BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    # The package managers' install commands are mocked, so the real modules must be loaded and visible
    # from inside the module under test (see GalleryLookup.Tests.ps1).
    Import-Module Microsoft.PowerShell.PSResourceGet, PowerShellGet -Global -ErrorAction SilentlyContinue
    Initialize-MMTestEnvironment
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Invoke-MMInstall' {

    BeforeAll {
        $script:HasBoth = [bool](Get-Command -Name Install-PSResource -ErrorAction Ignore) -and
            [bool](Get-Command -Name Install-Module -ErrorAction Ignore)
    }

    BeforeEach {
        if (-not $script:HasBoth) { Set-ItResult -Skipped -Because 'PSResourceGet and PowerShellGet are not both installed'; return }
        Mock -ModuleName ModuleManager Install-PSResource {}
        Mock -ModuleName ModuleManager Install-Module {}
    }

    It 'Installs with <Expected> when the module was installed by <InstalledBy> and the default is <Default>' -ForEach @(
        @{ Default = 'PSResourceGet'; InstalledBy = 'PowerShellGet'; Expected = 'PowerShellGet' }
        @{ Default = 'PowerShellGet'; InstalledBy = 'PSResourceGet'; Expected = 'PSResourceGet' }
        @{ Default = 'PSResourceGet'; InstalledBy = ''; Expected = 'PSResourceGet' }
        @{ Default = 'PowerShellGet'; InstalledBy = ''; Expected = 'PowerShellGet' }
    ) {
        InModuleScope ModuleManager -Parameters $_ {
            Mock Get-MMBackend { $Default }
            Invoke-MMInstall -Name MMAlpha -Version 2.0.0 -Repository PSGallery -Scope CurrentUser -InstalledBy $InstalledBy
            Should -Invoke Install-Module -Times ([int]($Expected -eq 'PowerShellGet')) -Exactly -ParameterFilter {
                $Name -eq 'MMAlpha' -and $RequiredVersion -eq '2.0.0' -and $Scope -eq 'CurrentUser'
            }
            Should -Invoke Install-PSResource -Times ([int]($Expected -eq 'PSResourceGet')) -Exactly -ParameterFilter {
                $Name -eq 'MMAlpha' -and $Version -eq '[2.0.0]' -and $Scope -eq 'CurrentUser'
            }
        }
    }

    It "Uses the default, with a warning, when the package manager that installed the module isn't available" {
        InModuleScope ModuleManager {
            Mock Get-MMBackend { 'PSResourceGet' }
            Mock Get-Command -ParameterFilter { $Name -eq 'PowerShellGet\Install-Module' } {}
            Invoke-MMInstall -Name MMAlpha -Version 2.0.0 -Repository PSGallery -Scope CurrentUser -InstalledBy PowerShellGet `
                -WarningVariable warnings -WarningAction SilentlyContinue
            Should -Invoke Install-PSResource -Times 1 -Exactly
            Should -Invoke Install-Module -Times 0 -Exactly
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Be ("MMAlpha was installed with PowerShellGet, which isn't available in this session, so 2.0.0 is being installed with PSResourceGet. " +
                "PowerShellGet's own commands, such as Update-Module or Get-InstalledModule, may not recognise the new version.")
        }
    }

    It "Doesn't warn when the package manager that installed the module is used, or there's no install record" {
        InModuleScope ModuleManager {
            Mock Get-MMBackend { 'PSResourceGet' }
            Invoke-MMInstall -Name MMAlpha -Version 2.0.0 -Repository PSGallery -Scope CurrentUser -InstalledBy PowerShellGet -WarningVariable w1
            Invoke-MMInstall -Name MMAlpha -Version 2.0.0 -Repository PSGallery -Scope CurrentUser -InstalledBy '' -WarningVariable w2
            $w1.Count + $w2.Count | Should -Be 0
        }
    }

    Context 'Prereleases with PowerShellGet 1.x' {
        BeforeEach {
            # PowerShellGet 1.x's Install-Module has no -AllowPrerelease.
            Mock -ModuleName ModuleManager Get-Command -ParameterFilter { $Name -eq 'PowerShellGet\Install-Module' } {
                [pscustomobject]@{ Name = 'Install-Module'; Parameters = @{ Name = $null; RequiredVersion = $null } }
            }
            Mock -ModuleName ModuleManager Get-MMBackend { 'PSResourceGet' }
        }

        It 'Installs a prerelease with PSResourceGet, with a warning' {
            InModuleScope ModuleManager {
                Mock Get-Command -ParameterFilter { $Name -eq 'Microsoft.PowerShell.PSResourceGet\Install-PSResource' } { [pscustomobject]@{ Name = 'Install-PSResource' } }
                Invoke-MMInstall -Name MMAlpha -Version 2.0.0-beta1 -Prerelease $true -Repository PSGallery -Scope CurrentUser `
                    -InstalledBy PowerShellGet -WarningVariable warnings -WarningAction SilentlyContinue
                Should -Invoke Install-PSResource -Times 1 -Exactly -ParameterFilter { $Version -eq '[2.0.0-beta1]' -and $Prerelease }
                Should -Invoke Install-Module -Times 0 -Exactly
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -BeLike "MMAlpha was installed with PowerShellGet, but this version of PowerShellGet can't install prereleases, so 2.0.0-beta1 is being installed with PSResourceGet. *Update-Module*"
            }
        }

        It 'Still installs a stable version with PowerShellGet' {
            InModuleScope ModuleManager {
                Invoke-MMInstall -Name MMAlpha -Version 2.0.0 -Repository PSGallery -Scope CurrentUser -InstalledBy PowerShellGet -WarningVariable warnings
                Should -Invoke Install-Module -Times 1 -Exactly
                Should -Invoke Install-PSResource -Times 0 -Exactly
                $warnings.Count | Should -Be 0
            }
        }

        It "Fails as before when PSResourceGet isn't available either" {
            InModuleScope ModuleManager {
                Mock Get-MMBackend { 'PowerShellGet' }
                Mock Get-Command -ParameterFilter { $Name -eq 'Microsoft.PowerShell.PSResourceGet\Install-PSResource' } {}
                { Invoke-MMInstall -Name MMAlpha -Version 2.0.0-beta1 -Prerelease $true -Repository PSGallery -Scope CurrentUser -InstalledBy PowerShellGet } |
                    Should -Throw "*can't install prerelease versions*"
                Should -Invoke Install-PSResource -Times 0 -Exactly
            }
        }
    }
}
