BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Get-ManagedModule' {

    It 'Returns one object per module with the newest version first' {
        $alpha = Get-ManagedModule MMAlpha
        $alpha.Name | Should -Be 'MMAlpha'
        $alpha.Version | Should -Be '2.0.0-beta1'
        $alpha.Prerelease | Should -Be 'beta1'
        $alpha.VersionCount | Should -Be 4
        $alpha.Versions | Should -Be @('2.0.0-beta1', '1.1.0', '1.0.0', '0.9')
        $alpha.Repository | Should -Be 'PSGallery'
        $alpha.Description | Should -Be 'Fake module MMAlpha'
        $alpha.PSObject.TypeNames | Should -Contain 'ModuleManager.ModuleInfo'
    }

    It 'Scans modules in name order, and versions in version order, on every platform' {
        # Folder order is unspecified on Linux; 10.0 before 9.0 would also show a text sort.
        New-FakeModule $UserRoot 'mmOrder' '10.0' | Out-Null
        New-FakeModule $UserRoot 'mmOrder' '9.0' | Out-Null
        New-FakeModule $UserRoot 'MMAardvark' '1.0' | Out-Null
        try {
            $scanned = @(InModuleScope ModuleManager { Get-MMInstalledVersion -Name 'MMAardvark', 'MMAlpha', 'mmOrder' -Scope CurrentUser, Other })
            @($scanned | ForEach-Object { "$($_.Name) $($_.Version)" }) | Should -Be @(
                'MMAardvark 1.0', 'MMAlpha 1.0.0', 'MMAlpha 1.1.0', 'MMAlpha 2.0.0-beta1', 'mmOrder 9.0', 'mmOrder 10.0', 'MMAlpha 0.9'
            )
        }
        finally { Reset-FakeModules }
    }

    It 'Ignores commented-out manifest keys' {
        (Get-ManagedModule MMGamma).Prerelease | Should -BeNullOrEmpty
    }

    It 'Reads unversioned module folders' {
        $beta = Get-ManagedModule MMBeta
        $beta.Version | Should -Be '0.5.0'
        $beta.IsManaged | Should -BeFalse
    }

    It 'Reads install metadata in <Format> format' -ForEach @(
        @{ Name = 'MMAlpha'; Format = 'DT' }
        @{ Name = 'MMGamma'; Format = 'Obj (PowerShellGet)' }
    ) {
        $i = Get-ManagedModule $Name -AllVersions | Select-Object -First 1
        $i.IsManaged | Should -BeTrue
        $i.InstalledDate | Should -BeOfType [datetime]
        $i.InstalledDate.ToUniversalTime().Year | Should -Be 2025
    }

    It 'Uses UpdatedDate as the install date when it is later (Update-Module keeps the first InstalledDate)' -ForEach @(
        @{ Updated = '2026-03-04T05:06:07.0000000+00:00'; Expected = '2026-03-04' }
        @{ Updated = '2024-03-04T05:06:07.0000000+00:00'; Expected = '2025-01-02' }
    ) {
        New-FakeModule $UserRoot 'MMUpdated' '1.0' -Repository PSGallery -ObjDate -UpdatedDate $Updated | Out-Null
        try {
            $i = Get-ManagedModule MMUpdated -AllVersions
            $i.InstalledDate.ToUniversalTime().ToString('yyyy-MM-dd') | Should -Be $Expected
        }
        finally { Reset-FakeModules }
    }

    It 'Reads RequiredModules' {
        (Get-ManagedModule MMDependent).Installations[0].RequiredModules | Should -Be @('MMGamma')
    }

    It 'Filters with -MultipleVersions' {
        (Get-ManagedModule -MultipleVersions).Name | Should -Be @('MMAlpha')
    }

    It 'Lists each version with -AllVersions' {
        @(Get-ManagedModule MMAlpha -AllVersions).Count | Should -Be 4
    }

    It 'Supports wildcards and pipeline input' {
        @('MMB*', 'MMG*' | Get-ManagedModule).Name | Should -Be @('MMBeta', 'MMGamma')
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
            $deps = (Get-ManagedModule MMRoll).Dependencies
            $deps.Name | Should -Be @('MMRoll.Core', 'MMRoll.Extra')
            $deps.VersionRange | Should -Be @('[2.0.0]', '[1.0.0]')
        }

        It 'Reads version ranges from PowerShellGet install metadata for every version' {
            $old = Get-ManagedModule MMRoll -AllVersions | Where-Object Version -EQ '1.0.0'
            $old.Dependencies.VersionRange | Should -Be @('[1.0.0]', '[1.0.0]')
        }

        It 'Falls back to RequiredModules and versioned ModuleList entries in the manifest' {
            $m = Get-ManagedModule MMManual
            $m.Dependencies.Name | Should -Be @('MMBeta', 'MMGamma')
            $m.Dependencies.VersionRange | Should -Be @('[0.5.0]', '[3.0.0, )')
            $m.Installations[0].RequiredModules | Should -Be @('MMBeta')
        }
    }

    Context 'Size and reclaimable space' {

        BeforeAll {
            function Add-Blob([string]$Root, [string]$Name, [string]$Version, [int]$KB) {
                $path = Join-Path (Join-Path (Join-Path $Root $Name) $Version) 'blob.bin'
                [IO.File]::WriteAllBytes($path, [byte[]]::new($KB * 1KB))
            }
        }

        BeforeEach {
            Reset-FakeModules
            Add-FakeFamily
            # Temp folders may not be classified as CurrentUser on every OS; make removals allowed.
            Mock -ModuleName ModuleManager Get-MMScope { 'CurrentUser' }
            Add-Blob $script:UserRoot 'MMAlpha' '2.0.0' 2048       # newest (2.0.0-beta1): kept
            Add-Blob $script:UserRoot 'MMAlpha' '1.0.0' 1024
            Add-Blob $script:OtherRoot 'MMAlpha' '0.9' 512
            Add-Blob $script:UserRoot 'MMRoll' '1.0.0' 1024        # old, and nothing needs it
            Add-Blob $script:UserRoot 'MMRoll.Core' '1.0.0' 1024   # old, but MMRoll 1.0.0 pins it
            Add-Blob $script:UserRoot 'MMRoll.Core' '2.0.0' 1024   # old, but MMRoll 2.0.0 pins it
        }

        AfterAll { Reset-FakeModules }

        It 'Adds the size of every version, and what removing the old ones would free' {
            $alpha = Get-ManagedModule MMAlpha -IncludeSize
            $alpha.SizeMB | Should -Be 3.5
            $alpha.ReclaimableMB | Should -Be 1.5
            $alpha.PSObject.TypeNames[0] | Should -Be 'ModuleManager.ModuleInfo.Size'
        }

        It 'Leaves out old versions that modules staying installed depend on' {
            # MMRoll isn't asked for, so both its versions stay, and their pins hold MMRoll.Core's old versions back.
            $core = Get-ManagedModule MMRoll.Core -IncludeSize
            $core.SizeMB | Should -Be 2.0
            $core.ReclaimableMB | Should -Be 0
        }

        It 'Counts a family together, as removing its old versions would' {
            # Removing MMRoll 1.0.0 frees the MMRoll.Core 1.0.0 it pins; MMRoll 2.0.0 still pins MMRoll.Core 2.0.0.
            $m = @(Get-ManagedModule MMRoll, MMRoll.Core -IncludeSize)
            ($m | Where-Object Name -EQ 'MMRoll').ReclaimableMB | Should -Be 1.0
            ($m | Where-Object Name -EQ 'MMRoll.Core').ReclaimableMB | Should -Be 1.0
        }

        It 'Matches what Uninstall-ManagedModule -OldVersions frees' {
            $expected = (Get-ManagedModule -IncludeSize | Measure-Object ReclaimableMB -Sum).Sum
            $removed = @(Uninstall-ManagedModule -OldVersions -Confirm:$false -PassThru -InformationAction SilentlyContinue)
            ($removed | Measure-Object SizeMB -Sum).Sum | Should -Be $expected
            $expected | Should -Be 3.5
        }

        It 'Adds each version''s size with -AllVersions' {
            $sizes = @(Get-ManagedModule MMAlpha -AllVersions -IncludeSize | ForEach-Object { $_.SizeMB })
            $sizes | Should -Be @(2.0, 0.0, 1.0, 0.5)
        }

        It 'Adds no size properties without -IncludeSize' {
            $alpha = Get-ManagedModule MMAlpha
            $alpha.PSObject.Properties['SizeMB'] | Should -BeNullOrEmpty
            $alpha.PSObject.Properties['ReclaimableMB'] | Should -BeNullOrEmpty
            $alpha.PSObject.TypeNames | Should -Not -Contain 'ModuleManager.ModuleInfo.Size'
        }
    }
}
