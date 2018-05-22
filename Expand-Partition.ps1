Function Expand-Partition {
    <#
    .SYNOPSIS
        Simple tool to resize partition on Windows Server 2012+
    .DESCRIPTION
        Simple tool to resize partition on Windows Server 2012+

        User is prompted with a list of partitions that can be selected with Out-GridView to expand
    .PARAMETER Name
        ComputerName to expand a partition that has already been extended on in VMWare or SAN. Can accept pipeline input from Get-ADComputer

    .PARAMETER Credential
        Accepts a PSCreditial object passed to a remote computer via -Credential or creating a new CimSession using the credential

    .EXAMPLE
        Expand-Partition -ComputerName server101

    .NOTES
        Author:         Ryan Bushe / Martin Pugh
           
        Changelog:
            1.0         Initial Release
            1.1         Added Credential Parameter and Pester tests
            1.2         MLP - Added Parameter sets, Show-HDSize, simplified OS check, added support for multiple computers and partition
                        selection.
            1.3         MLP - Complete rewrite. Removed partition piping--no one's ever going to use that. Out-Gridview now shows only partitions with 
                        unallocated space, and it will show how much that is.  
    #>
    [CmdletBinding()]    
    Param(
        [Alias("ComputerName")]    
        [string[]]$Name = $env:COMPUTERNAME,

        [pscredential]$Credential
    )

    Begin {
        Write-Verbose "$(Get-Date): Starting Expand-Partition"

        Function Show-HDSize {
            #Return disk size converted to closest size
            Param (
                [Parameter(ValueFromPipeline=$true)]
                [int64]$Size
            )

            Process {
                If ($Size -gt 1125899906842624)
                {
                    $Result = "{0:N2} PB" -f ($Size / 1PB)
                }
                ElseIf ($Size -gt 1099511627776)
                {
                    $Result = "{0:N2} TB" -f ($Size / 1TB)
                }
                ElseIf ($Size -gt 1073741824)
                {
                    $Result = "{0:N2} GB" -f ($Size / 1GB)
                }
                Else
                {
                    $Result = "{0:N2} MB" -f ($Size / 1MB)
                }
                Return $Result
            }
        }
    }

    Process {
        ForEach ($Computer in $Name)
        {
            Write-Verbose "$(Get-Date): Working on $Computer"
            Write-Verbose "$(Get-Date): Checking OS version"
            $CimSplat = @{
                ComputerName = $Computer
            }
            If ($Credential)
            {
                $CimSplat.Add("Credential",$Credential)
            }

            Try {
                $CimSession = New-CimSession @CimSplat -ErrorAction Stop
                $OS = Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $CimSession -ErrorAction Stop | Select -ExpandProperty Caption
            }
            Catch {
                Write-Error "Unable to get OS for $Computer because ""$($_)""" -ErrorAction Stop
            } 
            If ($OS -match "200[038]")
            {
                Write-Error "This is only supported on Windows Server 2012+" -ErrorAction Stop
            }

            Write-Verbose "$(Get-Date): Select Partitions"
            
            #Rescan disks
            Update-HostStorageCache -CimSession $CimSession

            #Identify disks with unallocated space
            $UnallocatedDisks = Get-Disk -CimSession $CimSession -PipelineVariable $UnallocatedDisks | Where { $_.Size -ne $_.AllocatedSize }
            $UnallocatedPartitions = ForEach ($Disk in $UnallocatedDisks)
            {
                $Partition = $Disk | Get-Partition -CimSession $CimSession | Where Type -notmatch "Unknown|Reserved"
                [PSCustomObject]@{
                    DriveLetter      = $Partition.DriveLetter
                    Size             = Show-HDSize ([convert]::ToInt64($Disk.Size))
                    UnallocatedSpace = Show-HDSize ([convert]::ToInt64($Disk.Size - $Disk.AllocatedSize))
                    DiskNumber       = $Disk.Number
                    PartitionNumber  = $Partition.PartitionNumber
                }
            }

            #Select drive(s) you want to expand
            $UAPartitions = $UnallocatedPartitions | Sort DriveLetter | Out-GridView -OutputMode Multiple -Title "$($Computer): Select the partitions you wish to expand"
            If ($UAPartitions)
            {
                ForEach ($UAPartition in $UAPartitions)
                {
                    $Partition = Get-Partition -CimSession $CimSession -DiskNumber $UAPartition.DiskNumber -PartitionNumber $UAPartition.PartitionNumber
                    Write-Verbose "$(Get-Date): Getting MaxSize for $($Partition.DriveLetter) (sometimes takes a couple of minutes)..."
                    $MaxSize =  $Partition | Get-PartitionSupportedSize -CimSession $CimSession -ErrorAction Stop | Select -ExpandProperty SizeMax
                    If ($MaxSize -ne $Partition.Size)
                    {
                        Write-Verbose "$(Get-Date): Extending the drive for $($Partition.DriveLetter)"
                        $Partition | Resize-Partition -CimSession $CimSession -Size $MaxSize -ErrorAction Stop
                    }
                    Else
                    {
                        Write-Error "Drive is unable to be expanded because it is already at the full size. Verify the drive has been expanded in VMWare or the SAN" -ErrorAction Stop
                    }

                    $NewPartition = Get-Partition -CimSession $CimSession -DiskNumber $UAPartition.DiskNumber -PartitionNumber $UAPartition.PartitionNumber
                    [PSCustomObject]@{
                        ComputerName    = $Computer
                        DriveLetter     = $Partition.DriveLetter
                        PartitionNumber = $Partition.PartitionNumber
                        DiskNumber      = $Partition.DiskNumber
                        PreviousSize    = Show-HDSize -Size $Partition.Size
                        NewSize         = Show-HDSize -Size $NewPartition.Size
                    }
                }
            }
        }
    }

    End {
        Write-Verbose "$(Get-Date): Ending Expand-Partition"
    }
}
