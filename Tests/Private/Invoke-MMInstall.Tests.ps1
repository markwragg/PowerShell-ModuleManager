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

    It "Uses the default when the package manager that installed the module isn't available" {
        InModuleScope ModuleManager {
            Mock Get-MMBackend { 'PSResourceGet' }
            Mock Get-Command -ParameterFilter { $Name -eq 'PowerShellGet\Install-Module' } {}
            Invoke-MMInstall -Name MMAlpha -Version 2.0.0 -Repository PSGallery -Scope CurrentUser -InstalledBy PowerShellGet
            Should -Invoke Install-PSResource -Times 1 -Exactly
            Should -Invoke Install-Module -Times 0 -Exactly
        }
    }
}
