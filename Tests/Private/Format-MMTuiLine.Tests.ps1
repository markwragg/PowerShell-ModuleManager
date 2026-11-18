BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-MMTestModule
}

AfterAll {
    Remove-Module ModuleManager -Force -ErrorAction SilentlyContinue
}

Describe 'Format-MMTuiLine' {

    It 'Formats lines to an exact visible width' {
        InModuleScope ModuleManager {
            $line = Format-MMTuiLine @(@('abc', 'Yellow'), @('defghijklmnop', $null)) 10 'Cursor'
            ($line -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", '').Length | Should -Be 10
        }
    }
}
