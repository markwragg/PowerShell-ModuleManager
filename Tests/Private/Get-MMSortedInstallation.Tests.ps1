BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-MMTestModule
}

AfterAll {
    Remove-Module ModuleManager -Force -ErrorAction SilentlyContinue
}

Describe 'Get-MMSortedInstallation' {

    It 'Sorts installations newest first, with prerelease below its release' {
        InModuleScope ModuleManager {
            $items = @(
                [pscustomobject]@{ ModuleVersion = [version]'1.0.0'; Prerelease = $null; Version = '1.0.0' }
                [pscustomobject]@{ ModuleVersion = [version]'2.0.0'; Prerelease = 'preview9'; Version = '2.0.0-preview9' }
                [pscustomobject]@{ ModuleVersion = [version]'2.0.0'; Prerelease = $null; Version = '2.0.0' }
                [pscustomobject]@{ ModuleVersion = [version]'2.0.0'; Prerelease = 'preview10'; Version = '2.0.0-preview10' }
            )
            (Get-MMSortedInstallation $items).Version | Should -Be @('2.0.0', '2.0.0-preview10', '2.0.0-preview9', '1.0.0')
        }
    }
}
