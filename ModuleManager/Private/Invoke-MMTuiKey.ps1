function Invoke-MMTuiKey {
    <#
    .SYNOPSIS
        Handles a key press in the terminal UI.
    #>
    param([hashtable]$State, [ConsoleKeyInfo]$Key)

    $k = $Key.Key
    $c = [char]::ToLowerInvariant($Key.KeyChar)
    $ctrlC = ($k -eq [ConsoleKey]::C -and ($Key.Modifiers -band [ConsoleModifiers]::Control))

    switch ($State.Mode) {
        'filter' {
            if ($ctrlC -or $k -eq [ConsoleKey]::Escape) { $State.Filter = ''; $State.Mode = 'list' }
            elseif ($k -eq [ConsoleKey]::Enter) { $State.Mode = 'list' }
            elseif ($k -eq [ConsoleKey]::Backspace) {
                if ($State.Filter.Length) { $State.Filter = $State.Filter.Substring(0, $State.Filter.Length - 1) }
            }
            elseif (-not [char]::IsControl($Key.KeyChar)) { $State.Filter += $Key.KeyChar }
            $State.CurrentName = $null
            $State.Cursor = 0
            return
        }
        'confirm' {
            $confirm = $State.Confirm
            $State.Mode = $confirm.ReturnMode
            $State.Confirm = $null
            $choices = 'y'
            if ($confirm.ContainsKey('Choices') -and $confirm.Choices) { $choices = $confirm.Choices }
            if ($c -ne 'n' -and $choices.Contains([string]$c)) { & $confirm.Action $State $confirm.Data ([string]$c) }
            else { Set-MMTuiMessage $State 'Cancelled.' }
            return
        }
    }

    # Output pane keys work in the list and the details view.
    switch ($c) {
        'l' {
            if (-not $State.LogOpen -and -not $State.Log.Count) { Set-MMTuiMessage $State 'No output yet: it appears here when you update, move or uninstall.'; return }
            $State.LogOpen = -not $State.LogOpen
            $State.LogScroll = 0
            return
        }
        '[' { if ($State.LogOpen) { $State.LogScroll += [Math]::Max(1, $State.LogBody - 1) }; return }
        ']' { if ($State.LogOpen) { $State.LogScroll = [Math]::Max(0, $State.LogScroll - [Math]::Max(1, $State.LogBody - 1)) }; return }
    }
    if ($State.Mode -eq 'details') { Invoke-MMTuiDetailKey -State $State -Key $Key; return }

    # --- list mode
    $page = [Math]::Max(1, $State.ListHeight - 1)
    if ($ctrlC -or $c -eq 'q') {
        if (-not $State.Task) { $State.Quit = $true; return }
        if (-not $ctrlC) { Set-MMTuiMessage $State "Wait for '$($State.Task.Title)' to finish before quitting (or Ctrl+C to stop it)." 'Yellow'; return }
        Request-MMTuiConfirm $State "Stop '$($State.Task.Title)' and quit? Stopping part-way can leave a module half installed or removed." -Action {
            param($State)
            Stop-MMTuiTask $State -Closing
            $State.Quit = $true
        }
        return
    }
    switch ($k) {
        ([ConsoleKey]::UpArrow) { Set-MMTuiCursor $State ($State.Cursor - 1); return }
        ([ConsoleKey]::DownArrow) { Set-MMTuiCursor $State ($State.Cursor + 1); return }
        ([ConsoleKey]::PageUp) { Set-MMTuiCursor $State ($State.Cursor - $page); return }
        ([ConsoleKey]::PageDown) { Set-MMTuiCursor $State ($State.Cursor + $page); return }
        ([ConsoleKey]::Home) { Set-MMTuiCursor $State 0; return }
        ([ConsoleKey]::End) { Set-MMTuiCursor $State ($State.Visible.Count - 1); return }
        ([ConsoleKey]::Spacebar) {
            if ($State.Visible.Count) {
                $row = $State.Visible[$State.Cursor]
                $value = -not $row.Selected
                foreach ($r in (Get-MMTuiFamily $State $row)) { $r.Selected = $value }
                Set-MMTuiCursor $State ($State.Cursor + 1)
            }
            return
        }
        ([ConsoleKey]::LeftArrow) {
            # Collapse the family the cursor is in (moving up to its parent if on a member).
            if (-not $State.Group -or -not $State.Visible.Count) { return }
            $row = $State.Visible[$State.Cursor]
            $parent = $null
            if ($row.Children.Count) { $parent = $row }
            elseif ($row.Indent -and $row.Parent) { $parent = $State.Rows | Where-Object Name -EQ $row.Parent | Select-Object -First 1 }
            if ($parent) {
                $null = $State.Expanded.Remove($parent.Name.ToLowerInvariant())
                $State.CurrentName = $parent.Name
            }
            return
        }
        ([ConsoleKey]::Escape) {
            if ($State.LogOpen -and -not $State.Task) { $State.LogOpen = $false }
            elseif (@($State.Rows | Where-Object Selected).Count -or $State.DSelected.Count) {
                foreach ($r in $State.Rows) { $r.Selected = $false }
                $State.DSelected = @{}
            }
            elseif ($State.Filter) { $State.Filter = '' }
            return
        }
        { $_ -in [ConsoleKey]::Enter, [ConsoleKey]::RightArrow } {
            if ($State.Visible.Count) {
                $row = $State.Visible[$State.Cursor]
                $familyKey = $row.Name.ToLowerInvariant()
                if ($k -eq [ConsoleKey]::RightArrow -and $State.Group -and $row.Children.Count -and -not $row.Open -and -not $State.Expanded.ContainsKey($familyKey)) {
                    $State.Expanded[$familyKey] = $true
                    return
                }
                $State.Detail = $State.Visible[$State.Cursor]
                $State.DCursor = 0; $State.DTop = 0
                $State.Mode = 'details'
            }
            return
        }
        ([ConsoleKey]::Delete) { Request-MMTuiUninstall $State; return }
    }

    switch ($c) {
        'k' { Set-MMTuiCursor $State ($State.Cursor - 1) }
        'j' { Set-MMTuiCursor $State ($State.Cursor + 1) }
        '/' { $State.Mode = 'filter' }
        'v' { $State.View = ($State.View + 1) % $State.Views.Count; $State.Top = 0 }
        's' { $State.Sort = ($State.Sort + 1) % $State.Sorts.Count }
        'c' {
            # The next scope that has modules (System only does with -IncludeSystem), then All.
            $present = @($State.Rows | ForEach-Object { $_.Info.Scope -split ', ' })
            $n = $State.Scopes.Count
            $next = 0
            for ($i = 1; $i -lt $n; $i++) {
                $candidate = ($State.InScope + $i) % $n
                if ($candidate -eq 0 -or $State.Scopes[$candidate] -in $present) { $next = $candidate; break }
            }
            $State.InScope = $next
            $State.Top = 0
        }
        'g' {
            $State.Group = -not $State.Group
            $State.Top = 0
            if ($State.Group) { Set-MMTuiMessage $State 'Grouping module families (Right to expand, Left to collapse).' }
            else { Set-MMTuiMessage $State 'Showing every module separately.' }
        }
        'a' {
            # Includes members of collapsed families that are in view.
            $inView = [ordered]@{}
            foreach ($r in $State.Visible) { foreach ($m in (Get-MMTuiFamily $State $r)) { $inView[$m.Name] = $m } }
            # In the Multiple versions view it selects the modules with old versions, for O;
            # in the other views, the modules with updates, for U.
            if ($State.Views[$State.View] -eq 'Multiple versions') {
                $targets = @($inView.Values | Where-Object { $_.Info.VersionCount -gt 1 })
                if (-not $targets) { Set-MMTuiMessage $State 'No modules with old versions in this view.'; return }
                $selected = "Selected $($targets.Count) module(s) with old versions. Press O to remove them."
            }
            else {
                $targets = @($inView.Values | Where-Object Status -EQ 'UpdateAvailable')
                if (-not $targets) {
                    if ($State.Job) { Set-MMTuiMessage $State 'Still checking repositories...' 'Yellow' }
                    else { Set-MMTuiMessage $State 'No updates available in this view.' }
                    return
                }
                $selected = "Selected $($targets.Count) module(s) with updates. Press U to update."
            }
            if (@($targets | Where-Object { -not $_.Selected }).Count) {
                foreach ($r in $targets) { $r.Selected = $true }
                Set-MMTuiMessage $State $selected
            }
            else { foreach ($r in $State.Rows) { $r.Selected = $false } }
        }
        'r' {
            # A repository check still running is replaced, but an action has to finish first.
            if (Test-MMTuiBusy $State -AllowLookup) { return }
            Stop-MMTuiLookup $State
            try { Update-MMTuiRows $State }
            catch { Set-MMTuiMessage $State "Could not rescan: $($_.Exception.Message)" 'Red'; return }
            Start-MMTuiLookup $State -Refresh
            Set-MMTuiMessage $State 'Rescanned modules; checking repositories...'
        }
        'u' { Request-MMTuiUpdate $State (Get-MMTuiTarget $State) }
        'x' { Request-MMTuiUninstall $State }
        'm' { Request-MMTuiMove $State }
        'o' { Request-MMTuiRemoveOld $State (Get-MMTuiTarget $State) }
    }
}
