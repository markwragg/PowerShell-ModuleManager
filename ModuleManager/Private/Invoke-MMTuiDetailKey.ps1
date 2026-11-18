function Invoke-MMTuiDetailKey {
    <#
    .SYNOPSIS
        Handles a key press in the terminal UI details view.
    #>
    param([hashtable]$State, [ConsoleKeyInfo]$Key)
    $k = $Key.Key
    $c = [char]::ToLowerInvariant($Key.KeyChar)
    $installs = @($State.Detail.Info.Installations)
    $count = $installs.Count

    switch ($k) {
        ([ConsoleKey]::UpArrow) { $State.DCursor = [Math]::Max(0, $State.DCursor - 1); return }
        ([ConsoleKey]::DownArrow) { $State.DCursor = [Math]::Min($count - 1, $State.DCursor + 1); return }
        ([ConsoleKey]::Home) { $State.DCursor = 0; return }
        ([ConsoleKey]::End) { $State.DCursor = $count - 1; return }
        ([ConsoleKey]::Spacebar) {
            $path = $installs[$State.DCursor].ModuleBase
            if ($State.DSelected.ContainsKey($path)) { $State.DSelected.Remove($path) } else { $State.DSelected[$path] = $true }
            $State.DCursor = [Math]::Min($count - 1, $State.DCursor + 1)
            return
        }
        { $_ -in [ConsoleKey]::Escape, [ConsoleKey]::LeftArrow, [ConsoleKey]::Backspace } { $State.Mode = 'list'; return }
        ([ConsoleKey]::Delete) { Request-MMTuiUninstallVersion $State; return }
    }
    switch ($c) {
        'k' { $State.DCursor = [Math]::Max(0, $State.DCursor - 1) }
        'j' { $State.DCursor = [Math]::Min($count - 1, $State.DCursor + 1) }
        'q' { $State.Mode = 'list' }
        'x' { Request-MMTuiUninstallVersion $State }
        'o' { Request-MMTuiRemoveOld $State @($State.Detail) }
        'u' { Request-MMTuiUpdate $State @($State.Detail) }
    }
}
