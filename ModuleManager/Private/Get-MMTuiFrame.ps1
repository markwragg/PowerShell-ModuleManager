function Get-MMTuiFrame {
    <#
    .SYNOPSIS
        Renders the whole terminal UI screen as text.

    .DESCRIPTION
        Renders the whole screen as a string of $Height lines, each $Width visible characters.
    #>
    param([hashtable]$State, [int]$Width, [int]$Height)
    $w = $Width
    $h = $Height
    $State.Width = $w; $State.Height = $h
    $listHeight = $h - 4

    # Output pane (see Add-MMTuiLogLines): about 40% of the screen, leaving the list at least
    # 5 rows. Too small a window and it isn't shown; the status line still reports progress.
    $paneHeight = 0
    if ($State.LogOpen) {
        $paneHeight = [Math]::Min([Math]::Max(6, [int]($h * 0.4)), $listHeight - 5)
        if ($paneHeight -lt 3) { $paneHeight = 0 }
        $listHeight -= $paneHeight
    }
    $State.ListHeight = $listHeight

    # Where things are drawn, for mouse clicks (see Invoke-MMTuiMouse): rows (Y) and columns (X,
    # Start to before End) counted from 0. The list and details views fill in theirs; -1 is nowhere.
    $layout = @{
        HeaderY = -1; ListTop = -1; ListRows = 0; SortColumns = @(); DetailTop = -1; DetailRows = 0; CheckWidth = 0
        Links = [System.Collections.Generic.List[object]]::new()
        LogTop = -1; LogRows = 0; LogKeys = @(); StatusY = -1; HelpY = -1; TitleY = -1
        Title = [System.Collections.Generic.List[object]]::new()
        Help = [System.Collections.Generic.List[object]]::new(); Choices = [System.Collections.Generic.List[object]]::new()
    }
    $State.Layout = $layout

    $lines = [System.Collections.Generic.List[string]]::new()

    # --- Title bar
    # Counted in one pass, as this runs every frame (a pipeline per count is slow with many modules).
    # Found: modules the repository check found (newer than the repository counts as latest).
    $total = $State.Rows.Count
    $updates = 0; $selCount = 0; $found = 0
    foreach ($r in $State.Rows) {
        if ($r.Selected) { $selCount++ }
        switch ($r.Status) {
            'UpdateAvailable' { $updates++; $found++ }
            'UpToDate' { $found++ }
            'LocalNewer' { $found++ }
        }
    }
    $right = ''
    if ($State.Job) {
        $spin = '|/-\'[$State.Spinner % 4]
        $right = "$spin Checking repositories $($State.Job.Done)/$($State.Job.Total) "
    }
    if ($State.Task) {
        $spin = '|/-\'[$State.Spinner % 4]
        $right = "$spin $($State.Task.Title)"
        if ($State.Progress) { $right += " $([int]$State.Progress.Percent)%" }
        $right += ' '
    }
    # The share of modules on their latest version, of those the repository check found. Shown
    # once the check is done, and only if it fits.
    $latest = ''
    if ($found -and -not $State.Job) { $latest = "  |  $([Math]::Floor(100 * ($found - $updates) / $found))% latest" }

    $title = @(
        , @(' ModuleManager ', 'TitleBold')
        , @(" $total modules  |  $updates updates", $null)
        , @("  |  view: $($State.Views[$State.View])", $null)
        , @("  |  sort: $($State.Sorts[$State.Sort])", $null)
    )
    if ($State.Remote) { $title = @(, $title[0]) + @(, @("on $($State.Remote.Name) ", 'TitleBold')) + $title[1..($title.Count - 1)] }
    # Show-ModuleManager -WhatIf: operations only say what they would change.
    $whatIf = $State.Options -and $State.Options['WhatIf']
    if ($whatIf) { $title = @(, $title[0]) + @(, @(' WHATIF ', 'WhatIf')) + $title[1..($title.Count - 1)] }
    $selected = @()
    if ($selCount) { $selected += "$selCount module(s)" }
    if ($State.DSelected.Count) { $selected += "$($State.DSelected.Count) version(s)" }
    if ($selected) { $title += , @("  |  $($selected -join ', ') selected", $null) }
    if ($State.Filter) { $title += , @("  |  filter: $($State.Filter)", $null) }
    $leftLen = 0; foreach ($t in $title) { $leftLen += ([string]$t[0]).Length }
    if ($latest -and $leftLen + $latest.Length + $right.Length -le $w) {
        $at = 2
        if ($State.Remote) { $at++ }
        if ($whatIf) { $at++ }
        $title = $title[0..($at - 1)] + @(, @($latest, $null)) + $title[$at..($title.Count - 1)]
        $leftLen += $latest.Length
    }
    $pad = $w - $leftLen - $right.Length
    if ($right -and $pad -gt 0) { $title += , @(((' ' * $pad) + $right), $null) }
    # Clicking view: or sort: cycles it, as V and S do.
    $layout.TitleY = $lines.Count
    $x = 0
    foreach ($t in $title) {
        $text = [string]$t[0]
        $key = $null
        if ($text -match '^  \|  view: ') { $key = ConvertTo-MMTuiKeyInfo 'V' }
        elseif ($text -match '^  \|  sort: ') { $key = ConvertTo-MMTuiKeyInfo 'S' }
        if ($key) { $layout.Title.Add(@{ Start = $x + 5; End = $x + $text.Length; Key = $key }) }
        $x += $text.Length
    }
    $lines.Add((Format-MMTuiLine $title $w 'Title'))

    if ($State.Mode -eq 'details' -or ($State.Mode -eq 'confirm' -and $State.Confirm.ReturnMode -eq 'details')) {
        Add-MMTuiDetailLines -State $State -Lines $lines -Width $w -ListHeight $listHeight
    }
    else {
        Add-MMTuiListLines -State $State -Lines $lines -Width $w -ListHeight $listHeight
    }
    if ($paneHeight) {
        $layout.LogTop = $lines.Count; $layout.LogRows = $paneHeight
        Add-MMTuiLogLines -State $State -Lines $lines -Width $w -PaneHeight $paneHeight
    }

    # --- Status / prompt line
    $layout.StatusY = $lines.Count
    switch ($State.Mode) {
        'filter' { $lines.Add((Format-MMTuiLine @(@(' Filter: ', 'Key'), @("$($State.Filter)_", 'Bold'), @('   Enter to apply, Esc to clear', 'Dim')) $w)) }
        'confirm' {
            $choices = 'y'
            if ($State.Confirm.ContainsKey('Choices') -and $State.Confirm.Choices) { $choices = $State.Confirm.Choices }
            $answers = @($choices.ToCharArray() | ForEach-Object { [string]$_ }) + 'N'
            $hint = "[$($answers -join '/')]"
            $prompt = " $($State.Confirm.Prompt) "
            $lines.Add((Format-MMTuiLine @(@($prompt, 'Yellow'), @($hint, 'Key')) $w))
            # Each answer in [y/N] can be clicked.
            for ($i = 0; $i -lt $answers.Count; $i++) {
                $x = $prompt.Length + 1 + 2 * $i
                $layout.Choices.Add(@{ Start = $x; End = $x + 1; Key = (ConvertTo-MMTuiKeyInfo $answers[$i]) })
            }
        }
        default { $lines.Add((Format-MMTuiLine @(, @(" $($State.Message)", $State.MessageStyle)) $w)) }
    }

    # --- Help bar
    if ($State.Mode -eq 'details' -or ($State.Mode -eq 'confirm' -and $State.Confirm.ReturnMode -eq 'details')) {
        # X acts on the versions selected (of any module), if there are some.
        $uninstall = 'uninstall'; $move = 'move scope'
        if ($State.DSelected.Count) { $uninstall = 'uninstall selected'; $move = 'move selected' }
        $keys = @('Up/Dn', 'move', 'Space', 'select', 'X', $uninstall, 'M', $move, 'O', 'remove old', 'U', 'update')
        # P opens the project page (or the gallery page), when the module has one.
        $links = Get-MMTuiDetailLink $State
        if ($links.Project) { $keys += 'P', 'project page' } elseif ($links.Gallery) { $keys += 'P', 'gallery page' }
        $keys += 'L', 'output', 'Esc', 'back'
    }
    else {
        # U and O act on the selected modules, and X on selected modules and versions, if there are some.
        $update = 'update'; $removeOld = 'remove old'; $uninstall = 'uninstall'; $move = 'move scope'
        if ($selCount) { $update = 'update selected'; $removeOld = 'remove old from selected' }
        if ($selCount -or $State.DSelected.Count) { $uninstall = 'uninstall selected'; $move = 'move selected' }
        $selectAll = if ($State.Views[$State.View] -eq 'Multiple versions') { 'select old' } else { 'select updates' }
        $keys = @('Up/Dn', 'move', 'Space', 'select', 'A', $selectAll, 'Enter', 'details', 'U', $update, 'X', $uninstall,
            'M', $move, 'O', $removeOld, 'L', 'output', '/', 'filter', 'V', 'view', 'S', 'sort', 'G', 'group', 'R', 'refresh', 'Q', 'quit')
    }
    $help = @()
    $x = 0
    for ($i = 0; $i -lt $keys.Count; $i += 2) {
        $keyText = " $($keys[$i])"; $label = " $($keys[$i + 1]) "
        $help += , @($keyText, 'Key')
        $help += , @($label, $null)
        # Clicking a key (or what it does) presses it.
        $key = ConvertTo-MMTuiKeyInfo $keys[$i]
        if ($key) { $layout.Help.Add(@{ Start = $x; End = $x + $keyText.Length + $label.Length; Key = $key }) }
        $x += $keyText.Length + $label.Length
    }
    $layout.HelpY = $lines.Count
    $lines.Add((Format-MMTuiLine $help $w 'HelpBar'))

    $lines -join "`r`n"
}
