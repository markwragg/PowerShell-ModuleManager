function Start-MMGalleryLookup {
    <#
    .SYNOPSIS
        Starts looking up the latest version of each module in parallel.

    .DESCRIPTION
        Starts looking up the latest version of each requested module in parallel using a
        runspace pool. Returns a job object; use Receive-MMGalleryLookup to collect results.
        Cached results are returned immediately without querying the repository.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Starts read-only repository lookups in background runspaces; changes no system state.')]
    param(
        [object[]]$Request,
        [ValidateRange(1, 64)][int]$ThrottleLimit = 16,
        [ValidateRange(1, 100)][int]$BatchSize = 6,
        [switch]$Refresh
    )

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
    if ($backend -eq 'PSResourceGet') { $iss.ImportPSModule('Microsoft.PowerShell.PSResourceGet') }
    else { $iss.ImportPSModule('PowerShellGet') }

    $pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit, $iss, $Host)
    $pool.Open()
    $job.Pool = $pool

    $groups = $pending | Group-Object -Property { "$($_.Repository)|$($_.Prerelease)" }
    foreach ($group in $groups) {
        $first = $group.Group[0]
        $names = @($group.Group | ForEach-Object { $_.Name })
        for ($i = 0; $i -lt $names.Count; $i += $BatchSize) {
            $chunk = @($names[$i..([Math]::Min($i + $BatchSize, $names.Count) - 1)])
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($script:MMLookupScript.ToString()).
                AddArgument($chunk).AddArgument($first.Repository).AddArgument([bool]$first.Prerelease).AddArgument($backend)
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
