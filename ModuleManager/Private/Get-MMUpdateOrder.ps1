function Get-MMUpdateOrder {
    <#
    .SYNOPSIS
        Orders updates so that each module is updated after the modules it depends on.

    .DESCRIPTION
        Orders updates so that each module comes after the modules it depends on (for example
        Az.Accounts, then the Az.* modules, then the Az rollup). Otherwise the original order is kept.
        Uses the dependencies of both the latest version (from the repository) and the newest
        installed version. Dependency cycles are broken rather than reported.
    #>
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Update)

    $byName = @{}
    foreach ($u in $Update) { $byName[$u.Name.ToLowerInvariant()] = $u }
    $state = @{}
    $order = [System.Collections.Generic.List[object]]::new()

    $visit = {
        param($u)
        $key = $u.Name.ToLowerInvariant()
        if ($state.ContainsKey($key)) { return }
        $state[$key] = $true
        $deps = @()
        foreach ($p in 'LatestDependencies', 'Dependencies') {
            if ($u.PSObject.Properties[$p]) { $deps += @($u.$p) }
        }
        foreach ($d in $deps) {
            if (-not $d) { continue }
            $dk = $d.Name.ToLowerInvariant()
            if ($dk -ne $key -and $byName.ContainsKey($dk)) { & $visit $byName[$dk] }
        }
        $order.Add($u)
    }
    foreach ($u in $Update) { & $visit $u }
    $order.ToArray()
}
