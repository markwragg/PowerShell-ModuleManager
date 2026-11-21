BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Uninstall-ManagedModule -OldVersions' {

    BeforeEach {
        Reset-FakeModules
        # Temp folders may not be classified as CurrentUser on every OS; make removals allowed.
        Mock -ModuleName ModuleManager Get-MMScope { 'CurrentUser' }
    }

    It 'Does nothing with -WhatIf' {
        Uninstall-ManagedModule -OldVersions -WhatIf
        (Get-ManagedModule MMAlpha).VersionCount | Should -Be 4
    }

    It 'Removes all but the newest version, leaving other files alone' {
        Uninstall-ManagedModule -OldVersions MMAlpha -Confirm:$false
        (Get-ManagedModule MMAlpha).Versions | Should -Be @('2.0.0-beta1')
        Test-Path (Join-Path $script:OtherRoot 'MMAlpha') | Should -BeFalse
        Test-Path (Join-Path (Join-Path $script:UserRoot 'MMAlpha') 'notes.zip') | Should -BeTrue
    }

    It 'Takes names from the pipeline, and outputs the removed versions with -PassThru' {
        $removed = @('MMAlpha', 'MMGamma' | Uninstall-ManagedModule -OldVersions -Confirm:$false -PassThru)
        @($removed | ForEach-Object { $_.Version }) | Should -Be @('1.1.0', '1.0.0', '0.9')
        (Get-ManagedModule MMAlpha).Versions | Should -Be @('2.0.0-beta1')
        (Get-ManagedModule MMGamma).Versions | Should -Be @('3.0.0')
    }

    It 'Outputs nothing without -PassThru' {
        Uninstall-ManagedModule MMAlpha -OldVersions -Confirm:$false | Should -BeNullOrEmpty
    }

    It 'Honours -Keep' {
        Uninstall-ManagedModule -OldVersions MMAlpha -Keep 2 -Confirm:$false
        (Get-ManagedModule MMAlpha).Versions | Should -Be @('2.0.0-beta1', '1.1.0')
    }

    Context 'Version-aware dependencies' {

        BeforeEach { Add-FakeFamily }

        It 'Keeps old versions that installed modules pin, with one warning' {
            Uninstall-ManagedModule -OldVersions MMRoll.Core -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
            (Get-ManagedModule MMRoll.Core).Versions | Should -Be @('3.0.0', '2.0.0', '1.0.0')
            @($warnings).Count | Should -Be 1
            $warnings[0] | Should -BeLike 'Keeping 2 old versions because other installed modules depend on them: MMRoll 1.0.0; MMRoll 2.0.0*'
        }

        It 'Removes old versions of a family together, keeping only what the newest versions pin' {
            Uninstall-ManagedModule -OldVersions MMRoll, MMRoll.* -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
            (Get-ManagedModule MMRoll).Versions | Should -Be @('2.0.0')
            (Get-ManagedModule MMRoll.Core).Versions | Should -Be @('3.0.0', '2.0.0')
            $warnings | Should -BeLike '*MMRoll.Core 2.0.0 because other installed modules depend on them: MMRoll 2.0.0*'
        }

        It 'Removes pinned versions with -Force' {
            Uninstall-ManagedModule -OldVersions MMRoll.Core -Force -Confirm:$false
            (Get-ManagedModule MMRoll.Core).Versions | Should -Be @('3.0.0')
        }
    }

    Context 'Versions it skips' {

        It 'Only removes versions in the given -Scope' {
            Mock -ModuleName ModuleManager Get-MMScope { if ($Path -like '*other*') { 'Other' } else { 'CurrentUser' } }
            $removed = @(Uninstall-ManagedModule -OldVersions MMAlpha -Scope Other -Confirm:$false -PassThru)
            @($removed | ForEach-Object { $_.Version }) | Should -Be @('0.9')
            (Get-ManagedModule MMAlpha).VersionCount | Should -Be 3
        }

        It 'Never removes versions that ship with PowerShell' {
            Mock -ModuleName ModuleManager Get-MMScope { if ($Path -like '*other*') { 'System' } else { 'CurrentUser' } }
            Uninstall-ManagedModule -OldVersions -Confirm:$false
            Test-Path (Join-Path (Join-Path $script:OtherRoot 'MMAlpha') '0.9') | Should -BeTrue
            (Get-ManagedModule MMAlpha).Versions | Should -Be @('2.0.0-beta1')
        }

        It 'Skips loaded versions, with a warning, unless -Force is used' {
            $base = Join-Path (Join-Path $script:UserRoot 'MMAlpha') '1.0.0'
            InModuleScope ModuleManager -Parameters @{ Base = $base } {
                $script:MMLoadedModule = @([pscustomobject]@{ Name = 'MMAlpha'; Version = [version]'1.0.0'; ModuleBase = $Base; PrivateData = $null })
            }
            try {
                Mock -ModuleName ModuleManager Remove-Module { }
                Uninstall-ManagedModule -OldVersions MMAlpha -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
                $warnings | Should -HaveCount 1
                $warnings[0] | Should -Match 'Skipping MMAlpha 1\.0\.0: it is loaded'
                Test-Path $base | Should -BeTrue

                Uninstall-ManagedModule -OldVersions MMAlpha -Force -Confirm:$false
                Test-Path $base | Should -BeFalse
            }
            finally { InModuleScope ModuleManager { $script:MMLoadedModule = $null } }
        }
    }
}
