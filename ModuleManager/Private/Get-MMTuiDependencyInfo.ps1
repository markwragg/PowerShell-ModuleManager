function Get-MMTuiDependencyInfo {
    <#
    .SYNOPSIS
        Returns what one installed version depends on, and which installed versions depend on it.

    .DESCRIPTION
        For the details view. Returns @{ Known; DependsOn; RequiredBy }:
          Known       $false when the version's dependencies weren't read (see New-MMInstalledVersion)
          DependsOn   one entry per dependency: Name, Range (as Format-MMVersionRange shows it) and
                      Installed, the newest version in the list that's in its range ($null if none)
          RequiredBy  one entry per module with versions that depend on this one, and accept this
                      version: Name and Versions (newest first)
        Only the modules in the terminal UI's list are looked at, so a dependency outside it (such as
        a system module, without -IncludeSystem) has no installed version. Results are kept in
        $State.DepInfo by folder, and the index of every installed version in $State.DepIndex, until
        the modules are rescanned.
    #>
    param([hashtable]$State, [object]$Installation)
    $key = $Installation.ModuleBase
    if ($State.DepInfo.ContainsKey($key)) { return $State.DepInfo[$key] }

    if (-not $State.DepIndex) {
        # By name (lower case): the installed versions, newest first, and the versions that depend on it.
        # Rows are one per module and each one's installations are newest first, so neither needs sorting.
        $byName = @{}
        $dependents = @{}
        foreach ($row in $State.Rows) {
            foreach ($i in @($row.Info.Installations)) {
                $n = $i.Name.ToLowerInvariant()
                if (-not $byName.ContainsKey($n)) { $byName[$n] = [System.Collections.Generic.List[object]]::new() }
                $byName[$n].Add($i)
                foreach ($dep in @($i.Dependencies)) {
                    if (-not $dep -or -not $dep.Name) { continue }
                    $d = ([string]$dep.Name).ToLowerInvariant()
                    if ($d -eq $n) { continue }
                    if (-not $dependents.ContainsKey($d)) { $dependents[$d] = [System.Collections.Generic.List[object]]::new() }
                    $dependents[$d].Add(@($i, [string]$dep.VersionRange))
                }
            }
        }
        $State.DepIndex = @{ ByName = $byName; Dependents = $dependents }
    }
    $index = $State.DepIndex
    $name = $Installation.Name.ToLowerInvariant()

    $known = $true
    if ($Installation.PSObject.Properties['DependenciesKnown']) { $known = [bool]$Installation.DependenciesKnown }

    $dependsOn = [System.Collections.Generic.List[object]]::new()
    foreach ($dep in @($Installation.Dependencies)) {
        if (-not $dep -or -not $dep.Name -or ([string]$dep.Name).ToLowerInvariant() -eq $name) { continue }
        $installed = $null
        $candidates = $index.ByName[([string]$dep.Name).ToLowerInvariant()]
        if ($candidates) {
            foreach ($c in $candidates) {
                if (Test-MMVersionInRange $c.ModuleVersion $c.Prerelease ([string]$dep.VersionRange)) { $installed = $c.Version; break }
            }
        }
        $dependsOn.Add([pscustomobject]@{ Name = [string]$dep.Name; Range = (Format-MMVersionRange ([string]$dep.VersionRange)); Installed = $installed })
    }

    # The index is in the list's order (by name, then newest version first), so this is too. Many
    # dependents share a range (such as every Az module needing Az.Accounts [5.4.0, )), so each range
    # is checked once.
    $requiredBy = [ordered]@{}
    $inRange = @{}
    $entries = $index.Dependents[$name]
    if ($entries) {
        foreach ($e in $entries) {
            $range = $e[1]
            if (-not $inRange.ContainsKey($range)) { $inRange[$range] = Test-MMVersionInRange $Installation.ModuleVersion $Installation.Prerelease $range }
            if (-not $inRange[$range]) { continue }
            $dependent = $e[0]
            $n = $dependent.Name.ToLowerInvariant()
            if (-not $requiredBy.Contains($n)) { $requiredBy[$n] = [pscustomobject]@{ Name = $dependent.Name; Versions = [System.Collections.Generic.List[string]]::new() } }
            if (-not $requiredBy[$n].Versions.Contains($dependent.Version)) { $requiredBy[$n].Versions.Add($dependent.Version) }
        }
    }

    $info = @{ Known = $known; DependsOn = $dependsOn.ToArray(); RequiredBy = @($requiredBy.Values) }
    $State.DepInfo[$key] = $info
    $info
}
