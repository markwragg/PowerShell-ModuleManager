BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Uninstall-ManagedModule' {

    BeforeEach {
        Reset-FakeModules
        # Temp folders may not be classified as CurrentUser on every OS; make removals allowed.
        Mock -ModuleName ModuleManager Get-MMScope { 'CurrentUser' }
    }

    It 'Removes only the piped version when given Get-ModuleLocation output' {
        Get-ModuleLocation MMAlpha | Where-Object Version -EQ '1.0.0' | Uninstall-ManagedModule -Confirm:$false
        (Get-ModuleInventory MMAlpha).Versions | Should -Be @('2.0.0-beta1', '1.1.0', '0.9')
    }

    It 'Removes all versions when piped Get-ModuleInventory output' {
        Get-ModuleInventory MMAlpha | Uninstall-ManagedModule -Confirm:$false
        Get-ModuleInventory MMAlpha | Should -BeNullOrEmpty
    }

    It 'Removes specific versions by -Version wildcard' {
        Uninstall-ManagedModule MMAlpha -Version '1.*' -Confirm:$false
        (Get-ModuleInventory MMAlpha).Versions | Should -Be @('2.0.0-beta1', '0.9')
    }

    It 'Does nothing with -WhatIf' {
        Uninstall-ManagedModule MMAlpha -WhatIf
        (Get-ModuleInventory MMAlpha).VersionCount | Should -Be 4
    }

    It 'Refuses to remove a module other modules depend on' {
        { Uninstall-ManagedModule MMGamma -Confirm:$false -ErrorAction Stop } | Should -Throw '*required by: MMDependent*'
        Get-ModuleInventory MMGamma | Should -Not -BeNullOrEmpty
    }

    It 'Allows removing a dependency together with its dependents' {
        Uninstall-ManagedModule MMGamma, MMDependent -Confirm:$false
        Get-ModuleInventory MMGamma, MMDependent | Should -BeNullOrEmpty
    }

    It 'Removes a dependency with -Force' {
        Uninstall-ManagedModule MMGamma -Force -Confirm:$false
        Get-ModuleInventory MMGamma | Should -BeNullOrEmpty
    }

    It 'Refuses to remove System modules' {
        Mock -ModuleName ModuleManager Get-MMScope { 'System' }
        { Uninstall-ManagedModule MMBeta -Confirm:$false -ErrorAction Stop } | Should -Throw '*ships with PowerShell*'
    }

    It 'Errors for unknown modules' {
        { Uninstall-ManagedModule DoesNotExist -Confirm:$false -ErrorAction Stop } | Should -Throw '*No installed module*'
    }

    Context 'Version-aware dependencies' {

        BeforeEach { Add-FakeFamily }

        It 'Refuses to remove an exact version another module pins' {
            { Uninstall-ManagedModule MMRoll.Core -Version 2.0.0 -Confirm:$false -ErrorAction Stop } |
                Should -Throw '*MMRoll.Core 2.0.0*required by: MMRoll 2.0.0 needs `[2.0.0`]*'
            (Get-ModuleInventory MMRoll.Core).Versions | Should -Contain '2.0.0'
        }

        It 'Removes a version no remaining module needs' {
            Uninstall-ManagedModule MMRoll.Core -Version 3.0.0 -Confirm:$false
            (Get-ModuleInventory MMRoll.Core).Versions | Should -Be @('2.0.0', '1.0.0')
        }

        It 'Removes a whole family together' {
            Uninstall-ManagedModule MMRoll, MMRoll.* -Confirm:$false
            Get-ModuleInventory MMRoll* | Should -BeNullOrEmpty
        }
    }
}
