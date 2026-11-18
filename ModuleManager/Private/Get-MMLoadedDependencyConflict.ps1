function Get-MMLoadedDependencyConflict {
    <#
    .SYNOPSIS
        Finds loaded modules that are too old for the new versions about to be installed.

    .DESCRIPTION
        Finds modules loaded in this session at a version that the latest version of a module
        being updated doesn't accept (for example Az.Accounts 5.4.0 loaded, while the new
        Az.Compute needs [5.5.0, )). The update still installs, but a module can only be loaded
        once per session, so the new version can't be used until a new session is started.

        Returns one object per loaded module: Name, LoadedVersion, and the modules that need a
        different version, with the range each needs.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Update,
        [object[]]$LoadedModule = @(Get-MMLoadedModule)
    )

    $loaded = @{}
    foreach ($m in $LoadedModule) {
        # Checked step by step rather than in a try/catch: under strict mode a missing key throws,
        # and a caught error still lands in the caller's -ErrorVariable (the terminal UI reports
        # those as failures).
        $pre = $null
        $private = $null
        if ($m.PSObject.Properties['PrivateData']) { $private = $m.PrivateData }
        if ($private -is [System.Collections.IDictionary] -and $private['PSData'] -is [System.Collections.IDictionary]) {
            $pre = $private['PSData']['Prerelease']
        }
        $key = $m.Name.ToLowerInvariant()
        if (-not $loaded.ContainsKey($key)) { $loaded[$key] = [System.Collections.Generic.List[object]]::new() }
        $loaded[$key].Add(@{ Name = $m.Name; Version = $m.Version; Prerelease = $pre })
    }

    $conflicts = [ordered]@{}
    foreach ($u in $Update) {
        if (-not $u.PSObject.Properties['LatestDependencies']) { continue }
        foreach ($dep in @($u.LatestDependencies)) {
            if (-not $dep) { continue }
            $key = $dep.Name.ToLowerInvariant()
            if (-not $loaded.ContainsKey($key)) { continue }
            $ok = $false
            foreach ($l in $loaded[$key]) {
                if (Test-MMVersionInRange $l.Version $l.Prerelease $dep.VersionRange) { $ok = $true; break }
            }
            if ($ok) { continue }
            if (-not $conflicts.Contains($key)) {
                $first = $loaded[$key][0]
                $text = [string]$first.Version
                if ($first.Prerelease) { $text = "$text-$($first.Prerelease)" }
                $conflicts[$key] = [pscustomobject]@{
                    Name          = $first.Name
                    LoadedVersion = $text
                    RequiredBy    = [System.Collections.Generic.List[string]]::new()
                }
            }
            $conflicts[$key].RequiredBy.Add("$($u.Name) $($u.LatestVersion) needs $($dep.VersionRange)")
        }
    }
    $conflicts.Values
}
