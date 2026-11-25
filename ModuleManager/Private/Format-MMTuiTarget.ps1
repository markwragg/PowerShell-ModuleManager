function Format-MMTuiTarget {
    <#
    .SYNOPSIS
        Describes a set of installed versions for a terminal UI prompt, such as "Pester 5.5.0, 5.6.1" or "3 modules (7 versions)".
    #>
    param([hashtable]$State, [object[]]$Installation)
    # By module rather than name, as different modules can share a name (see Group-MMInstallation).
    $moduleOf = @{}
    foreach ($r in $State.Rows) { foreach ($i in @($r.Info.Installations)) { $moduleOf[$i.ModuleBase] = $r } }
    $groups = @($Installation | Group-Object -Property { $r = $moduleOf[$_.ModuleBase]; if ($r -and $r.PSObject.Properties['Key'] -and $r.Key) { $r.Key } else { $_.Name.ToLowerInvariant() } })
    $whole = @($groups | Where-Object { $r = $moduleOf[$_.Group[0].ModuleBase]; $r -and $_.Count -eq $r.Info.VersionCount }).Count -eq $groups.Count

    if ($groups.Count -eq 1) {
        $g = $groups[0]
        $name = $g.Group[0].Name
        if ($whole) { return "$name ($($g.Count) version(s))" }
        return "$name $(@($g.Group | ForEach-Object { $_.Version }) -join ', ')"
    }
    if ($whole) { return "$($groups.Count) modules ($($Installation.Count) versions)" }
    "$($Installation.Count) versions of $($groups.Count) modules"
}
