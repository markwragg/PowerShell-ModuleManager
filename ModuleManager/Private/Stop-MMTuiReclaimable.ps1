function Stop-MMTuiReclaimable {
    <#
    .SYNOPSIS
        Stops working out the Reclaim column, if it's still being worked out, and forgets it.

    .DESCRIPTION
        Used when the modules are rescanned (the old versions may have changed) and when the
        terminal UI closes.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI, not system state.')]
    param([hashtable]$State)
    $reclaim = $State.Reclaim
    $State.Reclaim = $null
    if (-not $reclaim -or -not $reclaim.PowerShell) { return }
    try { $reclaim.PowerShell.Stop() } catch { Write-Debug $_ }
    try { $reclaim.PowerShell.Dispose() } catch { Write-Debug $_ }
}
