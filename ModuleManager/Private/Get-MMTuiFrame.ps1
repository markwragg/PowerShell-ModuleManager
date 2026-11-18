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
    $title = @(
        , @(' ModuleManager ', 'TitleBold')
        , @(" $total modules  |  $updates updates  |  view: $($State.Views[$State.View])  |  sort: $($State.Sorts[$State.Sort])", $null)
    )
    if ($selCount) { $title += , @("  |  $selCount selected", $null) }
    if ($State.Filter) { $title += , @("  |  filter: $($State.Filter)", $null) }
    $leftLen = 0; foreach ($t in $title) { $leftLen += ([string]$t[0]).Length }
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
        'confirm' { $lines.Add((Format-MMTuiLine @(@(" $($State.Confirm.Prompt) ", 'Yellow'), @('[y/N]', 'Key')) $w)) }
        default { $lines.Add((Format-MMTuiLine @(, @(" $($State.Message)", $State.MessageStyle)) $w)) }
    }

    # --- Help bar
    if ($State.Mode -eq 'details' -or ($State.Mode -eq 'confirm' -and $State.Confirm.ReturnMode -eq 'details')) {
        $keys = @('Up/Dn', 'move', 'Space', 'select', 'X', 'uninstall', 'O', 'remove old', 'U', 'update', 'L', 'output', 'Esc', 'back')
    }
    else {
        $keys = @('Up/Dn', 'move', 'Space', 'select', 'A', 'select updates', 'Enter', 'details', 'U', 'update', 'X', 'uninstall',
            'O', 'remove old', 'L', 'output', '/', 'filter', 'V', 'view', 'S', 'sort', 'G', 'group', 'R', 'refresh', 'Q', 'quit')
    }
    $help = @()
    for ($i = 0; $i -lt $keys.Count; $i += 2) {
        $help += , @(" $($keys[$i])", 'Key')
        $help += , @(" $($keys[$i + 1]) ", $null)
    }
    $lines.Add((Format-MMTuiLine $help $w 'HelpBar'))

    $lines -join "`r`n"
}
