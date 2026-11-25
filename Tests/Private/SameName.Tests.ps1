BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
    # Two different modules named MMSame, like the TLS module that ships with Windows and the
    # community TLS module in the PowerShell Gallery: one copied in, one installed from the gallery.
    $script:OwnGuid = '1e28c697-2370-42f2-ace1-5ac8777f8053'
    New-FakeModule $script:OtherRoot 'MMSame' '2.0.0' -Guid "{$($script:OwnGuid.ToUpperInvariant())}" | Out-Null
    New-FakeModule $script:UserRoot 'MMSame' '1.0.5' -Repository PSGallery | Out-Null
    New-FakeModule $script:UserRoot 'MMSame' '1.0.4' -Repository PSGallery | Out-Null
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Different modules with the same name' {

    It 'Lists them as separate modules, the one installed from the repository first' {
        $m = @(Get-ManagedModule MMSame)
        $m.Count | Should -Be 2
        $m[0].Key | Should -Be 'mmsame'
        @($m[0].Versions) | Should -Be @('1.0.5', '1.0.4')
        $m[1].Key | Should -Be "mmsame|$($script:OwnGuid)"
        @($m[1].Versions) | Should -Be @('2.0.0')
    }

    It "Doesn't count one as an old version of the other" {
        # What Uninstall-ManagedModule -OldVersions removes.
        $old = InModuleScope ModuleManager { Get-MMOldVersion -Installation @(Get-MMInstalledVersion -IncludeSystem) -Name MMSame }
        @($old.Removable | ForEach-Object { [string]$_.Version }) | Should -Be @('1.0.4')
        $info = @(Get-ManagedModule MMSame -IncludeSize)
        $info[1].ReclaimableMB | Should -Be 0
    }

    It "Compares each with the repository's module of that name by its own GUID" {
        InModuleScope ModuleManager -Parameters @{ Guid = Get-FakeModuleGuid 'MMSame' } {
            $script:MMGalleryCache[(Get-MMCacheKey 'MMSame' 'PSGallery' $false)] = [pscustomobject]@{
                RequestedName = 'MMSame'; Name = 'MMSame'; Repository = 'PSGallery'; Prerelease = $false; Status = 'Found'
                Version = '1.0.6'; ModuleVersion = [version]'1.0.6'; PrereleaseLabel = $null; PublishedDate = [datetime]::UtcNow
                Error = $null; CachedAt = [datetime]::UtcNow; Guid = $Guid; Dependencies = @()
            }
        }
        $u = @(Get-ManagedModuleUpdate MMSame)
        $u.Count | Should -Be 2
        $u[0].InstalledVersion | Should -Be '1.0.5'
        $u[0].Status | Should -Be 'UpdateAvailable'
        $u[1].InstalledVersion | Should -Be '2.0.0'
        $u[1].Status | Should -Be 'NotInRepository'
        $u[1].Error | Should -Match 'is a different module with the same name'
    }

    It 'Shows them as separate rows in the terminal UI, and keeps the details view on the right one' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions; OwnGuid = $script:OwnGuid } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s; Update-MMTuiVisible $s
            $rows = @($s.Visible | Where-Object Name -EQ 'MMSame')
            $rows.Count | Should -Be 2
            # The main module first, in either edition (Windows PowerShell's Sort-Object doesn't keep ties in order).
            $rows[0].Key | Should -Be 'mmsame'
            $rows[1].Key | Should -Be "mmsame|$OwnGuid"

            # The cursor stays on the second MMSame, not the first, when the rows are worked out again.
            Set-MMTuiCursor $s ([array]::IndexOf($s.Visible, $rows[1]))
            Update-MMTuiVisible $s
            $s.Visible[$s.Cursor].Key | Should -Be $rows[1].Key

            $s.Detail = $rows[1]
            $s.Mode = 'details'
            Update-MMTuiRows $s
            Sync-MMTuiDetail $s
            $s.Detail.Key | Should -Be $rows[1].Key
            @($s.Detail.Info.Versions) | Should -Be @('2.0.0')
        }
    }
}

Describe 'Group-MMInstallation' {

    BeforeAll {
        function Get-FakeInstall([string]$Version, [string]$Guid, [string]$Repository, [string]$Scope = 'CurrentUser') {
            [pscustomobject]@{
                Name = 'MMX'; Version = $Version; ModuleVersion = [version]$Version; Prerelease = $null; Scope = $Scope
                Repository = $Repository; IsManaged = [bool]$Repository; IsLoaded = $false; ModuleBase = "C:\fake\$Scope\MMX\$Version"
                Description = $null; Guid = $Guid; ProjectUri = $null; Dependencies = @()
            }
        }
        $script:A = 'aaaaaaaa-0000-0000-0000-000000000000'
        $script:B = 'bbbbbbbb-0000-0000-0000-000000000000'
    }

    It 'Keeps versions installed from a repository together, whatever their GUIDs (<Case>)' -ForEach @(
        @{ Case = 'the publisher changed the GUID'; Second = 'bbbbbbbb-0000-0000-0000-000000000000' }
        @{ Case = 'no GUID'; Second = $null }
    ) {
        $m = @(InModuleScope ModuleManager -Parameters @{ I = @((Get-FakeInstall '2.0' $B 'PSGallery'), (Get-FakeInstall '1.0' $A 'PSGallery')) } { Group-MMInstallation -Installation $I })
        $m.Count | Should -Be 1
        $m[0].VersionCount | Should -Be 2
        $m[0].Key | Should -Be 'mmx'
    }

    It 'Puts a version copied in by hand with the module that has its GUID, or with the main one when it has none' {
        $installs = @(
            (Get-FakeInstall '2.0' $A 'PSGallery'), (Get-FakeInstall '1.0' $B 'PSGallery')
            (Get-FakeInstall '0.9' "{$($B.ToUpperInvariant())}" $null 'Other'), (Get-FakeInstall '0.8' $null $null 'Other')
        )
        $m = @(InModuleScope ModuleManager -Parameters @{ I = $installs } { Group-MMInstallation -Installation $I })
        $m.Count | Should -Be 1
        $m[0].VersionCount | Should -Be 4
    }

    It 'Makes the module with the newest version the main one when none was installed from a repository' {
        $installs = @((Get-FakeInstall '1.0' $A $null 'Other'), (Get-FakeInstall '3.0' $B $null 'System'), (Get-FakeInstall '0.1' $null $null 'Other'))
        $m = @(InModuleScope ModuleManager -Parameters @{ I = $installs } { Group-MMInstallation -Installation $I })
        $m.Count | Should -Be 2
        $m[0].Key | Should -Be 'mmx'
        @($m[0].Versions) | Should -Be @('3.0', '0.1')
        $m[1].Key | Should -Be "mmx|$A"
    }
}
