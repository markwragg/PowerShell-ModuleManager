function Get-MMRequiredInstallation {
    <#
    .SYNOPSIS
        Works out which of the versions about to be removed must be kept because other modules need them.

    .DESCRIPTION
        Works out which of the versions about to be removed must be kept because a module that
        will still be installed depends on them. A dependency is satisfied if any version that
        stays installed is inside its version range; if every matching version is being removed,
        the newest of them is kept.

        Returns one object per version to keep: the installation and the dependents (with the
        range each one needs). Kept versions are themselves treated as staying installed, so
        their own dependencies are protected too.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Removing,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AllInstallation
    )
    if (-not $Removing) { return }

    $removingKeys = @{}
    $removingNames = @{}
    foreach ($r in $Removing) {
        $removingKeys[(Get-MMPathKey $r.ModuleBase)] = $true
        $removingNames[$r.Name.ToLowerInvariant()] = $true
    }
    $byName = @{}
    foreach ($i in $AllInstallation) {
        $n = $i.Name.ToLowerInvariant()
        if (-not $byName.ContainsKey($n)) { $byName[$n] = [System.Collections.Generic.List[object]]::new() }
        $byName[$n].Add($i)
    }

    $kept = [ordered]@{}
    $queue = [System.Collections.Generic.Queue[object]]::new()
    foreach ($i in $AllInstallation) {
        if (-not $removingKeys.ContainsKey((Get-MMPathKey $i.ModuleBase))) { $queue.Enqueue($i) }
    }

    # Many dependents share the same requirement (e.g. ~80 Az modules need Az.Accounts [5.4.0, )),
    # so the matching versions are worked out once per name and range. Each entry holds
    # @(installation, path key) pairs, newest first.
    $matching = @{}

    while ($queue.Count) {
        $dependent = $queue.Dequeue()
        foreach ($dep in @($dependent.Dependencies)) {
            if (-not $dep) { continue }
            $depName = $dep.Name.ToLowerInvariant()
            # Only dependencies on modules that are losing a version can be broken.
            if (-not $removingNames.ContainsKey($depName) -or $depName -eq $dependent.Name.ToLowerInvariant()) { continue }

            $cacheKey = "$depName|$($dep.VersionRange)"
            $candidates = $matching[$cacheKey]
            if ($null -eq $candidates) {
                $candidates = @(foreach ($c in (Get-MMSortedInstallation @($byName[$depName]))) {
                        if (Test-MMVersionInRange $c.ModuleVersion $c.Prerelease $dep.VersionRange) { , @($c, (Get-MMPathKey $c.ModuleBase)) }
                    })
                $matching[$cacheKey] = $candidates
            }
            if (-not $candidates.Count) { continue }   # never satisfied, so removing versions can't break it

            $requirement = "$($dependent.Name) $($dependent.Version)"
            if ($dep.VersionRange) { $requirement += " needs $($dep.VersionRange)" }

            $satisfied = $false
            foreach ($c in $candidates) {
                if ($kept.Contains($c[1])) { $kept[$c[1]].RequiredBy.Add($requirement); $satisfied = $true; break }
                if (-not $removingKeys.ContainsKey($c[1])) { $satisfied = $true; break }
            }
            if ($satisfied) { continue }

            $keep = $candidates[0][0]
            $key = $candidates[0][1]
            $removingKeys.Remove($key)
            $kept[$key] = [pscustomobject]@{
                Installation = $keep
                RequiredBy   = [System.Collections.Generic.List[string]]::new()
            }
            $kept[$key].RequiredBy.Add($requirement)
            $queue.Enqueue($keep)
        }
    }
    $kept.Values
}
