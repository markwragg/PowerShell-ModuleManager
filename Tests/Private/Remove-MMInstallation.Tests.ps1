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

    It 'Does nothing with -WhatIf' {
        InModuleScope ModuleManager {
            $i = Get-TestInstallation 'MMGamma' '3.0.0'
            Invoke-TestRemoval -Installation $i -WhatIf | Should -BeFalse
            Test-Path $i.ModuleBase | Should -BeTrue
        }
    }
}
