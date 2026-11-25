BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
    Set-FakeGalleryCache
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Get-ManagedModuleUpdate' {

    It 'Reports the status of each module from cached lookups' {
        $u = Get-ManagedModuleUpdate
        ($u | Where-Object Name -EQ 'MMAlpha').Status | Should -Be 'UpdateAvailable'
        ($u | Where-Object Name -EQ 'MMAlpha').LatestVersion | Should -Be '2.0.0'
        ($u | Where-Object Name -EQ 'MMBeta').Status | Should -Be 'NotInRepository'
        ($u | Where-Object Name -EQ 'MMDependent').Status | Should -Be 'UpToDate'
        ($u | Where-Object Name -EQ 'MMGamma').Status | Should -Be 'LocalNewer'
    }

    It 'Reports modules unlisted from the repository as Unlisted' {
        InModuleScope ModuleManager {
            $script:MMGalleryCache[(Get-MMCacheKey 'MMBeta' 'PSGallery' $false)].Status = 'Unlisted'
        }
        try {
            $u = Get-ManagedModuleUpdate MMBeta
            $u.Status | Should -Be 'Unlisted'
            $u.LatestVersion | Should -BeNullOrEmpty
        }
        finally { Set-FakeGalleryCache }
    }

    It 'Reports a module copied in by hand whose repository namesake has a different GUID as NotInRepository, and says why' {
        # MMBeta was copied in by hand (no install record).
        InModuleScope ModuleManager {
            $script:MMGalleryCache[(Get-MMCacheKey 'MMBeta' 'PSGallery' $false)] = [pscustomobject]@{
                RequestedName = 'MMBeta'; Name = 'MMBeta'; Repository = 'PSGallery'; Prerelease = $false; Status = 'Found'
                Version = '1.0.0'; ModuleVersion = [version]'1.0.0'; PrereleaseLabel = $null; PublishedDate = [datetime]::UtcNow
                Error = $null; CachedAt = [datetime]::UtcNow; Guid = [guid]::NewGuid().ToString()
            }
        }
        try {
            $u = Get-ManagedModuleUpdate MMBeta
            $u.Status | Should -Be 'NotInRepository'
            $u.LatestVersion | Should -BeNullOrEmpty
            $u.Error | Should -Be "The MMBeta module in PSGallery is a different module with the same name (its GUID doesn't match)."
            Update-ManagedModule MMBeta -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
                ForEach-Object Message | Should -Contain "The MMBeta module in PSGallery is a different module with the same name (its GUID doesn't match). Skipping."

            # With the same GUID, it's the same module.
            InModuleScope ModuleManager -Parameters @{ Guid = Get-FakeModuleGuid 'MMBeta' } {
                $script:MMGalleryCache[(Get-MMCacheKey 'MMBeta' 'PSGallery' $false)].Guid = $Guid
            }
            (Get-ManagedModuleUpdate MMBeta).Status | Should -Be 'UpdateAvailable'
        }
        finally { Set-FakeGalleryCache }
    }

    It "Doesn't check the GUID of a module installed from the repository, as some publishers change it between versions" {
        InModuleScope ModuleManager {
            $script:MMGalleryCache[(Get-MMCacheKey 'MMGamma' 'PSGallery' $false)] | Add-Member -NotePropertyName Guid -NotePropertyValue ([guid]::NewGuid().ToString()) -Force
        }
        try { (Get-ManagedModuleUpdate MMGamma).Status | Should -Be 'LocalNewer' }
        finally { Set-FakeGalleryCache }
    }

    It 'Filters with -Outdated' {
        (Get-ManagedModuleUpdate -Outdated).Name | Should -Be @('MMAlpha')
    }

    It 'Outputs ModuleUpdate objects' {
        (Get-ManagedModuleUpdate MMAlpha).PSObject.TypeNames | Should -Contain 'ModuleManager.ModuleUpdate'
    }
}
