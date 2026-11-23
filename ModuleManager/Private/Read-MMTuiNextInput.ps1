function Read-MMTuiNextInput {
    <#
    .SYNOPSIS
        Returns the next key press or mouse event without echoing it, or $null if there's no input
        waiting. Read-MMTuiInput calls this, and screens what it returns for pasted text.

    .DESCRIPTION
        Key presses are returned as [ConsoleKeyInfo], mouse events as the objects
        ConvertFrom-MMTuiMouseSequence describes. Mouse events only arrive once Enable-MMTuiMouse has
        turned the mouse on ($State.Mouse):

          Windows  They're read from the console's input queue (see Enable-MMTuiMouse), as
                   [Console]::ReadKey and KeyAvailable discard them. KeyAvailable discards every
                   event before the next key press, so the helper also says when a key is waiting.
          VT       The terminal reports them as escape sequences among the keys (ESC [ < b ; x ; y M,
                   or ESC [ M and three characters from a terminal without the SGR format),
                   which .NET returns as an Escape or Alt+[ key followed by ordinary characters. Those
                   are put back together here. Anything read while looking for a sequence that turns
                   out not to be one is returned afterwards, in order, so no key press is lost.
    #>
    param([hashtable]$State)

    if ($State.PendingKeys.Count) { return $State.PendingKeys.Dequeue() }

    if ($State.Mouse -eq 'Windows') {
        $console = 'ModuleManager.ConsoleMouse' -as [type]
        while ($true) {
            $x = 0; $y = 0; $button = 0
            $kind = $console::Next([ref]$x, [ref]$y, [ref]$button)
            if ($kind -eq 2) {
                $name = @('None', 'Left', 'Right', 'Middle', 'WheelUp', 'WheelDown')[$button]
                return [pscustomobject]@{ PSTypeName = 'ModuleManager.TuiMouse'; Button = $name; X = $x; Y = $y }
            }
            # A key press, which ReadKey returns without waiting.
            if ($kind -eq 1) { return [Console]::ReadKey($true) }
            # Nothing waiting (0), otherwise an event that was read and ignored (3).
            if ($kind -eq 0) { break }
        }
        # A key ReadKey still has from before (a repeated key comes as one event, with a count). With
        # nothing else waiting, KeyAvailable has nothing to discard.
    }

    if (-not [Console]::KeyAvailable) { return $null }
    $key = [Console]::ReadKey($true)

    $altBracket = $key.KeyChar -eq '[' -and ($key.Modifiers -band [ConsoleModifiers]::Alt)
    if ($State.Mouse -eq 'VT' -and ($key.KeyChar -eq [char]27 -or $altBracket) -and [Console]::KeyAvailable) {
        $text = ''
        if ($altBracket) { $text = '[' }
        $read = [System.Collections.Generic.List[ConsoleKeyInfo]]::new()
        while ($read.Count -lt 32 -and [Console]::KeyAvailable) {
            $next = [Console]::ReadKey($true)
            $read.Add($next)
            $text += $next.KeyChar
            if ($next.KeyChar -notmatch '[\[<0-9;]') { break }
        }
        # A terminal without the SGR format (such as GNU screen before 5.0) sends ESC [ M and three
        # characters: the button, column and row, which could be anything (u, x, y...). They're
        # read here, so they can't be taken as keys.
        if ($text -ceq '[M') {
            while ($text.Length -lt 5 -and [Console]::KeyAvailable) {
                $next = [Console]::ReadKey($true)
                $read.Add($next)
                $text += $next.KeyChar
            }
        }
        $mouse = ConvertFrom-MMTuiMouseSequence $text
        if ($mouse) { return $mouse }
        foreach ($k in $read) { $State.PendingKeys.Enqueue($k) }
    }
    $key
}
