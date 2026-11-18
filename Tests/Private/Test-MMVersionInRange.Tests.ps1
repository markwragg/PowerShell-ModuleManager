BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-MMTestModule
}

AfterAll {
    Remove-Module ModuleManager -Force -ErrorAction SilentlyContinue
}

Describe 'Test-MMVersionInRange' {

    It '<Version>/<Pre> in <Range> is <Expected>' -ForEach @(
        @{ Version = '1.0.0'; Pre = ''; Range = ''; Expected = $true }
        @{ Version = '1.0.0'; Pre = ''; Range = '*'; Expected = $true }
        @{ Version = '5.4.0'; Pre = ''; Range = '[5.4.0, )'; Expected = $true }
        @{ Version = '5.3.9'; Pre = ''; Range = '[5.4.0, )'; Expected = $false }
        @{ Version = '5.4.0'; Pre = ''; Range = '(5.4.0, )'; Expected = $false }
        @{ Version = '2.1.0'; Pre = ''; Range = '[2.1.0]'; Expected = $true }
        @{ Version = '2.1.1'; Pre = ''; Range = '[2.1.0]'; Expected = $false }
        @{ Version = '2.1'; Pre = ''; Range = '[2.1.0.0]'; Expected = $true }
        @{ Version = '1.5.0'; Pre = ''; Range = '[1.0, 2.0)'; Expected = $true }
        @{ Version = '2.0.0'; Pre = ''; Range = '[1.0, 2.0)'; Expected = $false }
        @{ Version = '2.0.0'; Pre = ''; Range = '(, 2.0]'; Expected = $true }
        @{ Version = '3.0.0'; Pre = ''; Range = '(, 2.0]'; Expected = $false }
        @{ Version = '1.2.0'; Pre = ''; Range = '1.2'; Expected = $true }
        @{ Version = '1.1.0'; Pre = ''; Range = '1.2'; Expected = $false }
        @{ Version = '2.0.0'; Pre = 'beta1'; Range = '[2.0.0, )'; Expected = $false }
        @{ Version = '2.0.0'; Pre = 'beta2'; Range = '[2.0.0-beta1, )'; Expected = $true }
    ) {
        InModuleScope ModuleManager -Parameters $_ {
            Test-MMVersionInRange $Version $Pre $Range | Should -Be $Expected
        }
    }
}
