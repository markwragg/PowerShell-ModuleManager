function Get-MMTuiReclaimSize {
    <#
    .SYNOPSIS
        The space removing a row's old versions would free, in bytes (with its family's, when collapsed).

    .DESCRIPTION
        $null while it's still being worked out (see Update-MMTuiReclaimable), and -1 when there's
        nothing to remove, so that sorts below modules whose old versions are empty folders.
    #>
    param([hashtable]$State, [object]$Row)
    $reclaim = $State.Reclaim
    if (-not $reclaim -or -not $reclaim.Done) { return $null }
    $total = 0L
    $any = $false
    foreach ($member in (Get-MMTuiFamily $State $Row)) {
        $bases = $reclaim.ByName[$member.Name.ToLowerInvariant()]
        if (-not $bases) { continue }
        # Only this module's: different modules can share a name (see Group-MMInstallation).
        $own = @{}
        foreach ($i in @($member.Info.Installations)) { $own[[string]$i.ModuleBase] = $true }
        foreach ($b in $bases) {
            if (-not $own.ContainsKey([string]$b)) { continue }
            if (-not $State.Sizes.ContainsKey($b)) { return $null }
            $total += [long]$State.Sizes[$b]
            $any = $true
        }
    }
    if (-not $any) { return -1L }
    $total
}
