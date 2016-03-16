function Expand-Partition {
<#
    .SYNOPSIS
        Simple tool to resize partition on Windows Server 2012+
    .DESCRIPTION
        Simple tool to resize partition on Windows Server 2012+

        User is prompted with a list of partitions that can be selected with Out-GridView to expand
    .PARAMETER ComputerName
        ComputerName to expand a partition that has already been extended on in VMWare or SAN
    .EXAMPLE
        Expand-Partition -ComputerName bushe101
    .NOTES
        Author:         Ryan Bushe  
           
        Changelog:
            1.0         Initial Release
    #>    
    param(
        [string]$ComputerName
    )
    if((Get-WmiObject -ComputerName $ComputerName -Class Win32_OperatingSystem | Select -ExpandProperty Caption) -like "*2008*" -or (Get-WmiObject -ComputerName $ComputerName -Class Win32_OperatingSystem | Select -ExpandProperty Caption) -like "*2003*"){
        Write-Verbose "This is only supported on Windows Server 2012+" -Verbose
        return
    }
    $Partitions = Get-Partition -CimSession $ComputerName | ? Type -ne "Reserved" | Out-GridView -PassThru
    if($Partitions){
        foreach($Partition in $Partitions){
            Update-HostStorageCache -CimSession $ComputerName
            $MaxSize =  ($Partition | Get-PartitionSupportedSize -CimSession $ComputerName).SizeMax
            Try{
                $Partition | Resize-Partition -CimSession $ComputerName -Size $MaxSize -ErrorAction Stop
            }
            Catch{
                $ErrorMessage = $_.Exception.Message
                If($ErrorMessage -like "*Size Not Supported*"){
                    Write-Verbose "Drive is unable to be expanded because it is already at the full size. Verify the drive has been expanded in VMWare or the SAN" -Verbose
                }
                Else{
                    Write-Error $ErrorMessage
                }
            }

            [pscustomobject]@{
                "DriveLetter"=$Partition.DriveLetter
                "PartitionNumber"=$Partition.PartitionNumber
                "DiskNumber"=$Partition.DiskNumber
                "PreviousSize"="$('{0:N2}' -f(($Partition | Select -ExpandProperty Size)/1024/1024/1024)) GB"
                "CurrentSize"="$('{0:N2}' -f(($Partition | Get-Partition -CimSession $ComputerName | Select -ExpandProperty Size)/1024/1024/1024)) GB"
                "ComputerName"=$ComputerName
            }
        }
    }
}