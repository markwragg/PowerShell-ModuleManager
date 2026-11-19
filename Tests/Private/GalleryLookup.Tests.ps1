BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    # These tests mock the package managers' commands, so the real modules must be loaded and visible from
    # inside the module under test. -Global matters: the build runs Pester from within psake (a module), and a
    # plain Import-Module would land in psake's scope, out of sight of InModuleScope ModuleManager.
    Import-Module Microsoft.PowerShell.PSResourceGet, PowerShellGet -Global -ErrorAction SilentlyContinue
    Initialize-MMTestEnvironment
    # No Reset-FakeModules here: nothing below needs the fake module tree, and pointing PSModulePath at it
    # would hide the package managers from command lookup and from the lookup runspaces.
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'The repository lookup script' {

    Context 'With PSResourceGet' {

        It 'Returns the newest version found, with its dependencies' {
            InModuleScope ModuleManager {
                Mock Find-PSResource {
                    [pscustomobject]@{ Name = 'MMThing'; Version = [version]'1.0.0'; Prerelease = ''; PublishedDate = [datetime]'2025-01-01'; Dependencies = @() }
                    [pscustomobject]@{
                        Name = 'MMThing'; Version = [version]'2.0.0'; Prerelease = 'beta1'; PublishedDate = [datetime]'2025-06-01'
                        Dependencies = @($null, [pscustomobject]@{ Name = 'MMCore'; VersionRange = '[1.5.0, )' })
                    }
                }
                $r = & $script:MMLookupScript -Names 'mmthing' -Repository 'PSGallery' -Prerelease $true -Backend 'PSResourceGet'
                $r.Status | Should -Be 'Found'
                $r.RequestedName | Should -Be 'mmthing'
                $r.Name | Should -Be 'MMThing'
                $r.Version | Should -Be '2.0.0-beta1'
                $r.ModuleVersion | Should -Be ([version]'2.0.0')
                $r.PrereleaseLabel | Should -Be 'beta1'
                $r.Dependencies | Should -Be @('MMCore|[1.5.0, )')
                Should -Invoke Find-PSResource -Times 1 -ParameterFilter { $Name -eq 'mmthing' -and $Repository -eq 'PSGallery' -and $Prerelease }
            }
        }

        It 'Reports <Status> when the search fails with "<Message>"' -ForEach @(
            @{ Message = "Package 'MMThing' could not be found"; Status = 'NotFound' }
            @{ Message = 'The remote server returned an error: (503)'; Status = 'Error' }
        ) {
            InModuleScope ModuleManager -Parameters $_ {
                Mock Find-PSResource ([scriptblock]::Create("throw '$($Message.Replace("'", "''"))'"))
                $r = & $script:MMLookupScript -Names 'MMThing' -Repository 'PSGallery' -Prerelease $false -Backend 'PSResourceGet'
                $r.Status | Should -Be $Status
                $r.Error | Should -Be $Message
                $r.Version | Should -BeNullOrEmpty
                $r.Dependencies.Count | Should -Be 0
            }
        }

        It 'Works with PowerShellGet 1.x, which has no -AllowPrerelease' {
            InModuleScope ModuleManager {
                # How Windows PowerShell's built-in PowerShellGet 1.0.0.1 looks: no -AllowPrerelease.
                Mock Get-Command { [pscustomobject]@{ Parameters = @{ Name = $null; Repository = $null } } } -ParameterFilter { $Name -eq 'PowerShellGet\Find-Module' }
                Mock Find-Module { [pscustomobject]@{ Name = 'MMThing'; Version = '1.5'; PublishedDate = $null; Dependencies = @() } }

                $r = & $script:MMLookupScript -Names 'MMThing' -Repository 'PSGallery' -Prerelease $false -Backend 'PowerShellGet'
                $r.Status | Should -Be 'Found'
                Should -Invoke Find-Module -Times 1 -Exactly -ParameterFilter { -not $PSBoundParameters.ContainsKey('AllowPrerelease') }

                $r = & $script:MMLookupScript -Names 'MMThing' -Repository 'PSGallery' -Prerelease $true -Backend 'PowerShellGet'
                $r.Status | Should -Be 'Error'
                $r.Error | Should -Match "can't find prerelease versions"
            }
        }

        It 'Explains what to do when PowerShellGet wants to install the NuGet provider' {
            InModuleScope ModuleManager {
                Mock Find-Module { throw 'Exception calling "ShouldContinue" with "2" argument(s): "... This version of PowerShellGet requires minimum version ''2.8.5.201'' of NuGet provider ..."' }
                $r = & $script:MMLookupScript -Names 'MMThing' -Repository 'PSGallery' -Prerelease $false -Backend 'PowerShellGet'
                $r.Status | Should -Be 'Error'
                $r.Error | Should -BeLike 'PowerShellGet needs the NuGet package provider. Install it with ''Install-PackageProvider -Name NuGet*'
            }
        }

        It 'Reports NotFound when the search returns nothing' {
            InModuleScope ModuleManager {
                Mock Find-PSResource { }
                (& $script:MMLookupScript -Names 'MMThing' -Repository 'PSGallery' -Prerelease $false -Backend 'PSResourceGet').Status | Should -Be 'NotFound'
            }
        }
    }

    Context 'With PowerShellGet' {

        It 'Parses <Version> and each form of dependency' -ForEach @(
            @{ Version = '2.1.0-beta1'; Expected = '2.1.0-beta1'; Label = 'beta1' }
            @{ Version = '3'; Expected = '3.0'; Label = $null }
        ) {
            InModuleScope ModuleManager -Parameters $_ {
                Mock Find-Module {
                    [pscustomobject]@{
                        Name = 'MMThing'; Version = $Version; PublishedDate = $null
                        Dependencies = @(
                            @{ Name = 'MMExact'; RequiredVersion = '1.0.0' }
                            @{ Name = 'MMRange'; MinimumVersion = '1.0'; MaximumVersion = '2.0' }
                            @{ Name = 'MMMin'; MinimumVersion = '1.5' }
                            @{ Name = 'MMMax'; MaximumVersion = '4.0' }
                            @{ Name = 'MMAny' }
                        )
                    }
                }
                $r = & $script:MMLookupScript -Names 'MMThing' -Repository 'PSGallery' -Prerelease $false -Backend 'PowerShellGet'
                $r.Status | Should -Be 'Found'
                $r.Version | Should -Be $Expected
                $r.PrereleaseLabel | Should -Be $Label
                $r.Dependencies | Should -Be @('MMExact|[1.0.0]', 'MMRange|[1.0, 2.0]', 'MMMin|[1.5, )', 'MMMax|(, 4.0]', 'MMAny|')
            }
        }
    }
}

Describe 'Start-MMGalleryLookup, Receive-MMGalleryLookup and Wait-MMGalleryLookup' {

    BeforeEach {
        InModuleScope ModuleManager { $script:MMGalleryCache = @{} }
    }

    It 'Returns cached results straight away, unless -Refresh is used' {
        InModuleScope ModuleManager {
            $cached = [pscustomobject]@{ RequestedName = 'MMAlpha'; Status = 'Found'; Version = '9.0'; CachedAt = [datetime]::UtcNow }
            $script:MMGalleryCache[(Get-MMCacheKey 'MMAlpha' 'PSGallery' $false)] = $cached
            $request = [pscustomobject]@{ Name = 'MMAlpha'; Repository = 'PSGallery'; Prerelease = $false }

            $job = Start-MMGalleryLookup -Request $request
            $job.Done | Should -Be 1
            $job.Tasks.Count | Should -Be 0
            $job.Results[0].Version | Should -Be '9.0'

            Mock Get-MMBackend { 'None' }
            $job = Start-MMGalleryLookup -Request $request -Refresh
            $job.Results[0].Status | Should -Be 'Error'
            $job.Results[0].Error | Should -Match 'Neither'
        }
    }

    It 'Ignores expired cache entries' {
        InModuleScope ModuleManager {
            $script:MMGalleryCache[(Get-MMCacheKey 'MMAlpha' 'PSGallery' $false)] = [pscustomobject]@{ Status = 'Found'; CachedAt = [datetime]::UtcNow.AddHours(-2) }
            Get-MMCachedResult ([pscustomobject]@{ Name = 'MMAlpha'; Repository = 'PSGallery'; Prerelease = $false }) | Should -BeNullOrEmpty
        }
    }

    It 'Looks modules up in parallel and collects every result' {
        # A repository that isn't registered fails at once, without going to the network.
        InModuleScope ModuleManager {
            Mock Write-Progress { }
            $requests = foreach ($n in 'MMOne', 'MMTwo', 'MMThree') { [pscustomobject]@{ Name = $n; Repository = 'MMNoSuchRepository'; Prerelease = $false } }
            $job = Start-MMGalleryLookup -Request $requests -ThrottleLimit 2 -BatchSize 2
            $job.Tasks.Count | Should -Be 2
            $results = @(Wait-MMGalleryLookup -Job $job)
            $results.Count | Should -Be 3
            @($results | ForEach-Object { $_.RequestedName } | Sort-Object) | Should -Be @('MMOne', 'MMThree', 'MMTwo')
            $results | ForEach-Object { $_.Status | Should -BeIn 'NotFound', 'Error' }
            $job.Pool | Should -BeNullOrEmpty
            Test-MMGalleryLookupComplete -Job $job | Should -BeTrue
        }
    }

    It 'Reports every module in a batch as an error when the batch itself fails' {
        InModuleScope ModuleManager {
            $ps = [powershell]::Create()
            [void]$ps.AddScript({ throw 'runspace broke' })
            $task = [pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Names = @('MMOne', 'MMTwo'); Repository = 'PSGallery'; Prerelease = $false; Collected = $false }
            $job = [pscustomobject]@{ Tasks = @($task); Results = [System.Collections.Generic.List[object]]::new(); Pool = $null; Total = 2; Done = 0 }
            while (-not $task.Handle.IsCompleted) { Start-Sleep -Milliseconds 20 }

            $results = @(Receive-MMGalleryLookup -Job $job)
            $results.Count | Should -Be 2
            $results | ForEach-Object { $_.Status | Should -Be 'Error'; $_.Error | Should -Match 'runspace broke' }
            $job.Done | Should -Be 2
            $script:MMGalleryCache.Count | Should -Be 0   # errors aren't cached
        }
    }

    It 'Converts dependency strings, and caches what it finds' {
        InModuleScope ModuleManager {
            $ps = [powershell]::Create()
            [void]$ps.AddScript({
                    [pscustomobject]@{
                        RequestedName = 'MMOne'; Name = 'MMOne'; Repository = 'PSGallery'; Prerelease = $false; Status = 'Found'
                        Version = '1.0'; ModuleVersion = [version]'1.0'; PrereleaseLabel = $null; PublishedDate = $null; Error = $null
                        Dependencies = @('MMCore|[1.0, )', 'MMAny', '')
                    }
                    $null
                })
            $task = [pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Names = @('MMOne'); Repository = 'PSGallery'; Prerelease = $false; Collected = $false }
            $job = [pscustomobject]@{ Tasks = @($task); Results = [System.Collections.Generic.List[object]]::new(); Pool = $null; Total = 1; Done = 0 }
            while (-not $task.Handle.IsCompleted) { Start-Sleep -Milliseconds 20 }

            $r = Receive-MMGalleryLookup -Job $job
            @($r.Dependencies | ForEach-Object { "$($_.Name)|$($_.VersionRange)" }) | Should -Be @('MMCore|[1.0, )', 'MMAny|')
            $script:MMGalleryCache[(Get-MMCacheKey 'MMOne' 'PSGallery' $false)] | Should -Not -BeNullOrEmpty
            @(Receive-MMGalleryLookup -Job $job).Count | Should -Be 0   # already collected
        }
    }

    It 'Stops lookups that are still running' {
        InModuleScope ModuleManager {
            $pool = [runspacefactory]::CreateRunspacePool(1, 1)
            $pool.Open()
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript({ Start-Sleep -Seconds 30 })
            $task = [pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Collected = $false }
            $job = [pscustomobject]@{ Tasks = @($task); Pool = $pool }

            Stop-MMGalleryLookup -Job $job
            $task.Collected | Should -BeTrue
            $job.Pool | Should -BeNullOrEmpty
            { Stop-MMGalleryLookup -Job $null } | Should -Not -Throw
        }
    }
}

Describe 'Package manager detection' {

    AfterEach {
        InModuleScope ModuleManager { $script:MMBackend = $null; $script:MMRepositories = $null }
    }

    It 'Picks <Expected> when <Available> is available' -ForEach @(
        @{ Available = 'Find-PSResource'; Expected = 'PSResourceGet' }
        @{ Available = 'Find-Module'; Expected = 'PowerShellGet' }
        @{ Available = 'nothing'; Expected = 'None' }
    ) {
        InModuleScope ModuleManager -Parameters $_ {
            $script:MMBackend = $null
            Mock Get-Command { if ($Name -eq $Available) { [pscustomobject]@{ Name = $Name } } }
            Get-MMBackend | Should -Be $Expected
            Get-MMBackend | Should -Be $Expected
            Should -Invoke Get-Command -ParameterFilter { $Name -eq 'Find-PSResource' } -Times 1 -Exactly   # then cached
        }
    }

    It 'Lists registered repositories with <Backend>' -ForEach @(
        @{ Backend = 'PSResourceGet' }
        @{ Backend = 'PowerShellGet' }
        @{ Backend = 'None' }
    ) {
        InModuleScope ModuleManager -Parameters $_ {
            $script:MMRepositories = $null
            Mock Get-MMBackend { $Backend }
            Mock Get-PSResourceRepository { [pscustomobject]@{ Name = 'PSGallery'; Trusted = $false }, [pscustomobject]@{ Name = 'Internal'; Trusted = $true } }
            Mock Get-PSRepository { [pscustomobject]@{ Name = 'PSGallery'; InstallationPolicy = 'Untrusted' }, [pscustomobject]@{ Name = 'Internal'; InstallationPolicy = 'Trusted' } }
            $expected = @('PSGallery', 'Internal')
            if ($Backend -eq 'None') { $expected = @() }
            @(Get-MMRegisteredRepository) | Should -Be $expected
            @(Get-MMUntrustedRepository -Name 'PSGallery', 'Internal', '', 'PSGallery') | Should -Be @($expected | Select-Object -First 1)
        }
    }

    It 'Copes when repositories cannot be listed' {
        InModuleScope ModuleManager {
            $script:MMRepositories = $null
            Mock Get-MMBackend { 'PSResourceGet' }
            Mock Get-PSResourceRepository { throw 'repository store is corrupt' }
            @(Get-MMRegisteredRepository).Count | Should -Be 0
            @(Get-MMUntrustedRepository -Name 'PSGallery').Count | Should -Be 0
            @(Get-MMUntrustedRepository -Name @()).Count | Should -Be 0
        }
    }

    It 'Uses the repository each module came from, if it is registered' {
        InModuleScope ModuleManager {
            $script:MMRepositories = @('PSGallery', 'Internal')
            $modules = @(
                [pscustomobject]@{ Name = 'MMOne'; Repository = 'Internal'; Prerelease = $null }
                [pscustomobject]@{ Name = 'MMTwo'; Repository = 'Gone'; Prerelease = 'beta' }
                [pscustomobject]@{ Name = 'MMThree'; Repository = $null; Prerelease = $null }
            )
            $r = @(New-MMLookupRequest -ModuleInfo $modules)
            @($r | ForEach-Object { "$($_.Name) $($_.Repository) $($_.Prerelease)" }) | Should -Be @('MMOne Internal False', 'MMTwo PSGallery True', 'MMThree PSGallery False')
            (New-MMLookupRequest -ModuleInfo $modules[0] -Repository 'Other' -IncludePrerelease).Repository | Should -Be 'Other'
        }
    }
}

Describe 'Invoke-MMInstall' {

    It 'Installs with PSResourceGet' {
        InModuleScope ModuleManager {
            Mock Get-MMBackend { 'PSResourceGet' }
            Mock Install-PSResource { }
            Invoke-MMInstall -Name 'MMOne' -Version '2.0.0-beta1' -Prerelease $true -Repository 'PSGallery' -Scope CurrentUser -TrustRepository
            Should -Invoke Install-PSResource -Times 1 -ParameterFilter {
                $Name -eq 'MMOne' -and $Version -eq '[2.0.0-beta1]' -and $Prerelease -and $TrustRepository -and $Scope -eq 'CurrentUser'
            }
        }
    }

    It 'Installs with PowerShellGet' {
        InModuleScope ModuleManager {
            Mock Get-MMBackend { 'PowerShellGet' }
            Mock Install-Module { }
            Invoke-MMInstall -Name 'MMOne' -Version '2.0.0' -Prerelease $true -Repository 'PSGallery' -Scope AllUsers -TrustRepository
            Should -Invoke Install-Module -Times 1 -ParameterFilter {
                $Name -eq 'MMOne' -and $RequiredVersion -eq '2.0.0' -and $AllowPrerelease -and $Force -and $Scope -eq 'AllUsers'
            }
        }
    }

    It 'Installs with PowerShellGet 1.x, which has no -AllowClobber or -AllowPrerelease' {
        InModuleScope ModuleManager {
            Mock Get-MMBackend { 'PowerShellGet' }
            Mock Get-Command { [pscustomobject]@{ Parameters = @{ Name = $null; RequiredVersion = $null } } } -ParameterFilter { $Name -eq 'PowerShellGet\Install-Module' }
            Mock Install-Module { }
            Invoke-MMInstall -Name 'MMOne' -Version '2.0.0' -Repository 'PSGallery' -Scope CurrentUser
            Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
                -not $PSBoundParameters.ContainsKey('AllowClobber') -and -not $PSBoundParameters.ContainsKey('AllowPrerelease')
            }
            { Invoke-MMInstall -Name 'MMOne' -Version '2.0.0-beta1' -Prerelease $true -Repository 'PSGallery' -Scope CurrentUser } |
                Should -Throw "*can't install prerelease versions*"
        }
    }

    It 'Fails clearly with no package manager' {
        InModuleScope ModuleManager {
            Mock Get-MMBackend { 'None' }
            { Invoke-MMInstall -Name 'MMOne' -Version '1.0' -Repository 'PSGallery' -Scope CurrentUser } | Should -Throw '*Neither*'
        }
    }
}

Describe 'Test-MMIsAdmin' {

    It 'Returns a boolean on <Platform>' -ForEach @(@{ Platform = 'this platform'; Windows = $null }, @{ Platform = 'a non-Windows platform'; Windows = $false }) {
        InModuleScope ModuleManager -Parameters $_ {
            $saved = $script:MMIsWindows
            try {
                if ($null -ne $Windows) { $script:MMIsWindows = $Windows }
                Test-MMIsAdmin | Should -BeOfType [bool]
            }
            finally { $script:MMIsWindows = $saved }
        }
    }
}
