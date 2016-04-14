Import-Module $PSScriptRoot\..\Expand-Partition.ps1 -Force

Describe "Testing for Expand-Partition on PS$($PSVersionTable.PSVersion.Major)" {
    
    $FakePassword = ConvertTo-SecureString "FakePassword" -AsPlainText -Force
    $FakeCreds = New-Object System.Management.Automation.PSCredential ("FakeCreds", $FakePassword)

    Write-Verbose "Since no expansion is actually being done this speeds up the tests"
    Mock Update-HostStorageCache { return $null }

    Context "Test to not run on Server 2008" {
        Mock Get-WmiObject { return [PSCustomObject]@{ Caption = "Microsoft Windows Server 2008 R2 Standard"} } -ParameterFilter { $Class -eq "Win32_OperatingSystem" }

        It "should throw because it is below server 2012" {
            { Expand-Partition -ErrorAction Stop } | Should Throw
        }
    }

    Context "Test to not run on Server 2008 with Credential" {
        Mock Get-WmiObject { return [PSCustomObject]@{ Caption = "Microsoft Windows Server 2008 R2 Standard"} } -ParameterFilter { $Class -eq "Win32_OperatingSystem" }

        It "should throw because it is below server 2012" {
            { Expand-Partition -Credential $FakeCreds -ErrorAction Stop } | Should Throw
        }
    }

    Context "credentials are passed but no partitions are available" {
        Mock Get-Partition { return $null }
        Mock New-CimSession { "localhost" }
        Mock Get-WmiObject { return [PSCustomObject]@{ Caption = "Microsoft Windows Server 2012 R2 Standard"} } -ParameterFilter { $Class -eq "Win32_OperatingSystem" }

        It "should be null or empty because no partitions where found" {
            Expand-Partition -ComputerName "fakevm1" -Credential $FakeCreds | Should BeNullOrEmpty
        }
    }

    Context "C drive expand on localhost but fails because it is the max size" {
        $Partition = Get-Partition -DriveLetter C
        Mock Out-GridView { return $Partition}
        Mock Get-PartitionSupportedSize { return @{SizeMin = 0;SizeMax = ($Partition.Size)} }

        It "should throw because partition is already at the max size"{
            { Expand-Partition -ErrorAction Stop } | Should Throw
        }
    }

    Context "drive gets expanded" {
        $Partition = Get-Partition -DriveLetter C -CimSession localhost
        Mock Get-PartitionSupportedSize { return @{SizeMin = 0;SizeMax = ($Partition.Size*2)} }
        Mock Resize-Partition {return $null}
        
        It "should return an object of expanded drive" {
            $Result = $Partition | Expand-Partition
            $Result.DriveLetter | Should Be "C"
        }
    }

    Context "drive is in unknown state" {
        Mock Out-GridView { return $null}
        Mock Get-PartitionSupportedSize { return @{SizeMin = 0;SizeMax = ((Get-Partition -DriveLetter C).Size*2)} }
        Mock Resize-Partition {Throw "Unknown Error when resizing partition"}
        It "should throw because of unknown error" {
            { Expand-Partition -ErrorAction Stop } | Should Throw
        }
    }
}