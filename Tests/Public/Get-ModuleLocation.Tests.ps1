BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Get-ModuleLocation' {

    It 'Lists every installed version with its location' {
        $loc = @(Get-ModuleLocation MMAlpha)
        $loc.Count | Should -Be 4
        $loc[-1].ModuleRoot | Should -Be $script:OtherRoot
        $loc[0].PSObject.TypeNames | Should -Contain 'ModuleManager.InstalledVersion'
    }

    It 'Summarises by module path' {
        $summary = @(Get-ModuleLocation -Summary)
        $summary.Count | Should -Be 2
        $summary[0].Modules | Should -Be 4
        $summary[0].Versions | Should -Be 6
        $summary[1].Versions | Should -Be 1
    }

    It 'Includes sizes when asked' {
        (Get-ModuleLocation MMGamma -IncludeSize).SizeMB | Should -BeGreaterOrEqual 0
    }
}
