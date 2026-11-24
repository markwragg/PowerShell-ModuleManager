BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Remove-MMInstallation' {

    BeforeEach {
        Reset-FakeModules
        # Removal reports through the calling cmdlet, so call it from one.
        InModuleScope ModuleManager {
            function script:Invoke-TestRemoval {
                [CmdletBinding(SupportsShouldProcess)]
                param($Installation, [switch]$Force)
                Remove-MMInstallation -Installation $Installation -Cmdlet $PSCmdlet -Force:$Force
            }
            function script:Get-TestInstallation([string]$Name, [string]$Version, [hashtable]$Set = @{}) {
                $i = Get-MMInstalledVersion -Name $Name | Where-Object Version -EQ $Version
                foreach ($k in $Set.Keys) { $i.$k = $Set[$k] }
                $i
            }
        }
    }

    It 'Refuses a <Case>' -ForEach @(
        @{ Case = 'module that ships with PowerShell'; Set = @{ Scope = 'System' }; ErrorId = 'ModuleManager.SystemModule' }
        @{ Case = 'module for all users without elevation'; Set = @{ Scope = 'AllUsers' }; ErrorId = 'ModuleManager.RequiresElevation' }
        @{ Case = 'loaded module without -Force'; Set = @{ IsLoaded = $true }; ErrorId = 'ModuleManager.ModuleInUse' }
    ) {
        InModuleScope ModuleManager -Parameters $_ {
            Mock Test-MMIsAdmin { $false }
            $i = Get-TestInstallation 'MMAlpha' '1.0.0' $Set
            $errors = @()
            $removed = Invoke-TestRemoval -Installation $i -ErrorAction SilentlyContinue -ErrorVariable errors
            $removed | Should -BeFalse
            $errors[0].FullyQualifiedErrorId | Should -BeLike "$ErrorId*"
            Test-Path $i.ModuleBase | Should -BeTrue
        }
    }

    It 'Unloads a loaded module before removing it with -Force' {
        InModuleScope ModuleManager {
            $i = Get-TestInstallation 'MMAlpha' '1.0.0' @{ IsLoaded = $true }
            Mock Get-Module { [pscustomobject]@{ Name = 'MMAlpha'; ModuleBase = $i.ModuleBase } }
            Mock Remove-Module { }
            Invoke-TestRemoval -Installation $i -Force -Confirm:$false | Should -BeTrue
            Should -Invoke Remove-Module -Times 1
            Test-Path $i.ModuleBase | Should -BeFalse
        }
    }

    It 'Reports a folder that cannot be deleted' {
        InModuleScope ModuleManager {
            $i = Get-TestInstallation 'MMAlpha' '1.0.0'
            Mock Remove-Item { throw 'file is locked' } -ParameterFilter { $Recurse }
            $errors = @()
            Invoke-TestRemoval -Installation $i -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable errors | Should -BeFalse
            $own = @($errors | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -like 'ModuleManager.RemoveFailed*' })
            $own | Should -HaveCount 1
            $own[0].Exception.Message | Should -Match 'file is locked'
        }
    }

    It 'Removes the module folder too when its last version goes' {
        InModuleScope ModuleManager {
            $i = Get-TestInstallation 'MMGamma' '3.0.0'
            Invoke-TestRemoval -Installation $i -Confirm:$false | Should -BeTrue
            Test-Path (Split-Path $i.ModuleBase -Parent) | Should -BeFalse
        }
    }

    It 'Does nothing with -WhatIf, but counts what it would free' {
        InModuleScope ModuleManager {
            function script:Invoke-TestTally {
                [CmdletBinding(SupportsShouldProcess)]
                param($Installation, [hashtable]$Tally)
                Remove-MMInstallation -Installation $Installation -Cmdlet $PSCmdlet -Tally $Tally
            }
            $i = Get-TestInstallation 'MMGamma' '3.0.0'
            $bytes = (Get-ChildItem $i.ModuleBase -Recurse -File | Measure-Object Length -Sum).Sum
            $tally = @{}
            Invoke-TestTally -Installation $i -Tally $tally -WhatIf | Should -BeFalse
            Test-Path $i.ModuleBase | Should -BeTrue
            $tally.WhatIf | Should -Be 1
            $tally.WhatIfBytes | Should -Be $bytes
            $tally.Removed | Should -BeNullOrEmpty
        }
    }

    It 'Counts what it removes, and adds the size to the installation' {
        InModuleScope ModuleManager {
            function script:Invoke-TestTally {
                [CmdletBinding(SupportsShouldProcess)]
                param($Installation, [hashtable]$Tally)
                Remove-MMInstallation -Installation $Installation -Cmdlet $PSCmdlet -Tally $Tally
            }
            $i = Get-TestInstallation 'MMGamma' '3.0.0'
            $bytes = (Get-ChildItem $i.ModuleBase -Recurse -File | Measure-Object Length -Sum).Sum
            $tally = @{ Removed = 1; Bytes = 100L }
            $out = @(Invoke-TestTally -Installation $i -Tally $tally -Confirm:$false -Verbose 4>&1)
            $out | Should -Contain $true
            $verbose = @($out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and "$_" -like 'Removed *' })
            $verbose | Should -HaveCount 1
            "$($verbose[0])" | Should -BeLike "Removed MMGamma 3.0.0, $(Format-MMSize $bytes) from *"
            $tally.Removed | Should -Be 2
            $tally.Bytes | Should -Be (100 + $bytes)
            $i.SizeMB | Should -Be ([Math]::Round($bytes / 1MB, 1))
            Test-Path $i.ModuleBase | Should -BeFalse
        }
    }

    It 'Does not count a version it does not remove' {
        InModuleScope ModuleManager {
            function script:Invoke-TestTally {
                [CmdletBinding(SupportsShouldProcess)]
                param($Installation, [hashtable]$Tally)
                Remove-MMInstallation -Installation $Installation -Cmdlet $PSCmdlet -Tally $Tally
            }
            Mock Remove-Item { throw 'file is locked' } -ParameterFilter { $Recurse }
            $tally = @{}
            Invoke-TestTally -Installation (Get-TestInstallation 'MMGamma' '3.0.0') -Tally $tally -Confirm:$false -ErrorAction SilentlyContinue | Should -BeFalse
            $tally.Count | Should -Be 0
        }
    }
}
