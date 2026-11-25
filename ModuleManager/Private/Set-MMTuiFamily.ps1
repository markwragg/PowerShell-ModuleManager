function Set-MMTuiFamily {
    <#
    .SYNOPSIS
        Links module families (such as Az and the Az.* modules) for grouping in the terminal UI.

    .DESCRIPTION
        Links module families for the terminal UI: a module whose newest version depends on at
        least two installed modules named '<Module>.*' (Az -> Az.Accounts, Az.Compute ...;
        Microsoft.Graph -> Microsoft.Graph.*) becomes the parent of those rows.
        Sets Parent (name or $null) and Children (rows) on each row.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    param([AllowEmptyCollection()][object[]]$Rows)

    $byName = @{}
    foreach ($r in $Rows) {
        $r.Parent = $null
        $r.Children = @()
        # Only the main module of a name (see Group-MMInstallation) is in a family.
        if ($r.Key -eq $r.Name.ToLowerInvariant()) { $byName[$r.Key] = $r }
    }
    foreach ($p in $Rows) {
        if ($p.Key -ne $p.Name.ToLowerInvariant()) { continue }
        $prefix = $p.Name.ToLowerInvariant() + '.'
        $children = [System.Collections.Generic.List[object]]::new()
        foreach ($d in @($p.Info.Dependencies)) {
            if (-not $d) { continue }
            $key = $d.Name.ToLowerInvariant()
            if (-not $key.StartsWith($prefix) -or -not $byName.ContainsKey($key)) { continue }
            $child = $byName[$key]
            if ($child.Parent -or $children.Contains($child)) { continue }
            $children.Add($child)
        }
        if ($children.Count -lt 2) { continue }
        foreach ($c in $children) { $c.Parent = $p.Name }
        $p.Children = @($children | Sort-Object Name)
    }
}
