function Update-MMTuiVisible {
    <#
    .SYNOPSIS
        Works out which rows the terminal UI shows, and in what order, keeping the cursor on the same
        module.

    .DESCRIPTION
        Applies view, filter and sort, and keeps the cursor on the same module.
        With grouping on, family members are listed under their parent (see Set-MMTuiFamily):
        only when the family is expanded, or when a view or filter matches them.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    param([hashtable]$State)

    $view = $State.Views[$State.View]
    $f = $State.Filter
    $match = {
        param($r)
        switch ($view) {
            'Updates' { if ($r.Status -ne 'UpdateAvailable') { return $false } }
            'Multiple versions' { if ($r.Info.VersionCount -le 1) { return $false } }
            'Loaded' { if (-not $r.Info.IsLoaded) { return $false } }
        }
        if ($f -and -not ($r.Name -like "*$f*" -or $r.Info.Description -like "*$f*")) { return $false }
        $true
    }
    $narrowed = ($view -ne 'All') -or [bool]$f

    foreach ($r in $State.Rows) { $r.Indent = 0; $r.Last = $false; $r.Open = $false }

    $grouped = $State.Group
    $top = [System.Collections.Generic.List[object]]::new()
    $shownChildren = @{}
    foreach ($r in $State.Rows) {
        if ($grouped -and $r.Parent) { continue }
        $kids = @()
        if ($grouped -and $r.Children.Count) {
            $expanded = $State.Expanded.ContainsKey($r.Name.ToLowerInvariant())
            $matching = @($r.Children | Where-Object { & $match $_ })
            if ($narrowed) { $kids = $matching }       # show the members the view/filter found
            elseif ($expanded) { $kids = @($r.Children) }
            if (-not (& $match $r) -and -not $matching) { continue }
        }
        elseif (-not (& $match $r)) { continue }
        $r.Open = $kids.Count -gt 0
        $top.Add($r)
        $shownChildren[$r.Name] = $kids
    }

    # Sort the top level; a family sorts by its most urgent status.
    $statusKey = {
        $s = $script:MMStatusSortOrder[$_.Status]
        if ($grouped) {
            foreach ($c in $_.Children) { $cs = $script:MMStatusSortOrder[$c.Status]; if ($cs -lt $s) { $s = $cs } }
        }
        $s
    }
    $rows = $top.ToArray()
    switch ($State.Sorts[$State.Sort]) {
        'Status' { $rows = @($rows | Sort-Object $statusKey, Name) }
        'Versions' { $rows = @($rows | Sort-Object @{ Expression = { $_.Info.VersionCount }; Descending = $true }, @{ Expression = 'Name'; Descending = $false }) }
        'Scope' { $rows = @($rows | Sort-Object { $_.Info.Scope }, Name) }
        default { $rows = @($rows | Sort-Object Name) }
    }

    $visible = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $rows) {
        $visible.Add($r)
        $kids = @($shownChildren[$r.Name])
        for ($i = 0; $i -lt $kids.Count; $i++) {
            $kids[$i].Indent = 1
            $kids[$i].Last = ($i -eq $kids.Count - 1)
            $visible.Add($kids[$i])
        }
    }
    $State.Visible = $visible.ToArray()

    if ($State.CurrentName) {
        for ($i = 0; $i -lt $State.Visible.Count; $i++) {
            if ($State.Visible[$i].Name -eq $State.CurrentName) { $State.Cursor = $i; break }
        }
    }
    Set-MMTuiCursor $State $State.Cursor
}
