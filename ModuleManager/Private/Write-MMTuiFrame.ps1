function Write-MMTuiFrame {
    <#
    .SYNOPSIS
        Draws the terminal UI screen to the console.

    .DESCRIPTION
        Only the lines that changed since the last frame are written, so a redraw that changes
        little (the spinner, or a few repository results arriving) doesn't repaint the whole
        screen, which flickers in some consoles. The whole screen is drawn when the window size
        changes, or when $State.Screen is $null.

        The frame is wrapped in a synchronized update (DEC mode 2026), so terminals that support
        it show it all at once; others ignore it.
    #>
    param([hashtable]$State)
    $E = [char]27
    $size = Get-MMConsoleSize
    $w = $size.Width
    $h = $size.Height
    $full = $w -ne $State.Width -or $h -ne $State.Height -or $null -eq $State.Screen
    $lines = (Get-MMTuiFrame -State $State -Width $w -Height $h) -split "`r`n"
    $previous = $State.Screen
    $State.Screen = $lines

    $sb = [System.Text.StringBuilder]::new()
    if ($full) {
        [void]$sb.Append("$E[?25l$E[2J$E[H").Append($lines -join "`r`n")
    }
    else {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($i -lt $previous.Count -and $previous[$i] -ceq $lines[$i]) { continue }
            [void]$sb.Append("$E[$($i + 1);1H").Append($lines[$i])
        }
        if (-not $sb.Length) { return }
        [void]$sb.Insert(0, "$E[?25l")
    }
    Write-MMConsole "$E[?2026h$($sb.ToString())$E[?2026l"
}
