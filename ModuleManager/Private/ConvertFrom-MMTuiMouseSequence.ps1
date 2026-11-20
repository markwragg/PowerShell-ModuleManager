function ConvertFrom-MMTuiMouseSequence {
    <#
    .SYNOPSIS
        Converts a terminal's SGR mouse report into a terminal UI mouse event, or returns $null if the
        text isn't one.

    .DESCRIPTION
        Terminals report the mouse (once turned on with ESC [ ? 1000 h and ESC [ ? 1006 h) as
        ESC [ < b ; x ; y M for a button press and the same ending in m for a release, with x and y
        counted from 1. $Text is the report without the leading ESC.

        A terminal that doesn't have the SGR format (such as GNU screen before 5.0) uses the older
        one, ESC [ M followed by three characters: 32 plus the button, and 33 plus the column and
        row. A release is button 3.

        The event has Button (Left, Right, Middle, WheelUp, WheelDown, or None for a release, a
        move or anything else the terminal UI ignores), and X and Y: the column and row, counted
        from 0.
    #>
    param([string]$Text)

    $button = 'None'
    if ($Text.Length -eq 5 -and $Text.StartsWith('[M', [StringComparison]::Ordinal)) {
        $b = [int]$Text[2] - 32
        $x = [int]$Text[3] - 33
        $y = [int]$Text[4] - 33
        $press = ($b -band 3) -ne 3
        if ($b -lt 0 -or $x -lt 0 -or $y -lt 0 -or $x -gt 222 -or $y -gt 222) { $press = $false; $x = [Math]::Max(0, $x); $y = [Math]::Max(0, $y) }
    }
    elseif ($Text -match '^\[<(\d+);(\d+);(\d+)([Mm])$') {
        $b = [int]$Matches[1]
        $x = [int]$Matches[2] - 1
        $y = [int]$Matches[3] - 1
        $press = $Matches[4] -ceq 'M'
    }
    else { return $null }

    # 4, 8 and 16 are Shift, Alt and Ctrl, and 32 is a move with the button held.
    if ($press -and -not ($b -band 32)) {
        if ($b -band 64) { $button = @('WheelUp', 'WheelDown', 'None', 'None')[$b -band 3] }
        else { $button = @('Left', 'Middle', 'Right', 'None')[$b -band 3] }
    }
    [pscustomobject]@{ PSTypeName = 'ModuleManager.TuiMouse'; Button = $button; X = $x; Y = $y }
}
