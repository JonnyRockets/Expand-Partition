function Expand-Partition {
<#
    .SYNOPSIS
        Simple tool to resize partition on Windows Server 2012+
    .DESCRIPTION
        Simple tool to resize partition on Windows Server 2012+

        User is prompted with a list of partitions that can be selected with Out-GridView to expand
    .PARAMETER Disk
        Partition object from Get-Partition that can be passed via the pipeline
    .PARAMETER ComputerName
        ComputerName to expand a partition that has already been extended on in VMWare or SAN
    .PARAMETER Credential
        Accepts a PSCreditial object passed to a remote computer via -Credential or creating a new CimSession using the credential
    .EXAMPLE
        Expand-Partition -ComputerName bushe101
    .NOTES
        Author:         Ryan Bushe  
           
        Changelog:
            1.0         Initial Release
            1.1         Added Credential Parameter and Pester tests
    #>
    [CmdletBinding()]    
    param(
        [parameter(ValueFromPipeline)]
        [CimInstance]$InputObject,        
        [string]$ComputerName="localhost",
        [pscredential]$Credential
    )
    if($InputObject.PSComputerName){
        $ComputerName = $InputObject.PSComputerName
    }
    
    if($Credential){
        if((Get-WmiObject -ComputerName $ComputerName -Credential $Credential -Class Win32_OperatingSystem | Select -ExpandProperty Caption) -like "*2008*" -or (Get-WmiObject -ComputerName $ComputerName -Credential $Credential -Class Win32_OperatingSystem | Select -ExpandProperty Caption) -like "*2003*"){
            Write-Error "This is only supported on Windows Server 2012+"
            return
        }        
        $CimSession = New-CimSession -Credential $Credential -ComputerName $ComputerName
    }
    else{
        if((Get-WmiObject -ComputerName $ComputerName -Class Win32_OperatingSystem | Select -ExpandProperty Caption) -like "*2008*" -or (Get-WmiObject -ComputerName $ComputerName -Class Win32_OperatingSystem | Select -ExpandProperty Caption) -like "*2003*"){
            Write-Error "This is only supported on Windows Server 2012+"
            return
        }
        $CimSession = $ComputerName        
    }
    
    if($InputObject){
        $Partitions = @($InputObject)
    }
    else{
        $Partitions = Get-Partition -CimSession $CimSession | ? Type -ne "Reserved" | Out-GridView -PassThru
    }
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
                "PreviousSize"="$('{0:N2}' -f(($Partition | Select -ExpandProperty Size)/1024/1024/1024)) GB"
                "CurrentSize"="$('{0:N2}' -f(($Partition | Get-Partition -CimSession $CimSession | Select -ExpandProperty Size)/1024/1024/1024)) GB"
                "ComputerName"=$CimSession
            }
        }
    }
}