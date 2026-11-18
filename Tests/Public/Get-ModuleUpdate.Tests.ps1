BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
    Set-FakeGalleryCache
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Get-ModuleUpdate' {

    It 'Reports the status of each module from cached lookups' {
        $u = Get-ModuleUpdate
        ($u | Where-Object Name -EQ 'MMAlpha').Status | Should -Be 'UpdateAvailable'
        ($u | Where-Object Name -EQ 'MMAlpha').LatestVersion | Should -Be '2.0.0'
        ($u | Where-Object Name -EQ 'MMBeta').Status | Should -Be 'NotInRepository'
        ($u | Where-Object Name -EQ 'MMDependent').Status | Should -Be 'UpToDate'
        ($u | Where-Object Name -EQ 'MMGamma').Status | Should -Be 'LocalNewer'
    }

    It 'Filters with -Outdated' {
        (Get-ModuleUpdate -Outdated).Name | Should -Be @('MMAlpha')
    }

    It 'Outputs ModuleUpdate objects' {
        (Get-ModuleUpdate MMAlpha).PSObject.TypeNames | Should -Contain 'ModuleManager.ModuleUpdate'
    }
}
