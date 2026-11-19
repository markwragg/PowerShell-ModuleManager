BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Move-ManagedModule' {

    BeforeEach {
        Reset-FakeModules
        # The fake tree's 'user' folder stands in for CurrentUser, and 'other' for AllUsers.
        Mock -ModuleName ModuleManager Get-MMScope { if ($Path -match 'MMTests_\w+[\\/]other([\\/]|$)') { 'AllUsers' } else { 'CurrentUser' } }
        Mock -ModuleName ModuleManager Test-MMIsAdmin { $true }
    }

    It 'Moves a version to AllUsers, keeping its folder layout' {
        Move-ManagedModule MMAlpha -Version 1.0.0 -Destination AllUsers
        Test-Path ([IO.Path]::Combine($script:UserRoot, 'MMAlpha', '1.0.0')) | Should -BeFalse
        Test-Path ([IO.Path]::Combine($script:OtherRoot, 'MMAlpha', '1.0.0', 'MMAlpha.psd1')) | Should -BeTrue
        $moved = Get-ModuleLocation MMAlpha | Where-Object Version -EQ '1.0.0'
        $moved.Scope | Should -Be 'AllUsers'
        $moved.Repository | Should -Be 'PSGallery'
        @(Get-ChildItem -LiteralPath ([IO.Path]::Combine($script:UserRoot, 'MMAlpha')) -Filter '*.mmmove-*').Count | Should -Be 0
    }

    It 'Moves a version back to CurrentUser' {
        Move-ManagedModule MMAlpha -Version 0.9 -Destination CurrentUser
        (Get-ModuleLocation MMAlpha | Where-Object Version -EQ '0.9').Scope | Should -Be 'CurrentUser'
        Test-Path ([IO.Path]::Combine($script:OtherRoot, 'MMAlpha')) | Should -BeFalse   # the empty name folder is tidied up
    }

    It 'Moves modules without a version folder' {
        Move-ManagedModule MMBeta -Destination AllUsers
        Test-Path ([IO.Path]::Combine($script:OtherRoot, 'MMBeta', 'MMBeta.psd1')) | Should -BeTrue
        Test-Path ([IO.Path]::Combine($script:UserRoot, 'MMBeta')) | Should -BeFalse
    }

    It 'Moves what is piped from Get-ModuleLocation, and outputs the moved versions with -PassThru' {
        $r = @(Get-ModuleLocation MMAlpha -Scope CurrentUser | Move-ManagedModule -Destination AllUsers -PassThru)
        $r.Count | Should -Be 3
        $r | ForEach-Object { $_.Scope | Should -Be 'AllUsers' }
        (Get-ModuleInventory MMAlpha).VersionCount | Should -Be 4
    }

    It 'Updates the install location in <Format> install records' -ForEach @(
        @{ Format = 'PSResourceGet'; Location = 'root' }
        @{ Format = 'PowerShellGet'; Location = 'base' }
    ) {
        $base = [IO.Path]::Combine($script:UserRoot, 'MMGamma', '3.0.0')
        $old = if ($Location -eq 'root') { $script:UserRoot } else { $base }
        $xml = Join-Path $base 'PSGetModuleInfo.xml'
        (Get-Content -LiteralPath $xml -Raw).Replace('<S N="Repository">', "<S N=`"InstalledLocation`">$old</S>`n    <S N=`"Repository`">") |
            Set-Content -LiteralPath $xml

        Move-ManagedModule MMGamma -Destination AllUsers -WarningAction SilentlyContinue
        $expected = if ($Location -eq 'root') { $script:OtherRoot } else { [IO.Path]::Combine($script:OtherRoot, 'MMGamma', '3.0.0') }
        Get-Content -LiteralPath ([IO.Path]::Combine($script:OtherRoot, 'MMGamma', '3.0.0', 'PSGetModuleInfo.xml')) -Raw |
            Should -Match ([regex]::Escape("<S N=`"InstalledLocation`">$expected</S>"))
    }

    It 'Skips versions already in the destination scope' {
        Move-ManagedModule MMAlpha -Version 0.9 -Destination AllUsers -ErrorAction Stop
        Test-Path ([IO.Path]::Combine($script:OtherRoot, 'MMAlpha', '0.9')) | Should -BeTrue
    }

    It 'Does not overwrite a copy already at the destination' {
        New-FakeModule $script:OtherRoot 'MMGamma' '3.0.0' | Out-Null
        { Move-ManagedModule MMGamma -Scope CurrentUser -Destination AllUsers -ErrorAction Stop } | Should -Throw '*already installed for AllUsers*'
        Test-Path ([IO.Path]::Combine($script:UserRoot, 'MMGamma', '3.0.0')) | Should -BeTrue
    }

    It 'Requires an elevated session' {
        Mock -ModuleName ModuleManager Test-MMIsAdmin { $false }
        { Move-ManagedModule MMGamma -Destination AllUsers -ErrorAction Stop } | Should -Throw '*Moving MMGamma 3.0.0 to the all users module folder needs an elevated session*'
        Test-Path ([IO.Path]::Combine($script:UserRoot, 'MMGamma', '3.0.0')) | Should -BeTrue
        { Move-ManagedModule MMAlpha -Version 0.9 -Destination CurrentUser -ErrorAction Stop } | Should -Throw '*Moving MMAlpha 0.9 from the all users module folder needs an elevated session*'
    }

    It 'Refuses to move System modules' {
        Mock -ModuleName ModuleManager Get-MMScope { if ($Path -match 'MMTests_\w+[\\/]other([\\/]|$)') { 'AllUsers' } else { 'System' } }
        { Move-ManagedModule MMBeta -Destination AllUsers -ErrorAction Stop } | Should -Throw '*ships with PowerShell*'
    }

    It 'Does nothing with -WhatIf' {
        Move-ManagedModule MMAlpha -Destination AllUsers -WhatIf
        @(Get-ModuleLocation MMAlpha | Where-Object Scope -EQ 'CurrentUser').Count | Should -Be 3
    }

    It 'Puts the module back when the copy fails' {
        Mock -ModuleName ModuleManager Copy-Item { throw 'The disk is full.' }
        { Move-ManagedModule MMGamma -Destination AllUsers -ErrorAction Stop } | Should -Throw '*Failed to copy MMGamma 3.0.0*The disk is full.*'
        Test-Path ([IO.Path]::Combine($script:UserRoot, 'MMGamma', '3.0.0', 'MMGamma.psd1')) | Should -BeTrue
        Test-Path ([IO.Path]::Combine($script:OtherRoot, 'MMGamma')) | Should -BeFalse
        @(Get-ChildItem -LiteralPath ([IO.Path]::Combine($script:UserRoot, 'MMGamma'))).Name | Should -Be @('3.0.0')
    }

    It 'Warns when moving to CurrentUser a version that a module installed for all users needs' {
        New-FakeModule $script:OtherRoot 'MMShared' '1.0.0' -Repository PSGallery -Dependency @() | Out-Null
        New-FakeModule $script:OtherRoot 'MMNeedy' '1.0.0' -Repository PSGallery -Dependency 'MMShared|[1.0.0, )' | Out-Null
        Move-ManagedModule MMShared -Destination CurrentUser -WarningVariable warnings -WarningAction SilentlyContinue
        $warnings | Should -BeLike "*MMShared 1.0.0 is required by: MMNeedy 1.0.0*Other users won't have it*"
        (Get-ModuleLocation MMShared).Scope | Should -Be 'CurrentUser'
    }

    It 'Errors when there is no folder for the destination scope' {
        Mock -ModuleName ModuleManager Get-MMScope { 'CurrentUser' }
        { Move-ManagedModule MMGamma -Destination AllUsers -ErrorAction Stop } | Should -Throw '*no AllUsers module folder*'
    }

    It 'Errors for unknown modules, versions and folders' {
        { Move-ManagedModule DoesNotExist -Destination AllUsers -ErrorAction Stop } | Should -Throw '*No installed module*'
        { Move-ManagedModule MMAlpha -Version 9.* -Destination AllUsers -ErrorAction Stop } | Should -Throw "*No installed module matches 'MMAlpha' version '9.*'*"
        $missing = [IO.Path]::Combine($script:UserRoot, 'MMNothing', '1.0')
        { Move-ManagedModule -ModuleBase $missing -Destination AllUsers -ErrorAction Stop } | Should -Throw "*No installed module version found at '$missing'*"
    }

    Context "Each edition's module folders" {

        BeforeEach {
            # Laid out like PowerShell 7 on Windows: Documents and Program Files, each with a folder per edition,
            # and PSModulePath in PowerShell 7's order (no Documents\WindowsPowerShell\Modules).
            $docs = [IO.Path]::Combine($script:TestRoot, 'docs')
            $pf = [IO.Path]::Combine($script:TestRoot, 'pf')
            $script:Folder = @{
                CoreUser    = [IO.Path]::Combine($docs, 'PowerShell', 'Modules')
                DesktopUser = [IO.Path]::Combine($docs, 'WindowsPowerShell', 'Modules')
                CoreAll     = [IO.Path]::Combine($pf, 'PowerShell', 'Modules')
                DesktopAll  = [IO.Path]::Combine($pf, 'WindowsPowerShell', 'Modules')
            }
            foreach ($f in $script:Folder.Values) { $null = New-Item -ItemType Directory -Path $f -Force }
            $env:PSModulePath = @($script:Folder.CoreUser, $script:Folder.CoreAll, $script:Folder.DesktopAll) -join [IO.Path]::PathSeparator

            Mock -ModuleName ModuleManager Test-MMIsWindows { $true }
            Mock -ModuleName ModuleManager Get-MMKnownFolder { [IO.Path]::Combine($script:TestRoot, $(if ($Name -eq 'Documents') { 'docs' } else { 'pf' })) }
            Mock -ModuleName ModuleManager Get-MMScope { if ($Path -match 'MMTests_\w+[\\/]pf([\\/]|$)') { 'AllUsers' } else { 'CurrentUser' } }
        }

        It "Keeps a module shared by both editions with Windows PowerShell's modules, and says this session won't see it" {
            New-FakeModule $script:Folder.DesktopAll 'MMShared' '1.0.0' -Repository PSGallery | Out-Null
            Move-ManagedModule MMShared -Destination CurrentUser -WarningVariable warnings -WarningAction SilentlyContinue
            Test-Path ([IO.Path]::Combine($script:Folder.DesktopUser, 'MMShared', '1.0.0', 'MMShared.psd1')) | Should -BeTrue
            Test-Path ([IO.Path]::Combine($script:Folder.CoreUser, 'MMShared')) | Should -BeFalse
            Test-Path ([IO.Path]::Combine($script:Folder.DesktopAll, 'MMShared')) | Should -BeFalse
            $warnings | Should -BeLike "Moved MMShared 1.0.0 to $($script:Folder.DesktopUser), with the other Windows PowerShell modules. Windows PowerShell finds modules there, but this session doesn't*"
        }

        It "Moves a PowerShell 7 module to PowerShell 7's folder for the scope" {
            New-FakeModule $script:Folder.CoreUser 'MMCore' '2.0.0' -Repository PSGallery | Out-Null
            $r = Move-ManagedModule MMCore -Destination AllUsers -PassThru -WarningVariable warnings
            $r.ModuleBase | Should -Be ([IO.Path]::Combine($script:Folder.CoreAll, 'MMCore', '2.0.0'))
            $r.Scope | Should -Be 'AllUsers'
            $warnings | Should -BeNullOrEmpty
        }

        It "Keeps a PowerShell 7 module with PowerShell 7's modules when this session doesn't look there" {
            # As from Windows PowerShell, which doesn't look in Program Files\PowerShell\Modules.
            $env:PSModulePath = @($script:Folder.CoreUser, $script:Folder.DesktopUser, $script:Folder.DesktopAll) -join [IO.Path]::PathSeparator
            New-FakeModule $script:Folder.CoreUser 'MMCore' '2.0.0' | Out-Null
            Move-ManagedModule MMCore -Destination AllUsers -WarningVariable warnings -WarningAction SilentlyContinue
            Test-Path ([IO.Path]::Combine($script:Folder.CoreAll, 'MMCore', '2.0.0', 'MMCore.psd1')) | Should -BeTrue
            $warnings | Should -BeLike "Moved MMCore 2.0.0 to $($script:Folder.CoreAll), with the other PowerShell 7 modules. PowerShell 7 finds modules there*"
        }

        It 'Uses the first folder for the scope for other module folders, and outside Windows' {
            $custom = [IO.Path]::Combine($script:TestRoot, 'custom')
            $env:PSModulePath = @($env:PSModulePath, $custom) -join [IO.Path]::PathSeparator
            New-FakeModule $custom 'MMCustom' '1.0.0' | Out-Null
            Move-ManagedModule MMCustom -Destination AllUsers
            Test-Path ([IO.Path]::Combine($script:Folder.CoreAll, 'MMCustom', '1.0.0')) | Should -BeTrue

            Mock -ModuleName ModuleManager Test-MMIsWindows { $false }
            New-FakeModule $script:Folder.DesktopAll 'MMShared' '1.0.0' | Out-Null
            Move-ManagedModule MMShared -Destination CurrentUser
            Test-Path ([IO.Path]::Combine($script:Folder.CoreUser, 'MMShared', '1.0.0')) | Should -BeTrue
        }
    }

    Context 'Loaded modules' {

        BeforeEach {
            $gamma = [IO.Path]::Combine($script:UserRoot, 'MMGamma', '3.0.0', 'MMGamma.psd1')
            Import-Module $gamma -Global
        }

        AfterEach {
            Get-Module MMGamma | Remove-Module -Force -ErrorAction Ignore
        }

        It 'Refuses to move a loaded module' {
            { Move-ManagedModule MMGamma -Destination AllUsers -ErrorAction Stop } | Should -Throw "*MMGamma 3.0.0 is loaded*Remove-Module MMGamma*"
            Test-Path $gamma | Should -BeTrue
            Get-Module MMGamma | Should -Not -BeNullOrEmpty
        }

        It 'Unloads and moves a loaded module with -Force' {
            Move-ManagedModule MMGamma -Destination AllUsers -Force
            Get-Module MMGamma | Should -BeNullOrEmpty
            Test-Path ([IO.Path]::Combine($script:OtherRoot, 'MMGamma', '3.0.0', 'MMGamma.psd1')) | Should -BeTrue
        }
    }

    Context 'When part of the move fails' {

        It 'Changes nothing when the module folder is in use' {
            Mock -ModuleName ModuleManager Rename-MMFolder { throw [UnauthorizedAccessException]::new("Access to the path is denied.") }
            Mock -ModuleName ModuleManager Copy-Item { }
            { Move-ManagedModule MMGamma -Destination AllUsers -ErrorAction Stop } | Should -Throw '*Failed to move MMGamma 3.0.0 from * (is it in use?): Access to the path is denied.*'
            Test-Path ([IO.Path]::Combine($script:UserRoot, 'MMGamma', '3.0.0', 'MMGamma.psd1')) | Should -BeTrue
            Test-Path ([IO.Path]::Combine($script:OtherRoot, 'MMGamma')) | Should -BeFalse
            Should -Invoke -ModuleName ModuleManager Copy-Item -Times 0 -Exactly
        }

        It 'Says where the module is when it cannot be put back after a failed copy' {
            Mock -ModuleName ModuleManager Copy-Item { throw 'The disk is full.' }
            # Renaming to the staging folder works; renaming it back doesn't.
            Mock -ModuleName ModuleManager Rename-MMFolder { [IO.Directory]::Move($Path, $Destination) }
            Mock -ModuleName ModuleManager Rename-MMFolder { throw 'Access to the path is denied.' } -ParameterFilter { $Path -like '*.mmmove-*' }
            { Move-ManagedModule MMGamma -Destination AllUsers -ErrorAction Stop } |
                Should -Throw '*The disk is full. The module is still in *.mmmove-*; rename it back to *3.0.0.*'
            @(Get-ChildItem -LiteralPath ([IO.Path]::Combine($script:UserRoot, 'MMGamma'))).Name | Should -BeLike '3.0.0.mmmove-*'
        }

        It 'Removes a partial copy when the copy fails part-way' {
            Mock -ModuleName ModuleManager Copy-Item {
                $null = New-Item -ItemType Directory -Path $Destination -Force
                throw 'The disk is full.'
            }
            { Move-ManagedModule MMAlpha -Version 1.0.0 -Destination AllUsers -ErrorAction Stop } | Should -Throw '*The disk is full.*'
            Test-Path ([IO.Path]::Combine($script:OtherRoot, 'MMAlpha', '1.0.0')) | Should -BeFalse
            Test-Path ([IO.Path]::Combine($script:OtherRoot, 'MMAlpha', '0.9')) | Should -BeTrue   # the existing name folder is kept
            Test-Path ([IO.Path]::Combine($script:UserRoot, 'MMAlpha', '1.0.0', 'MMAlpha.psd1')) | Should -BeTrue
        }

        It 'Warns, after a complete move, when the old copy cannot be removed' {
            Mock -ModuleName ModuleManager Remove-Item { Microsoft.PowerShell.Management\Remove-Item @PSBoundParameters }
            Mock -ModuleName ModuleManager Remove-Item { throw 'The file is in use.' } -ParameterFilter { $LiteralPath -like '*.mmmove-*' }
            Move-ManagedModule MMGamma -Destination AllUsers -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings | Should -BeLike '*Moved MMGamma 3.0.0 to *, but could not remove the old copy at *.mmmove-*: The file is in use.*'
            Test-Path ([IO.Path]::Combine($script:OtherRoot, 'MMGamma', '3.0.0', 'MMGamma.psd1')) | Should -BeTrue
        }
    }
}

Describe 'Get-MMKnownFolder' {

    It 'Returns the Documents and Program Files folders' {
        InModuleScope ModuleManager {
            Get-MMKnownFolder -Name Documents | Should -Be ([Environment]::GetFolderPath('MyDocuments'))
            Get-MMKnownFolder -Name ProgramFiles | Should -Be $env:ProgramFiles
        }
    }
}

Describe 'Rename-MMFolder' {

    It 'Renames a folder, and throws the underlying error when it cannot' {
        Reset-FakeModules
        InModuleScope ModuleManager -Parameters @{ UserRoot = $script:UserRoot } {
            $from = [IO.Path]::Combine($UserRoot, 'MMBeta')
            $to = [IO.Path]::Combine($UserRoot, 'MMBeta.renamed')
            Rename-MMFolder -Path $from -Destination $to
            Test-Path ([IO.Path]::Combine($to, 'MMBeta.psd1')) | Should -BeTrue

            $err = $null
            try { Rename-MMFolder -Path $from -Destination $to } catch { $err = $_ }
            $err.Exception | Should -BeOfType [IO.IOException]   # not wrapped in a MethodInvocationException
        }
    }
}

Describe 'Update-MMInstallLocation' {

    BeforeEach {
        Reset-FakeModules
    }

    It 'Rewrites a location <Case>, and leaves others alone' -ForEach @(
        @{ Case = 'inside the old folder'; Old = 'MMGamma'; New = 'MMGamma' }
        @{ Case = 'with special characters'; Old = 'A & B'; New = 'A &amp; B' }
    ) {
        InModuleScope ModuleManager -Parameters @{ UserRoot = $script:UserRoot; OtherRoot = $script:OtherRoot; Old = $Old; New = $New } {
            $base = [IO.Path]::Combine($OtherRoot, 'MMGamma', '3.0.0')
            $null = New-Item -ItemType Directory -Path $base -Force
            $xml = [IO.Path]::Combine($base, 'PSGetModuleInfo.xml')
            $inside = [Net.WebUtility]::HtmlEncode([IO.Path]::Combine($UserRoot, $Old))
            $elsewhere = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'Elsewhere')
            [IO.File]::WriteAllText($xml, "<S N=`"InstalledLocation`">$inside</S><S N=`"InstalledLocation`">$elsewhere</S>", [Text.UnicodeEncoding]::new($false, $true))

            Update-MMInstallLocation -ModuleBase $base -OldModuleBase ([IO.Path]::Combine($UserRoot, 'MMGamma', '3.0.0')) -OldRoot $UserRoot -NewRoot $OtherRoot
            $text = [IO.File]::ReadAllText($xml)
            $text | Should -BeLike "*<S N=`"InstalledLocation`">$([IO.Path]::Combine($OtherRoot, $New))</S>*"
            $text | Should -BeLike "*<S N=`"InstalledLocation`">$elsewhere</S>*"
            [IO.File]::ReadAllBytes($xml)[0..1] | Should -Be @(0xFF, 0xFE)   # still UTF-16, with its byte order mark
        }
    }

    It 'Leaves the file alone when no location changes, and warns when it cannot be read' {
        InModuleScope ModuleManager -Parameters @{ UserRoot = $script:UserRoot; OtherRoot = $script:OtherRoot } {
            $base = [IO.Path]::Combine($OtherRoot, 'MMNoChange')
            $null = New-Item -ItemType Directory -Path $base -Force
            $xml = [IO.Path]::Combine($base, 'PSGetModuleInfo.xml')
            [IO.File]::WriteAllText($xml, '<S N="Repository">PSGallery</S>')
            $stamp = [datetime]'2020-01-01'
            [IO.File]::SetLastWriteTimeUtc($xml, $stamp)
            Update-MMInstallLocation -ModuleBase $base -OldModuleBase $base -OldRoot $UserRoot -NewRoot $OtherRoot
            [IO.File]::GetLastWriteTimeUtc($xml) | Should -Be $stamp

            # No record at all: nothing to do.
            { Update-MMInstallLocation -ModuleBase ([IO.Path]::Combine($OtherRoot, 'MMMissing')) -OldModuleBase $base -OldRoot $UserRoot -NewRoot $OtherRoot } | Should -Not -Throw

            $stream = [IO.File]::Open($xml, 'Open', 'ReadWrite', 'None')
            try {
                Update-MMInstallLocation -ModuleBase $base -OldModuleBase $base -OldRoot $UserRoot -NewRoot $OtherRoot -WarningVariable warnings -WarningAction SilentlyContinue
            }
            finally { $stream.Dispose() }
            if (-not (Test-MMIsWindows)) { return }   # files aren't locked by open handles elsewhere
            $warnings | Should -BeLike "*Could not update the install location in $xml*"
        }
    }
}
