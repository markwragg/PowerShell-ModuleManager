function Read-MMTuiInput {
    <#
    .SYNOPSIS
        Returns the next key press or mouse event, or $null if there's no input waiting, ignoring
        pasted text.

    .DESCRIPTION
        Each key is a command, so text pasted into the terminal would run one command per character:
        a clipboard holding "xy" would uninstall the module under the cursor. Terminals paste on
        right-click (VS Code's terminal on Windows does by default, and so does Windows Terminal
        with text selected), so it's easy to do by accident. Pasted text arrives as key presses, but
        all at once, which typing doesn't, so input is read in batches: everything waiting when the
        first event is read (see Read-MMTuiNextInput). A batch is taken as pasted when it has two or
        more different keys and one of them is a character (holding a key down repeats the same
        key, and arrow keys can queue up while the screen redraws), or when it has more than one key
        while a confirmation is showing, so a paste can't answer it.

        Pasted keys are dropped, with a message, and so are keys that follow within a short time, in
        case a long paste arrives in more than one batch. When typing a filter, the pasted
        characters are kept, as filter text, but not Enter, Esc and the like, so the rest of the
        paste can't leave the filter and run as commands. Mouse events are always kept.
    #>
    param([hashtable]$State)

    if ($State.InputQueue.Count) { return $State.InputQueue.Dequeue() }

    $first = Read-MMTuiNextInput -State $State
    if ($null -eq $first) { return $null }
    $batch = [System.Collections.Generic.List[object]]::new()
    $batch.Add($first)
    while ($batch.Count -lt 4096) {
        $next = Read-MMTuiNextInput -State $State
        if ($null -eq $next) { break }
        $batch.Add($next)
    }

    $keys = @($batch | Where-Object { $_ -is [ConsoleKeyInfo] })
    $now = [datetime]::UtcNow
    $pasted = $State.PasteUntil -and $keys.Count -and $now -lt $State.PasteUntil
    if (-not $pasted -and $keys.Count -gt 1) {
        $isChar = { param($k) $k.KeyChar -ne [char]0 -and -not [char]::IsControl($k.KeyChar) }
        $distinct = @($keys | ForEach-Object { "$($_.Key)|$([int]$_.KeyChar)|$($_.Modifiers)" } | Select-Object -Unique)
        $hasChar = @($keys | Where-Object { & $isChar $_ }).Count -gt 0
        $pasted = $State.Mode -eq 'confirm' -or ($hasChar -and $distinct.Count -gt 1)
    }

    if ($pasted) {
        # More of a long paste may follow in the next batch or two; the message counts all of it.
        if (-not ($State.PasteUntil -and $now -lt $State.PasteUntil)) { $State.PastedKeys = 0 }
        $State.PastedKeys += $keys.Count
        $State.PasteUntil = $now.AddMilliseconds(300)
        $kept = @(foreach ($item in $batch) {
                if ($item -isnot [ConsoleKeyInfo]) { $item }
                elseif ($State.Mode -eq 'filter' -and $item.KeyChar -ne [char]0 -and -not [char]::IsControl($item.KeyChar)) { $item }
            })
        if ($State.Mode -ne 'filter') {
            Set-MMTuiMessage $State "Ignored pasted text ($($State.PastedKeys) key(s)): modman takes one key at a time." 'Yellow'
            $State.Redraw = $true
        }
        $batch = [System.Collections.Generic.List[object]]::new()
        foreach ($k in $kept) { $batch.Add($k) }
        if (-not $batch.Count) { return $null }
    }

    for ($i = 1; $i -lt $batch.Count; $i++) { $State.InputQueue.Enqueue($batch[$i]) }
    $batch[0]
}
