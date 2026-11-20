function Add-MMTuiLogLines {
    <#
    .SYNOPSIS
        Draws the output pane that shows a terminal UI operation's progress and output.

    .DESCRIPTION
        Draws the output pane: a header line, a progress bar while the operation reports
        progress, then the end of the output, wrapped to the screen width. $State.LogScroll
        scrolls back through earlier output.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The noun describes a set of lines/rows (or metadata, which has no singular form).')]
    param([hashtable]$State, $Lines, [int]$Width, [int]$PaneHeight)

    $task = $State.Task
    if ($task) {
        $spin = '|/-\'[$State.Spinner % 4]
        $status = "$spin running $(Format-MMElapsed ([datetime]::UtcNow - $task.Started))"
        $title = $task.Title
    }
    else {
        $status = 'finished'
        $title = ''
        if ($State.Log.Count) { $title = [string]$State.Log[0].Text }
    }
    $keys = ' [ ] scroll  L hide '
    if (-not $task) { $keys = ' [ ] scroll  L/Esc hide ' }
    $left = " Output: $title  ($status)"
    $pad = [Math]::Max(1, $Width - $left.Length - $keys.Length)
    # For the mouse (see Invoke-MMTuiMouse): [ and ] scroll, and L hide (or L/Esc hide) hides the pane.
    $at = $left.Length + $pad
    $State.Layout.LogKeys = @(
        @{ Start = $at + 1; End = $at + 2; Key = (ConvertTo-MMTuiKeyInfo '[') }
        @{ Start = $at + 3; End = $at + 4; Key = (ConvertTo-MMTuiKeyInfo ']') }
        @{ Start = $at + $keys.IndexOf('L'); End = $at + $keys.TrimEnd().Length; Key = (ConvertTo-MMTuiKeyInfo 'L') }
    )
    $Lines.Add((Format-MMTuiLine @(@($left, 'Bold'), @(((' ' * $pad) + $keys), $null)) $Width 'HelpBar'))
    $body = $PaneHeight - 1

    if ($task -and $State.Progress -and $body -gt 1) {
        $p = $State.Progress
        $barWidth = [Math]::Max(10, [Math]::Min(40, [int]($Width / 4)))
        $percent = [Math]::Max(0, [Math]::Min(100, [int]$p.Percent))
        $filled = [int][Math]::Round($barWidth * $percent / 100)
        $bar = ('#' * $filled) + ('-' * ($barWidth - $filled))
        $Lines.Add((Format-MMTuiLine @(@(" [$bar] ", 'Cyan'), @(("{0,3}%  " -f $percent), 'Bold'), @([string]$p.Status, $null)) $Width))
        $body--
    }

    # Wrap every entry (skipping the title, shown in the header) to the pane width.
    $wrapped = [System.Collections.Generic.List[object]]::new()
    $textWidth = [Math]::Max(10, $Width - 1)
    for ($i = 1; $i -lt $State.Log.Count; $i++) {
        $entry = $State.Log[$i]
        foreach ($line in ([string]$entry.Text -split "\r?\n")) {
            $line = $line.TrimEnd()
            do {
                $chunk = $line
                if ($chunk.Length -gt $textWidth) { $chunk = $line.Substring(0, $textWidth) }
                $wrapped.Add(@(" $chunk", $entry.Style))
                $line = $line.Substring($chunk.Length)
            } while ($line.Length)
        }
    }

    $State.LogBody = $body
    $maxScroll = [Math]::Max(0, $wrapped.Count - $body)
    $State.LogScroll = [Math]::Max(0, [Math]::Min($State.LogScroll, $maxScroll))
    $start = [Math]::Max(0, $wrapped.Count - $body - $State.LogScroll)
    for ($i = 0; $i -lt $body; $i++) {
        $index = $start + $i
        if ($index -lt $wrapped.Count -and ($index -lt $wrapped.Count - $State.LogScroll)) {
            $Lines.Add((Format-MMTuiLine @(, $wrapped[$index]) $Width))
        }
        elseif ($i -eq 0 -and $wrapped.Count -eq 0) { $Lines.Add((Format-MMTuiLine @(, @(' Starting...', 'Dim')) $Width)) }
        else { $Lines.Add((' ' * $Width)) }
    }
}
