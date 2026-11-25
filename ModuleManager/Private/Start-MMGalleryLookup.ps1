function Start-MMGalleryLookup {
    <#
    .SYNOPSIS
        Starts looking up the latest version of each module in parallel.

    .DESCRIPTION
        Starts looking up the latest version of each requested module in parallel using a
        runspace pool. Returns a job object; use Receive-MMGalleryLookup to collect results.
        NuGet v2 feeds (such as the PowerShell Gallery) are queried directly over HTTP, in batches;
        other repositories are queried with the package manager.
        Cached results are returned immediately without querying the repository.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Starts read-only repository lookups in background runspaces; changes no system state.')]
    param(
        [object[]]$Request,
        [ValidateRange(1, 64)][int]$ThrottleLimit = 16,
        [ValidateRange(1, 100)][int]$BatchSize = 6,
        # Kept well under the v2 feed's page size (100 entries) and URL length limits.
        [ValidateRange(1, 50)][int]$ApiBatchSize = 30,
        [switch]$Refresh
    )

    # Different modules of the same name (see Group-MMInstallation) share a lookup: the first
    # request is kept, which is the main module's.
    $seen = @{}
    $Request = @(foreach ($r in $Request) {
            $k = Get-MMCacheKey $r.Name $r.Repository $r.Prerelease
            if ($seen.ContainsKey($k)) { continue }
            $seen[$k] = $true
            $r
        })

    $job = [pscustomobject]@{
        Tasks   = [System.Collections.Generic.List[object]]::new()
        Results = [System.Collections.Generic.List[object]]::new()
        Pool    = $null
        Total   = @($Request).Count
        Done    = 0
    }

    $pending = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $Request) {
        $hit = $null
        if (-not $Refresh) { $hit = Get-MMCachedResult $r }
        if ($hit) { $job.Results.Add($hit) } else { $pending.Add($r) }
    }
    $job.Done = $job.Results.Count
    if ($pending.Count -eq 0) { return $job }

    $backend = Get-MMBackend
    if ($backend -eq 'None') {
        foreach ($r in $pending) {
            $job.Results.Add([pscustomobject]@{
                    RequestedName = $r.Name; Name = $r.Name; Repository = $r.Repository; Prerelease = $r.Prerelease
                    Status = 'Error'; Version = $null; ModuleVersion = $null; PrereleaseLabel = $null; PublishedDate = $null
                    Dependencies = @(); Error = 'Neither Microsoft.PowerShell.PSResourceGet nor PowerShellGet is available.'; CachedAt = [datetime]::UtcNow
                })
        }
        $job.Done = $job.Results.Count
        return $job
    }

    $iss = [initialsessionstate]::CreateDefault2()
    if (Test-MMIsWindows) {
        try { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch { Write-Debug $_ }
    }
    $groups = @($pending | Group-Object -Property { "$($_.Repository)|$($_.Prerelease)" })
    # Loading the package manager into every runspace is slow (several seconds for PowerShellGet in
    # Windows PowerShell), so only do it when a repository isn't a v2 feed. Lookups that fall back to
    # it otherwise load it on first use.
    if (@($groups | Where-Object { -not (Get-MMRepositoryApi -Name $_.Group[0].Repository) }).Count -gt 0) {
        if ($backend -eq 'PSResourceGet') { $iss.ImportPSModule('Microsoft.PowerShell.PSResourceGet') }
        else { $iss.ImportPSModule('PowerShellGet') }
    }

    $pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit, $iss, $Host)
    $pool.Open()
    $job.Pool = $pool
    # PowerShellGet's commands take turns holding this, as PackageManagement fails when used in parallel.
    $lock = [System.Threading.SemaphoreSlim]::new(1, 1)

    foreach ($group in $groups) {
        $first = $group.Group[0]
        $names = @($group.Group | ForEach-Object { $_.Name })
        $installed = @{}
        $installedAll = @{}
        foreach ($r in $group.Group) {
            if ($r.PSObject.Properties['InstalledVersion'] -and $r.InstalledVersion) { $installed[$r.Name] = [string]$r.InstalledVersion }
            if ($r.PSObject.Properties['InstalledVersions'] -and $r.InstalledVersions) { $installedAll[$r.Name] = [string[]]@($r.InstalledVersions) }
        }
        # A NuGet v2 feed answers a whole batch in one request, so it takes bigger batches.
        $api = Get-MMRepositoryApi -Name $first.Repository
        $size = $BatchSize
        if ($api) { $size = $ApiBatchSize }
        for ($i = 0; $i -lt $names.Count; $i += $size) {
            $chunk = @($names[$i..([Math]::Min($i + $size, $names.Count) - 1)])
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($script:MMLookupScript.ToString()).
                AddArgument($chunk).AddArgument($first.Repository).AddArgument([bool]$first.Prerelease).AddArgument($backend).
                AddArgument($installed).AddArgument($api).AddArgument($lock).AddArgument($installedAll)
            $job.Tasks.Add([pscustomobject]@{
                    PowerShell = $ps
                    Handle     = $ps.BeginInvoke()
                    Names      = $chunk
                    Repository = $first.Repository
                    Prerelease = [bool]$first.Prerelease
                    Collected  = $false
                })
        }
    }
    $job
}
