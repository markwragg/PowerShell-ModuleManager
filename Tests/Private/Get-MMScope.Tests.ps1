BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-MMTestModule
}

AfterAll {
    Remove-Module ModuleManager -Force -ErrorAction SilentlyContinue
}

Describe 'Get-MMScope' {

    It 'Classifies $PSHOME as System' {
        InModuleScope ModuleManager { Get-MMScope (Join-Path $PSHOME 'Modules') | Should -Be 'System' }
    }

    It 'Classifies the user profile as CurrentUser' {
        InModuleScope ModuleManager { Get-MMScope (Join-Path (Join-Path $HOME 'some') 'Modules') | Should -Be 'CurrentUser' }
    }

    It 'Classifies Program Files as AllUsers' -Skip:(-not $env:ProgramFiles) {
        InModuleScope ModuleManager { Get-MMScope (Join-Path $env:ProgramFiles 'PowerShell\Modules') | Should -Be 'AllUsers' }
    }
}
