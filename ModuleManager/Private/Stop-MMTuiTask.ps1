function Stop-MMTuiTask {
    <#
    .SYNOPSIS
        Stops the running terminal UI operation, if any.

    .DESCRIPTION
        Used when quitting while an operation is running, and when the terminal UI closes.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stops an operation the user already confirmed stopping (or the UI is closing).')]
    param([hashtable]$State, [switch]$Closing)
    $task = $State.Task
    if (-not $task) { return }
    $State.Task = $null
    $State.Progress = $null
    if ($task.ContainsKey('OwnsRunspace') -and -not $task.OwnsRunspace) {
        # Remotely, the runspace stays open for the next command: make sure it's free (see Stop-MMTuiLookup).
        $stopped = Stop-MMRemoteCommand -PowerShell $task.PowerShell -Handle $task.Handle
        if (-not $Closing) { Restore-MMTuiRemote -State $State -Stopped $stopped }
        return
    }
    $runspace = $task.PowerShell.Runspace
    try { $task.PowerShell.Stop(); $task.PowerShell.Dispose() } catch { Write-Debug $_ }
    try { if ($runspace) { $runspace.Dispose() } } catch { Write-Debug $_ }
}
