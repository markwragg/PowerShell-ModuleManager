BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Uninstall-OldModuleVersion' {

    BeforeEach {
        Reset-FakeModules
        # Temp folders may not be classified as CurrentUser on every OS; make removals allowed.
        Mock -ModuleName ModuleManager Get-MMScope { 'CurrentUser' }
    }

    It 'Does nothing with -WhatIf' {
        Uninstall-OldModuleVersion -WhatIf
        (Get-ModuleInventory MMAlpha).VersionCount | Should -Be 4
    }

    It 'Removes all but the newest version, leaving other files alone' {
        Uninstall-OldModuleVersion MMAlpha -Confirm:$false
        (Get-ModuleInventory MMAlpha).Versions | Should -Be @('2.0.0-beta1')
        Test-Path (Join-Path $script:OtherRoot 'MMAlpha') | Should -BeFalse
        Test-Path (Join-Path (Join-Path $script:UserRoot 'MMAlpha') 'notes.zip') | Should -BeTrue
    }

    It 'Honours -Keep' {
        Uninstall-OldModuleVersion MMAlpha -Keep 2 -Confirm:$false
        (Get-ModuleInventory MMAlpha).Versions | Should -Be @('2.0.0-beta1', '1.1.0')
    }

    Context 'Version-aware dependencies' {

        BeforeEach { Add-FakeFamily }

        It 'Keeps old versions that installed modules pin, with one warning' {
            Uninstall-OldModuleVersion MMRoll.Core -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
            (Get-ModuleInventory MMRoll.Core).Versions | Should -Be @('3.0.0', '2.0.0', '1.0.0')
            @($warnings).Count | Should -Be 1
            $warnings[0] | Should -BeLike 'Keeping 2 old versions because other installed modules depend on them: MMRoll 1.0.0; MMRoll 2.0.0*'
        }

        It 'Removes old versions of a family together, keeping only what the newest versions pin' {
            Uninstall-OldModuleVersion MMRoll, MMRoll.* -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
            (Get-ModuleInventory MMRoll).Versions | Should -Be @('2.0.0')
            (Get-ModuleInventory MMRoll.Core).Versions | Should -Be @('3.0.0', '2.0.0')
            $warnings | Should -BeLike '*MMRoll.Core 2.0.0 because other installed modules depend on them: MMRoll 2.0.0*'
        }

        It 'Removes pinned versions with -Force' {
            Uninstall-OldModuleVersion MMRoll.Core -Force -Confirm:$false
            (Get-ModuleInventory MMRoll.Core).Versions | Should -Be @('3.0.0')
        }
    }
}
