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

    $lines = [System.Collections.Generic.List[string]]::new()

    # --- Title bar
    $total = $State.Rows.Count
    $updates = @($State.Rows | Where-Object Status -EQ 'UpdateAvailable').Count
    $selCount = @($State.Rows | Where-Object Selected).Count
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
    # The share of modules on their latest version, of those the repository check found (newer
    # than the repository counts as latest). Shown once the check is done, and only if it fits.
    $latest = ''
    $found = @($State.Rows | Where-Object { $_.Status -in 'UpToDate', 'LocalNewer', 'UpdateAvailable' }).Count
    if ($found -and -not $State.Job) { $latest = "  |  $([Math]::Floor(100 * ($found - $updates) / $found))% latest" }

    $title = @(
        , @(' ModuleManager ', 'TitleBold')
        , @(" $total modules  |  $updates updates", $null)
        , @("  |  view: $($State.Views[$State.View])  |  sort: $($State.Sorts[$State.Sort])", $null)
    )
    if ($State.Remote) { $title = @(, $title[0]) + @(, @("on $($State.Remote.Name) ", 'TitleBold')) + $title[1..2] }
    $selected = @()
    if ($selCount) { $selected += "$selCount module(s)" }
    if ($State.DSelected.Count) { $selected += "$($State.DSelected.Count) version(s)" }
    if ($selected) { $title += , @("  |  $($selected -join ', ') selected", $null) }
    if ($State.Filter) { $title += , @("  |  filter: $($State.Filter)", $null) }
    $leftLen = 0; foreach ($t in $title) { $leftLen += ([string]$t[0]).Length }
    if ($latest -and $leftLen + $latest.Length + $right.Length -le $w) {
        $at = if ($State.Remote) { 3 } else { 2 }
        $title = $title[0..($at - 1)] + @(, @($latest, $null)) + $title[$at..($title.Count - 1)]
        $leftLen += $latest.Length
    }
    $pad = $w - $leftLen - $right.Length
    if ($right -and $pad -gt 0) { $title += , @(((' ' * $pad) + $right), $null) }
    $lines.Add((Format-MMTuiLine $title $w 'Title'))

    if ($State.Mode -eq 'details' -or ($State.Mode -eq 'confirm' -and $State.Confirm.ReturnMode -eq 'details')) {
        Add-MMTuiDetailLines -State $State -Lines $lines -Width $w -ListHeight $listHeight
    }
    else {
        Add-MMTuiListLines -State $State -Lines $lines -Width $w -ListHeight $listHeight
    }
    if ($paneHeight) { Add-MMTuiLogLines -State $State -Lines $lines -Width $w -PaneHeight $paneHeight }

    # --- Status / prompt line
    switch ($State.Mode) {
        'filter' { $lines.Add((Format-MMTuiLine @(@(' Filter: ', 'Key'), @("$($State.Filter)_", 'Bold'), @('   Enter to apply, Esc to clear', 'Dim')) $w)) }
        'confirm' {
            $choices = 'y'
            if ($State.Confirm.ContainsKey('Choices') -and $State.Confirm.Choices) { $choices = $State.Confirm.Choices }
            $hint = "[$(($choices.ToCharArray() | ForEach-Object { [string]$_ }) -join '/')/N]"
            $lines.Add((Format-MMTuiLine @(@(" $($State.Confirm.Prompt) ", 'Yellow'), @($hint, 'Key')) $w))
        }
        default { $lines.Add((Format-MMTuiLine @(, @(" $($State.Message)", $State.MessageStyle)) $w)) }
    }

    # --- Help bar
    if ($State.Mode -eq 'details' -or ($State.Mode -eq 'confirm' -and $State.Confirm.ReturnMode -eq 'details')) {
        # X acts on the versions selected (of any module), if there are some.
        $uninstall = 'uninstall'; $move = 'move scope'
        if ($State.DSelected.Count) { $uninstall = 'uninstall selected'; $move = 'move selected' }
        $keys = @('Up/Dn', 'move', 'Space', 'select', 'X', $uninstall, 'M', $move, 'O', 'remove old', 'U', 'update', 'L', 'output', 'Esc', 'back')
    }
    else {
        # U and O act on the selected modules, and X on selected modules and versions, if there are some.
        $update = 'update'; $removeOld = 'remove old'; $uninstall = 'uninstall'; $move = 'move scope'
        if ($selCount) { $update = 'update selected'; $removeOld = 'remove old from selected' }
        if ($selCount -or $State.DSelected.Count) { $uninstall = 'uninstall selected'; $move = 'move selected' }
        $keys = @('Up/Dn', 'move', 'Space', 'select', 'A', 'select updates', 'Enter', 'details', 'U', $update, 'X', $uninstall,
            'M', $move, 'O', $removeOld, 'L', 'output', '/', 'filter', 'V', 'view', 'S', 'sort', 'G', 'group', 'R', 'refresh', 'Q', 'quit')
    }
    $help = @()
    for ($i = 0; $i -lt $keys.Count; $i += 2) {
        $help += , @(" $($keys[$i])", 'Key')
        $help += , @(" $($keys[$i + 1]) ", $null)
    }
    $lines.Add((Format-MMTuiLine $help $w 'HelpBar'))

    $lines -join "`r`n"
}
