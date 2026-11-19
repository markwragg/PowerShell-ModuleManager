function Stop-MMTuiTask {
    <#
    .SYNOPSIS
        Stops the running terminal UI operation, if any.

    .DESCRIPTION
        Used when quitting while an operation is running, and when the terminal UI closes.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stops an operation the user already confirmed stopping (or the UI is closing).')]
    param([hashtable]$State)
    $task = $State.Task
    if (-not $task) { return }
    $State.Task = $null
    $State.Progress = $null
    $runspace = $task.PowerShell.Runspace
    try { $task.PowerShell.Stop(); $task.PowerShell.Dispose() } catch { Write-Debug $_ }
    if ($task.ContainsKey('OwnsRunspace') -and -not $task.OwnsRunspace) { return }   # the remote runspace stays open
    try { if ($runspace) { $runspace.Dispose() } } catch { Write-Debug $_ }
}
