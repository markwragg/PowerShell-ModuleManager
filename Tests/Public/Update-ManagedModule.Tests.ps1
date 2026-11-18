BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
    Set-FakeGalleryCache
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Update-ManagedModule' {

    BeforeEach {
        Mock -ModuleName ModuleManager Invoke-MMInstall {}
        Mock -ModuleName ModuleManager Get-MMScope { 'CurrentUser' }
    }

    It 'Installs updates into the existing scope via the package manager' {
        Update-ManagedModule MMAlpha, MMDependent -Confirm:$false
        Should -Invoke -ModuleName ModuleManager Invoke-MMInstall -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'MMAlpha' -and $Version -eq '2.0.0' -and $Scope -eq 'CurrentUser' -and $Repository -eq 'PSGallery' -and -not $Prerelease
        }
    }

    It 'Shows a progress bar while updating and clears it afterwards' {
        Mock -ModuleName ModuleManager Write-Progress {}
        Update-ManagedModule MMAlpha -Confirm:$false
        Should -Invoke -ModuleName ModuleManager Write-Progress -ParameterFilter {
            $Activity -eq 'Updating modules' -and $Status -like '1 of 1: MMAlpha*'
        }
        Should -Invoke -ModuleName ModuleManager Write-Progress -ParameterFilter {
            $Activity -eq 'Updating modules' -and $Completed
        }
    }

    It 'Reports a failed install as an error and carries on' {
        Mock -ModuleName ModuleManager Invoke-MMInstall { throw 'network down' }
        { Update-ManagedModule MMAlpha -Confirm:$false -ErrorAction Stop } | Should -Throw '*Failed to update MMAlpha*network down*'
    }

    It 'Does nothing with -WhatIf' {
        Get-ModuleUpdate -Outdated | Update-ManagedModule -WhatIf
        Should -Invoke -ModuleName ModuleManager Invoke-MMInstall -Times 0 -Exactly
    }

    Context 'Dependencies' {

        BeforeEach {
            Reset-FakeModules
            Add-FakeFamily
            Set-FakeGalleryCache
            $global:MMTestInstalls = [System.Collections.Generic.List[string]]::new()
            $env:MMTestUserRoot = $script:UserRoot
            # The rollup's latest version pins a newer MMRoll.Core, which also has an update.
            InModuleScope ModuleManager {
                $now = [datetime]::UtcNow
                foreach ($fake in @(
                        @{ Name = 'MMRoll'; Version = '3.0.0'; Deps = @(New-MMDependency 'MMRoll.Core' -VersionRange '[4.0.0]') }
                        @{ Name = 'MMRoll.Core'; Version = '4.0.0'; Deps = @() }
                        @{ Name = 'MMRoll.Extra'; Version = '1.0.0'; Deps = @() }
                        @{ Name = 'MMGamma'; Version = '4.0.0'; Deps = @() }
                    )) {
                    $script:MMGalleryCache[(Get-MMCacheKey $fake.Name 'PSGallery' $false)] = [pscustomobject]@{
                        RequestedName = $fake.Name; Name = $fake.Name; Repository = 'PSGallery'; Prerelease = $false; Status = 'Found'
                        Version = $fake.Version; ModuleVersion = [version]$fake.Version; PrereleaseLabel = $null
                        PublishedDate = $now; Dependencies = $fake.Deps; Error = $null; CachedAt = $now
                    }
                }
            }
            Mock -ModuleName ModuleManager Invoke-MMInstall {
                $global:MMTestInstalls.Add($Name)
                # Simulate the package manager pulling in a dependency.
                if ($Name -eq 'MMAlpha') {
                    $dir = Join-Path $env:MMTestUserRoot 'MMGamma\4.0.0'
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    "@{ ModuleVersion = '4.0.0' }" | Set-Content -LiteralPath (Join-Path $dir 'MMGamma.psd1')
                }
            }
        }

        AfterEach {
            Remove-Variable -Name MMTestInstalls -Scope Global -ErrorAction SilentlyContinue
            Remove-Item Env:\MMTestUserRoot -ErrorAction SilentlyContinue
        }

        It 'Updates dependencies before the modules that need them' {
            Update-ManagedModule MMRoll, MMRoll.Core -Confirm:$false
            $global:MMTestInstalls | Should -Be @('MMRoll.Core', 'MMRoll')
        }

        It 'Skips a module an earlier update installed as a dependency, and reports it' {
            $result = @(Update-ManagedModule MMAlpha, MMGamma -Confirm:$false -PassThru)
            $global:MMTestInstalls | Should -Be @('MMAlpha')
            $gamma = $result | Where-Object Name -EQ 'MMGamma'
            $gamma.Version | Should -Be '4.0.0'
            $gamma.UpdatedAsDependencyOf | Should -Be 'MMAlpha'
            ($result | Where-Object Name -EQ 'MMAlpha').UpdatedAsDependencyOf | Should -BeNullOrEmpty
        }

        It 'Warns before updating when a loaded module is older than a new version needs' {
            Mock -ModuleName ModuleManager Get-Module {
                [pscustomobject]@{ Name = 'MMRoll.Core'; Version = [version]'3.0.0'; PrivateData = $null; ModuleBase = 'C:\nowhere' }
            }
            Update-ManagedModule MMRoll -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings | Should -BeLike 'MMRoll.Core 3.0.0 is loaded in this session, but MMRoll 3.0.0 needs `[4.0.0`]*new session*'
        }

        It 'Removes old versions once, after all updates, keeping versions still pinned' {
            Mock -ModuleName ModuleManager Remove-OldModuleVersion {}
            Update-ManagedModule MMRoll, MMRoll.Core -RemoveOldVersions -Confirm:$false
            Should -Invoke -ModuleName ModuleManager Remove-OldModuleVersion -Times 1 -Exactly -ParameterFilter {
                ($Name | Sort-Object) -join ',' -eq 'MMRoll,MMRoll.Core'
            }
        }
    }
}
