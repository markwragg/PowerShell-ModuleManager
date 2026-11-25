function Invoke-MMTuiMouse {
    <#
    .SYNOPSIS
        Handles a mouse click or wheel turn in the terminal UI.

    .DESCRIPTION
        Works out what was clicked from where the last frame drew things ($State.Layout, set by
        Get-MMTuiFrame and the functions it calls):

          A row                      Moves the cursor to it. Double-click a module for its details.
          Right-click                Hides the output pane, when it's over the pane or in the list.
                                     Otherwise goes back from the details to the list, as Esc does.
          [, ] or L hide (output)    Scrolls or hides the output pane, as those keys do.
          The [ ] box of a row       Selects or deselects it, as Space does (without moving down).
          A family's expand glyph    Expands or collapses the family.
          A column header            Sorts the list by that column.
          view:, sort: or scope:     Cycles the view, sort or scope, as V, S and C do (in the list).
          (title)
          A key in the help bar      Presses that key.
          A web page (details)       Opens it in the browser, as P does for the project page.
          An answer in [y/N]         Gives that answer. While a confirmation is shown, other clicks
                                     are ignored, so a stray click can't answer it.
          The wheel                  Scrolls the output pane when the pointer is over it, otherwise
                                     the list or details, keeping the cursor on screen.

        Clicking while typing a filter applies it first, as Enter does. Other buttons, and clicks
        elsewhere, are ignored. $Mouse is an event from Read-MMTuiInput.
    #>
    param([hashtable]$State, [object]$Mouse)

    $layout = $State.Layout
    if (-not $layout -or -not $layout.Count) { return }
    $x = $Mouse.X; $y = $Mouse.Y
    $click = $Mouse.Button -eq 'Left'
    $rightClick = $Mouse.Button -eq 'Right'
    $wheel = 0
    if ($Mouse.Button -eq 'WheelUp') { $wheel = -3 }
    elseif ($Mouse.Button -eq 'WheelDown') { $wheel = 3 }
    if (-not $click -and -not $rightClick -and -not $wheel) { return }

    if ($State.Mode -eq 'confirm') {
        if ($click -and $y -eq $layout.StatusY) {
            $hit = @($layout.Choices | Where-Object { $x -ge $_.Start -and $x -lt $_.End }) | Select-Object -First 1
            if ($hit) { Invoke-MMTuiKey -State $State -Key $hit.Key }
        }
        return
    }
    $overPane = $layout.LogRows -and $y -ge $layout.LogTop -and $y -lt $layout.LogTop + $layout.LogRows
    # Right-click hides the output pane: when it's over the pane, or in the list (where it does nothing
    # else). Otherwise, in the details view, it goes back to the list. It isn't Esc in the list, as Esc
    # can also clear the selection or the filter, which a stray right-click shouldn't do.
    if ($rightClick) {
        if ($State.LogOpen -and ($overPane -or $State.Mode -ne 'details')) { $State.LogOpen = $false; $State.LogScroll = 0 }
        elseif ($State.Mode -eq 'details') { Invoke-MMTuiKey -State $State -Key (ConvertTo-MMTuiKeyInfo 'Esc') }
        return
    }
    if ($State.Mode -eq 'filter') { Invoke-MMTuiKey -State $State -Key (ConvertTo-MMTuiKeyInfo 'Enter') }

    if ($click -and $overPane) {
        # Only the keys in its header line do anything.
        if ($y -eq $layout.LogTop) {
            $hit = @($layout.LogKeys | Where-Object { $x -ge $_.Start -and $x -lt $_.End }) | Select-Object -First 1
            if ($hit) { Invoke-MMTuiKey -State $State -Key $hit.Key }
        }
        return
    }
    if ($click -and $y -eq $layout.TitleY) {
        $hit = @($layout.Title | Where-Object { $x -ge $_.Start -and $x -lt $_.End }) | Select-Object -First 1
        if ($hit -and $State.Mode -eq 'list') { Invoke-MMTuiKey -State $State -Key $hit.Key }
        return
    }
    if ($click -and $y -eq $layout.HelpY) {
        $hit = @($layout.Help | Where-Object { $x -ge $_.Start -and $x -lt $_.End }) | Select-Object -First 1
        if ($hit) { Invoke-MMTuiKey -State $State -Key $hit.Key }
        return
    }

    $details = $State.Mode -eq 'details'
    if ($wheel) {
        if ($layout.LogRows -and $y -ge $layout.LogTop -and $y -lt $layout.LogTop + $layout.LogRows) {
            # Up goes back through earlier output (the frame limits how far).
            $State.LogScroll = [Math]::Max(0, $State.LogScroll - $wheel)
        }
        elseif ($details) {
            $count = @($State.Detail.Info.Installations).Count
            $rows = [Math]::Max(1, $layout.DetailRows)
            $State.DTop = [Math]::Max(0, [Math]::Min($State.DTop + $wheel, $count - $rows))
            $State.DCursor = [Math]::Max($State.DTop, [Math]::Min($State.DCursor, [Math]::Min($count - 1, $State.DTop + $rows - 1)))
        }
        else {
            $rows = [Math]::Max(1, $layout.ListRows)
            $State.Top = [Math]::Max(0, [Math]::Min($State.Top + $wheel, $State.Visible.Count - $rows))
            Set-MMTuiCursor $State ([Math]::Max($State.Top, [Math]::Min($State.Cursor, $State.Top + $rows - 1)))
        }
        return
    }

    $space = ConvertTo-MMTuiKeyInfo 'Space'
    if ($details -and $click) {
        $hit = @($layout.Links | Where-Object { $y -eq $_.Y -and $x -ge $_.Start -and $x -lt $_.End }) | Select-Object -First 1
        if ($hit) { Request-MMTuiWebPage $State $hit.Uri; return }
    }
    if ($details) {
        if ($y -lt $layout.DetailTop -or $y -ge $layout.DetailTop + $layout.DetailRows) { return }
        $index = $State.DTop + $y - $layout.DetailTop
        if ($index -ge @($State.Detail.Info.Installations).Count) { return }
        $State.DCursor = $index
        if ($x -lt $layout.CheckWidth) {
            Invoke-MMTuiKey -State $State -Key $space
            $State.DCursor = $index
        }
        return
    }

    # --- list
    if ($y -eq $layout.HeaderY) {
        $hit = @($layout.SortColumns | Where-Object { $x -ge $_.Start -and $x -lt $_.End }) | Select-Object -First 1
        if ($hit) { $State.Sort = [array]::IndexOf($State.Sorts, $hit.Sort) }
        return
    }
    if ($y -lt $layout.ListTop -or $y -ge $layout.ListTop + $layout.ListRows) { return }
    $index = $State.Top + $y - $layout.ListTop
    if ($index -ge $State.Visible.Count) { return }
    $row = $State.Visible[$index]
    Set-MMTuiCursor $State $index

    if ($x -lt $layout.CheckWidth) {
        Invoke-MMTuiKey -State $State -Key $space
        Set-MMTuiCursor $State $index
        $State.LastClick = $null
        return
    }
    # The family glyph, just after the [ ] box.
    if ($State.Group -and $row.Children.Count -and -not $row.Indent -and $x -lt $layout.CheckWidth + 2) {
        $familyKey = $row.Name.ToLowerInvariant()
        if ($State.Expanded.ContainsKey($familyKey)) { $State.Expanded.Remove($familyKey) }
        elseif (-not $row.Open) { $State.Expanded[$familyKey] = $true }
        $State.LastClick = $null
        return
    }

    $now = [datetime]::UtcNow
    $last = $State.LastClick
    if ($last -and $last.Name -eq $row.Key -and ($now - $last.Time).TotalMilliseconds -le 500) {
        $State.LastClick = $null
        Invoke-MMTuiKey -State $State -Key (ConvertTo-MMTuiKeyInfo 'Enter')
        return
    }
    $State.LastClick = @{ Name = $row.Key; Time = $now }
}
