BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-MMTestModule
}

AfterAll {
    Remove-Module ModuleManager -Force -ErrorAction SilentlyContinue
}

Describe 'Get-MMLoadedDependencyConflict' {

    BeforeAll {
        $updates = InModuleScope ModuleManager {
            [pscustomobject]@{ Name = 'Az.Compute'; LatestVersion = '12.0.0'; LatestDependencies = @(New-MMDependency 'Az.Accounts' -VersionRange '[5.5.0, )') }
            [pscustomobject]@{ Name = 'Az.Storage'; LatestVersion = '10.0.0'; LatestDependencies = @(New-MMDependency 'Az.Accounts' -VersionRange '[5.5.0, )') }
            [pscustomobject]@{ Name = 'Az.Network'; LatestVersion = '8.0.0'; LatestDependencies = @(New-MMDependency 'Az.Accounts' -VersionRange '[5.0.0, )') }
        }
    }

    It 'Reports a loaded module that is older than the new versions need' {
        $loaded = @([pscustomobject]@{ Name = 'Az.Accounts'; Version = [version]'5.4.0'; PrivateData = $null })
        $c = @(InModuleScope ModuleManager -Parameters @{ U = $updates; L = $loaded } { Get-MMLoadedDependencyConflict -Update $U -LoadedModule $L })
        $c.Count | Should -Be 1
        $c[0].Name | Should -Be 'Az.Accounts'
        $c[0].LoadedVersion | Should -Be '5.4.0'
        $c[0].RequiredBy | Should -Be @('Az.Compute 12.0.0 needs [5.5.0, )', 'Az.Storage 10.0.0 needs [5.5.0, )')
    }

    It 'Reports nothing when the loaded version is new enough, or the module is not loaded' {
        $loaded = @([pscustomobject]@{ Name = 'Az.Accounts'; Version = [version]'5.5.5'; PrivateData = $null })
        InModuleScope ModuleManager -Parameters @{ U = $updates; L = $loaded } { Get-MMLoadedDependencyConflict -Update $U -LoadedModule $L } | Should -BeNullOrEmpty
        InModuleScope ModuleManager -Parameters @{ U = $updates } { Get-MMLoadedDependencyConflict -Update $U -LoadedModule @() } | Should -BeNullOrEmpty
    }

    It 'Reads prerelease labels without recording errors for modules that have no PSData or Prerelease' {
        $loaded = @(
            [pscustomobject]@{ Name = 'NoPSData'; Version = [version]'1.0.0'; PrivateData = @{ Other = 1 } }
            [pscustomobject]@{ Name = 'NoPrerelease'; Version = [version]'1.0.0'; PrivateData = @{ PSData = @{ Tags = 'x' } } }
            [pscustomobject]@{ Name = 'Az.Accounts'; Version = [version]'5.5.0'; PrivateData = @{ PSData = @{ Prerelease = 'preview1' } } }
        )
        # Errors caught inside the function still reach an outer advanced function's -ErrorVariable,
        # which is how Update-ManagedModule's callers (the terminal UI) collect failures.
        $r = InModuleScope ModuleManager -Parameters @{ U = $updates; L = $loaded } {
            function Invoke-Outer { [CmdletBinding()] param($U, $L) Get-MMLoadedDependencyConflict -Update $U -LoadedModule $L }
            $errs = @()
            $out = @(Invoke-Outer -U $U -L $L -ErrorVariable errs -ErrorAction SilentlyContinue)
            @{ Out = $out; Errors = @($errs) }
        }
        # 5.5.0-preview1 sorts before 5.5.0, so it doesn't satisfy [5.5.0, ).
        $r.Out.LoadedVersion | Should -Be '5.5.0-preview1'
        $r.Errors.Count | Should -Be 0
    }
}
