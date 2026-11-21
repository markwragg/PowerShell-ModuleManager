function Receive-MMGalleryLookup {
    <#
    .SYNOPSIS
        Collects finished repository lookups from a lookup job, returning only the new results.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Job)

    foreach ($task in $Job.Tasks) {
        if ($task.Collected -or -not $task.Handle.IsCompleted) { continue }
        $task.Collected = $true
        $output = @()
        $failure = $null
        try { $output = @($task.PowerShell.EndInvoke($task.Handle)) }
        catch { $failure = $_.Exception.Message }
        finally { $task.PowerShell.Dispose() }

        if ($failure) {
            $output = foreach ($n in $task.Names) {
                [pscustomobject]@{
                    RequestedName = $n; Name = $n; Repository = $task.Repository; Prerelease = $task.Prerelease
                    Status = 'Error'; Version = $null; ModuleVersion = $null; PrereleaseLabel = $null; PublishedDate = $null
                    Dependencies = @(); Error = $failure
                }
            }
        }

        foreach ($o in $output) {
            if ($null -eq $o) { continue }
            $rawDeps = @()
            if ($o.PSObject.Properties['Dependencies']) { $rawDeps = @($o.Dependencies) }
            $deps = @(foreach ($d in $rawDeps) {
                    if (-not $d) { continue }
                    $parts = ([string]$d).Split('|', 2)
                    $range = ''
                    if ($parts.Count -gt 1) { $range = $parts[1] }
                    New-MMDependency -Name $parts[0] -VersionRange $range
                })
            $unlistedVersions = $null
            if ($o.PSObject.Properties['UnlistedVersions'] -and $null -ne $o.UnlistedVersions) { $unlistedVersions = [string[]]@($o.UnlistedVersions) }
            $result = [pscustomobject]@{
                RequestedName   = [string]$o.RequestedName
                Name            = [string]$o.Name
                Repository      = [string]$o.Repository
                Prerelease      = [bool]$o.Prerelease
                Status          = [string]$o.Status
                Version         = $o.Version
                ModuleVersion   = $o.ModuleVersion
                PrereleaseLabel = $o.PrereleaseLabel
                PublishedDate   = $o.PublishedDate
                Dependencies    = $deps
                Error           = $o.Error
                # Installed versions the publisher has unlisted; $null when that wasn't checked.
                UnlistedVersions = $unlistedVersions
                CachedAt        = [datetime]::UtcNow
            }
            if ($result.Status -ne 'Error') {
                $script:MMGalleryCache[(Get-MMCacheKey $result.RequestedName $result.Repository $result.Prerelease)] = $result
            }
            $Job.Results.Add($result)
            $result
        }
    }

    $Job.Done = $Job.Results.Count
    if ($Job.Pool -and -not ($Job.Tasks | Where-Object { -not $_.Collected })) {
        $Job.Pool.Close()
        $Job.Pool.Dispose()
        $Job.Pool = $null
    }
}
