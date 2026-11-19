function Receive-MMTuiLookup {
    <#
    .SYNOPSIS
        Applies finished repository lookups to the terminal UI rows.

    .DESCRIPTION
        Returns $true if anything changed.
    #>
    param([hashtable]$State)
    $job = $State.Job
    if (-not $job) { return $false }
    $failure = $null
    if ($job.PSObject.Properties['Remote']) {
        # Each result comes back serialized (see Start-MMTuiLookup).
        $command = $job.Command
        $finished = $command.Handle.IsCompleted
        $new = @(foreach ($text in $command.Output.ReadAll()) {
                foreach ($r in [System.Management.Automation.PSSerializer]::Deserialize([string]$text)) { $r }
            })
        $job.Done += $new.Count
        if ($finished) {
            try { $null = $command.PowerShell.EndInvoke($command.Handle) }
            catch {
                $e = $_.Exception
                while ($e.InnerException -and $e -is [System.Management.Automation.MethodInvocationException]) { $e = $e.InnerException }
                $failure = $e.Message
            }
            $command.PowerShell.Dispose()
        }
    }
    else {
        $new = @(Receive-MMGalleryLookup -Job $job)
        $finished = Test-MMGalleryLookupComplete -Job $job
    }
    foreach ($r in $new) { $State.Gallery[$r.RequestedName.ToLowerInvariant()] = $r }
    $changed = $new.Count -gt 0
    if ($finished) { $State.Job = $null; $changed = $true }
    if ($changed) { Update-MMTuiStatus $State }
    if ($failure) {
        $where = ''
        if ($State.Remote) { $where = " on $($State.Remote.Name)" }
        Set-MMTuiMessage $State "The repository check$where failed: $failure" 'Red'
    }
    elseif ($finished) {
        $count = @($State.Rows | Where-Object Status -EQ 'UpdateAvailable').Count
        $failed = @($State.Rows | Where-Object Status -EQ 'Error')
        $text = "Update check complete: $count update(s) available."
        $style = 'Green'
        if ($failed) {
            # Say why, so a problem that fails every lookup (such as a missing package provider) is clear.
            $reasons = @($failed | ForEach-Object { if ($_.Result -and $_.Result.PSObject.Properties['Error']) { [string]$_.Result.Error } } | Where-Object { $_ } | Sort-Object -Unique)
            $text += " $($failed.Count) lookup(s) failed"
            if ($reasons.Count -eq 1) { $text += ": $($reasons[0])" }
            elseif ($reasons) { $text += ", for example: $($reasons[0])" }
            else { $text += '.' }
            $style = 'Yellow'
        }
        Set-MMTuiMessage $State $text $style
        if ($failed) { Request-MMTuiNuGetProvider $State $failed }
    }
    $changed
}
