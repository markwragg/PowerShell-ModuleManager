function Format-MMTuiTarget {
    <#
    .SYNOPSIS
        Describes a set of installed versions for a terminal UI prompt, such as "Pester 5.5.0, 5.6.1" or "3 modules (7 versions)".
    #>
    param([hashtable]$State, [object[]]$Installation)
    $groups = @($Installation | Group-Object -Property Name)
    $total = @{}
    foreach ($r in $State.Rows) { $total[$r.Name] = $r.Info.VersionCount }
    $whole = @($groups | Where-Object { $_.Count -eq $total[$_.Name] }).Count -eq $groups.Count

    if ($groups.Count -eq 1) {
        $g = $groups[0]
        if ($whole) { return "$($g.Name) ($($g.Count) version(s))" }
        return "$($g.Name) $(@($g.Group | ForEach-Object { $_.Version }) -join ', ')"
    }
    if ($whole) { return "$($groups.Count) modules ($($Installation.Count) versions)" }
    "$($Installation.Count) versions of $($groups.Count) modules"
}
