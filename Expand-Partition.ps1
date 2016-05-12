function Expand-Partition {
<#
    .SYNOPSIS
        Simple tool to resize partition on Windows Server 2012+
    .DESCRIPTION
        Simple tool to resize partition on Windows Server 2012+

        User is prompted with a list of partitions that can be selected with Out-GridView to expand
    .PARAMETER PSComputerName
        Partition object from Get-Partition that can be passed via the pipeline
    .PARAMETER Name
        ComputerName to expand a partition that has already been extended on in VMWare or SAN. Can accept pipeline input from Get-ADComputer
    .PARAMETER Credential
        Accepts a PSCreditial object passed to a remote computer via -Credential or creating a new CimSession using the credential
    .EXAMPLE
        Expand-Partition -ComputerName bushe101
    .NOTES
        Author:         Ryan Bushe  
           
        Changelog:
            1.0         Initial Release
            1.1         Added Credential Parameter and Pester tests
            1.2         MLP - Added Parameter sets, Show-HDSize, simplified OS check, added support for multiple computers and partition
                        selection.
    #>
    [CmdletBinding(DefaultParameterSetName="cli")]    
    param(
        [parameter(ValueFromPipeline,ParameterSetName="getp")]
        [CimInstance]$PSComputerName,
        
        [Parameter(ValueFromPipelineByPropertyName,ParameterSetName="cli")]
        [Alias("ComputerName")]    
        [string[]]$Name="localhost",

        [pscredential]$Credential
    )

    Begin {
        Function Show-HDSize {
            #Return disk size converted to closest size
            Param (
                [int64]$Size
            )

            If ($Size -gt 1125899906842624)
            {
                $Result = "{0:N2} PB" -f $Size / 1PB
            }
            ElseIf ($Size -gt 1099511627776)
            {
                $Result = "{0:N2} TB" -f $Size / 1TB
            }
            ElseIf ($Size -gt 1073741824)
            {
                $Result = "{0:N2} GB" -f $Size / 1GB
            }
            Else
            {
                $Result = "{0:N2} MB" -f $Size / 1MB
            }
            Return $Result
        }
        $ComputerNames = @()
    }

    Process {
        If ($PsCmdlet.ParameterSetName -eq "getp")
        {
            If ($PSComputerName)
            {
                $ComputerNames += $PSComputerName
            }
            Else
            {
                $ComputerNames += "localhost"
            }
        }
    }

    End {
        If ($PsCmdlet.ParameterSetName -eq "getp")
        {
            $Name = $ComputerNames | Select -Unique
        }

        ForEach ($Computer in $Name)
        {
            $CimSplat = @{
                ComputerName = $Computer
            }
            If ($Credential)
            {
                $CimSplat.Add("Credential",$Credential)
            }

            If ((Get-CimInstance -ClassName Win32_OperatingSystem @CimSplat | Select -ExpandProperty Caption) -match "200[038]")
            {
                Write-Error "This is only supported on Windows Server 2012+"
                Return
            }
            $CimSession = New-CimSession @CimSplat
   
            $Partitions = Get-Partition -CimSession $CimSession | ? Type -ne "Reserved" | Out-GridView -OutputMode Multiple -Title "Select the partitions you wish to expand"
            if($Partitions){
                foreach($Partition in $Partitions){
                    Update-HostStorageCache -CimSession $CimSession
                    $MaxSize =  ($Partition | Get-PartitionSupportedSize -CimSession $CimSession).SizeMax
                    if($MaxSize -ne $Partition.Size){
                        $Partition | Resize-Partition -CimSession $CimSession -Size $MaxSize -ErrorAction Stop
                    }
                    else{
                        Write-Error "Drive is unable to be expanded because it is already at the full size. Verify the drive has been expanded in VMWare or the SAN" -ErrorAction Stop
                    }
                    [PSCustomObject]@{
                        "DriveLetter"=$Partition.DriveLetter
                        "PartitionNumber"=$Partition.PartitionNumber
                        "DiskNumber"=$Partition.DiskNumber
                        "PreviousSize"=Show-HDSize -Size $Partition.Size     #"$('{0:N2}' -f(($Partition | Select -ExpandProperty Size)/1024/1024/1024)) GB"
                        "CurrentSize"=Show-HDSize -Size ($Partition | Get-Partition -CimSession $CimSession).Size    #"$('{0:N2}' -f(($Partition | Get-Partition -CimSession $CimSession | Select -ExpandProperty Size)/1024/1024/1024)) GB"
                        "ComputerName"=$Computer
                    }
                }
            }
        }
    }
}