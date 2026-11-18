BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-MMTestModule
}

AfterAll {
    Remove-Module ModuleManager -Force -ErrorAction SilentlyContinue
}

Describe 'Compare-MMVersion' {

    It 'Compares <A>/<PA> vs <B>/<PB> as <Expected>' -ForEach @(
        @{ A = '1.0'; PA = ''; B = '1.0.0.0'; PB = ''; Expected = 0 }
        @{ A = '1.0.1'; PA = ''; B = '1.0.0'; PB = ''; Expected = 1 }
        @{ A = '1.0.0'; PA = 'beta'; B = '1.0.0'; PB = ''; Expected = -1 }
        @{ A = '1.0.0'; PA = 'beta.2'; B = '1.0.0'; PB = 'beta.10'; Expected = -1 }
        @{ A = '1.0.0'; PA = 'beta'; B = '1.0.0'; PB = 'alpha'; Expected = 1 }
        @{ A = '2.0.0'; PA = 'preview1'; B = '1.9.9'; PB = ''; Expected = 1 }
        @{ A = '1.0.0'; PA = 'rc.1'; B = '1.0.0'; PB = 'rc.1.1'; Expected = -1 }
    ) {
        InModuleScope ModuleManager -Parameters $_ {
            Compare-MMVersion $A $PA $B $PB | Should -Be $Expected
        }
    }
}
