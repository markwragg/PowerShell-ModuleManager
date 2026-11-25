function Set-MMTuiCursor {
    <#
    .SYNOPSIS
        Moves the terminal UI cursor to a row, keeping it within the list.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    param([hashtable]$State, [int]$Index)
    $count = $State.Visible.Count
    if ($count -eq 0) { $State.Cursor = 0; $State.CurrentName = $null; return }
    $State.Cursor = [Math]::Max(0, [Math]::Min($Index, $count - 1))
    $State.CurrentName = $State.Visible[$State.Cursor].Key
}
