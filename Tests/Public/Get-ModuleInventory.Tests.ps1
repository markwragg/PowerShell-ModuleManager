BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Get-ModuleInventory' {

    It 'Returns one object per module with the newest version first' {
        $alpha = Get-ModuleInventory MMAlpha
        $alpha.Name | Should -Be 'MMAlpha'
        $alpha.Version | Should -Be '2.0.0-beta1'
        $alpha.Prerelease | Should -Be 'beta1'
        $alpha.VersionCount | Should -Be 4
        $alpha.Versions | Should -Be @('2.0.0-beta1', '1.1.0', '1.0.0', '0.9')
        $alpha.Repository | Should -Be 'PSGallery'
        $alpha.Description | Should -Be 'Fake module MMAlpha'
        $alpha.PSObject.TypeNames | Should -Contain 'ModuleManager.ModuleInfo'
    }

    It 'Ignores commented-out manifest keys' {
        (Get-ModuleInventory MMGamma).Prerelease | Should -BeNullOrEmpty
    }

    It 'Reads unversioned module folders' {
        $beta = Get-ModuleInventory MMBeta
        $beta.Version | Should -Be '0.5.0'
        $beta.IsManaged | Should -BeFalse
    }

    It 'Reads install metadata in <Format> format' -ForEach @(
        @{ Name = 'MMAlpha'; Format = 'DT' }
        @{ Name = 'MMGamma'; Format = 'Obj (PowerShellGet)' }
    ) {
        $i = Get-ModuleInventory $Name -AllVersions | Select-Object -First 1
        $i.IsManaged | Should -BeTrue
        $i.InstalledDate | Should -BeOfType [datetime]
        $i.InstalledDate.ToUniversalTime().Year | Should -Be 2025
    }

    It 'Reads RequiredModules' {
        (Get-ModuleInventory MMDependent).Installations[0].RequiredModules | Should -Be @('MMGamma')
    }

    It 'Filters with -MultipleVersions' {
        (Get-ModuleInventory -MultipleVersions).Name | Should -Be @('MMAlpha')
    }

    It 'Lists each version with -AllVersions' {
        @(Get-ModuleInventory MMAlpha -AllVersions).Count | Should -Be 4
    }

    It 'Supports wildcards and pipeline input' {
        @('MMB*', 'MMG*' | Get-ModuleInventory).Name | Should -Be @('MMBeta', 'MMGamma')
    }

    Context 'Dependencies' {

        BeforeAll {
            Add-FakeFamily
            New-FakeModule $script:UserRoot 'MMManual' '1.0.0' -ManifestText @"
RequiredModules = @(@{ ModuleName = 'MMBeta'; RequiredVersion = '0.5.0' })
    ModuleList = @(@{ModuleName = 'MMGamma'; ModuleVersion = '3.0.0'; }, 'Nested\Thing.psm1')
"@ | Out-Null
        }

        It 'Reads version ranges from PSResourceGet install metadata' {
            $deps = (Get-ModuleInventory MMRoll).Dependencies
            $deps.Name | Should -Be @('MMRoll.Core', 'MMRoll.Extra')
            $deps.VersionRange | Should -Be @('[2.0.0]', '[1.0.0]')
        }

        It 'Reads version ranges from PowerShellGet install metadata for every version' {
            $old = Get-ModuleInventory MMRoll -AllVersions | Where-Object Version -EQ '1.0.0'
            $old.Dependencies.VersionRange | Should -Be @('[1.0.0]', '[1.0.0]')
        }

        It 'Falls back to RequiredModules and versioned ModuleList entries in the manifest' {
            $m = Get-ModuleInventory MMManual
            $m.Dependencies.Name | Should -Be @('MMBeta', 'MMGamma')
            $m.Dependencies.VersionRange | Should -Be @('[0.5.0]', '[3.0.0, )')
            $m.Installations[0].RequiredModules | Should -Be @('MMBeta')
        }
    }
}
