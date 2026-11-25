function Update-MMTuiVisible {
    <#
    .SYNOPSIS
        Works out which rows the terminal UI shows, and in what order, keeping the cursor on the same
        module.

    .DESCRIPTION
        Applies view, filter and sort, and keeps the cursor on the same module.
        With grouping on, family members are listed under their parent (see Set-MMTuiFamily):
        only when the family is expanded, or when a view or filter matches them.

        With -IfChanged it does nothing when none of what it works from has changed since it last
        ran: the rows, their statuses (see Update-MMTuiStatus), the view, sort, grouping, expanded
        families, filter, whether the Reclaimable column shows and whether it's worked out. That's most key presses (moving the cursor, selecting), and sorting
        takes a while with many modules.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    param([hashtable]$State, [switch]$IfChanged)

    # Reclaimable is only a sort while its column is showing (see Test-MMTuiReclaimShown); otherwise
    # it's back to Name.
    $reclaimShown = Test-MMTuiReclaimShown $State
    if ($State.Sorts[$State.Sort] -eq 'Reclaimable' -and -not $reclaimShown) { $State.Sort = 0 }
    $reclaimDone = $false
    if ($State.Reclaim) { $reclaimDone = $State.Reclaim.Done }

    # The filter goes last, as it can contain any character. Sorting by Reclaimable is done again
    # once it's all worked out.
    $key = "$($State.View)|$($State.Sort)|$reclaimShown|$reclaimDone|$($State.InScope)|$($State.Group)|$($State.StatusVersion)|$([string]::Join('/', [string[]]@($State.Expanded.Keys)))|$($State.Filter)"
    $last = $State.VisibleKey
    if ($IfChanged -and $last -and [object]::ReferenceEquals($last.Rows, $State.Rows) -and $last.Key -ceq $key) { return }
    $State.VisibleKey = @{ Rows = $State.Rows; Key = $key }

    $view = $State.Views[$State.View]
    $scope = $State.Scopes[$State.InScope]
    $f = $State.Filter
    # n: matches only names and d: only descriptions; without a prefix the filter matches either.
    $inName = $inDescription = $true
    if ($f -match '^(?<p>[nd]):') {
        $inName = $Matches.p -eq 'n'
        $inDescription = -not $inName
        $f = $f.Substring(2)
    }
    $match = {
        param($r)
        switch ($view) {
            'Updates' { if ($r.Status -ne 'UpdateAvailable') { return $false } }
            'Multiple versions' { if ($r.Info.VersionCount -le 1) { return $false } }
            'Loaded' { if (-not $r.Info.IsLoaded) { return $false } }
        }
        # A module is in a scope when any of its versions is (its Scope lists them, such as
        # 'CurrentUser, AllUsers').
        if ($scope -ne 'All' -and $scope -notin @($r.Info.Scope -split ', ')) { return $false }
        if ($f -and -not (($inName -and $r.Name -like "*$f*") -or ($inDescription -and $r.Info.Description -like "*$f*"))) { return $false }
        $true
    }
    $narrowed = ($view -ne 'All') -or ($scope -ne 'All') -or [bool]$f

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
        $shownChildren[$r.Key] = $kids
    }

    # Sort the top level, and the members shown under each family; a family sorts by its most
    # urgent status (a member has no children, so it sorts by its own).
    $statusKey = {
        $s = $script:MMStatusSortOrder[$_.Status]
        if ($grouped) {
            foreach ($c in $_.Children) { $cs = $script:MMStatusSortOrder[$c.Status]; if ($cs -lt $s) { $s = $cs } }
        }
        $s
    }
    $sortName = $State.Sorts[$State.Sort]
    # Key last, so different modules of the same name keep the same order (the main one first, see
    # Group-MMInstallation): Sort-Object in Windows PowerShell doesn't keep the order of ties.
    $sortRows = {
        param($in)
        switch ($sortName) {
            'Status' { @($in | Sort-Object $statusKey, Name, Key) }
            'Versions' { @($in | Sort-Object @{ Expression = { $_.Info.VersionCount }; Descending = $true }, @{ Expression = 'Name'; Descending = $false }, @{ Expression = 'Key'; Descending = $false }) }
            'Scope' { @($in | Sort-Object { $_.Info.Scope }, Name, Key) }
            # Most first; modules still being worked out last.
            'Reclaimable' {
                @($in | Sort-Object @{ Expression = { $b = Get-MMTuiReclaimSize $State $_; if ($null -eq $b) { -2L } else { $b } }; Descending = $true },
                    @{ Expression = 'Name'; Descending = $false }, @{ Expression = 'Key'; Descending = $false })
            }
            default { @($in | Sort-Object Name, Key) }
        }
    }
    $rows = & $sortRows $top.ToArray()

    $visible = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $rows) {
        $visible.Add($r)
        $kids = @(& $sortRows @($shownChildren[$r.Key]))
        for ($i = 0; $i -lt $kids.Count; $i++) {
            $kids[$i].Indent = 1
            $kids[$i].Last = ($i -eq $kids.Count - 1)
            $visible.Add($kids[$i])
        }
    }
    $State.Visible = $visible.ToArray()

    if ($State.CurrentName) {
        for ($i = 0; $i -lt $State.Visible.Count; $i++) {
            if ($State.Visible[$i].Key -eq $State.CurrentName) { $State.Cursor = $i; break }
        }
    }
    Set-MMTuiCursor $State $State.Cursor
}
