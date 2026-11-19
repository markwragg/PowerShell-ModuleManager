function Receive-MMTuiTask {
    <#
    .SYNOPSIS
        Collects output and progress from the running terminal UI operation, and finishes it when it ends.

    .DESCRIPTION
        Collects output and progress from the running operation (see Invoke-MMTuiAction). When it
        has finished, cleans up, runs its OnComplete step and rescans. Returns $true if anything
        changed on screen.
    #>
    param([hashtable]$State)
    $task = $State.Task
    if (-not $task) { return $false }
    $changed = $false

    foreach ($record in $task.Output.ReadAll()) {
        $entry = ConvertTo-MMTuiLogEntry $record
        if ($entry.Style -eq 'Red') { $task.Errors++ }
        $State.Log.Add($entry)
        $changed = $true
    }

    # Show the newest progress from the top-level activity (the operation's own progress bar).
    $progress = $task.PowerShell.Streams.Progress
    if ($progress.Count) {
        foreach ($p in $progress.ReadAll()) {
            if ($p.ParentActivityId -ge 0) { continue }
            if ($p.RecordType -eq [System.Management.Automation.ProgressRecordType]::Completed) { $State.Progress = $null }
            else { $State.Progress = @{ Activity = $p.Activity; Status = $p.StatusDescription; Percent = $p.PercentComplete } }
        }
        $changed = $true
    }

    if (-not $task.Handle.IsCompleted) { return $changed }

    try { $null = $task.PowerShell.EndInvoke($task.Handle) }
    catch {
        $e = $_.Exception
        while ($e.InnerException -and $e -is [System.Management.Automation.MethodInvocationException]) { $e = $e.InnerException }
        $State.Log.Add(@{ Text = "ERROR: $($e.Message)"; Style = 'Red' })
        $task.Errors++
    }
    foreach ($record in $task.Output.ReadAll()) {
        $entry = ConvertTo-MMTuiLogEntry $record
        if ($entry.Style -eq 'Red') { $task.Errors++ }
        $State.Log.Add($entry)
    }
    $runspace = $task.PowerShell.Runspace
    $task.PowerShell.Dispose()
    if ($runspace -and $task.OwnsRunspace) { $runspace.Dispose() }

    $State.Task = $null
    $State.Progress = $null
    $elapsed = Format-MMElapsed ([datetime]::UtcNow - $task.Started)
    if ($task.Errors) {
        $State.Log.Add(@{ Text = "Finished in $elapsed with $($task.Errors) error(s)."; Style = 'Red' })
        Set-MMTuiMessage $State "$($task.Title) - finished with $($task.Errors) error(s). See the output below." 'Red'
    }
    else {
        $State.Log.Add(@{ Text = "Finished in $elapsed."; Style = 'Green' })
        Set-MMTuiMessage $State "$($task.Title) - done." 'Green'
    }

    try { Update-MMTuiRows $State }
    catch { Set-MMTuiMessage $State "$($task.Title) - finished, but the rescan failed: $($_.Exception.Message)" 'Red' }
    if ($task.OnComplete) { & $task.OnComplete $State $task.Data }
    Sync-MMTuiDetail $State
    Update-MMTuiVisible $State
    $true
}
