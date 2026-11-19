function Stop-MMTuiLookup {
    <#
    .SYNOPSIS
        Stops the terminal UI's repository check, if one is running, on this computer or the remote one.

    .DESCRIPTION
        Remotely, the check runs in the runspace everything else uses, so if it doesn't stop
        cleanly the connection is checked, and remade if needed (see Restore-MMTuiRemote).
        -Closing skips that, for when the terminal UI is about to disconnect anyway.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stops the terminal UI''s own background lookups; changes no system state.')]
    param([hashtable]$State, [switch]$Closing)
    $job = $State.Job
    if (-not $job) { return }
    $State.Job = $null
    if ($job.PSObject.Properties['Remote']) {
        $stopped = Stop-MMRemoteCommand -PowerShell $job.Command.PowerShell -Handle $job.Command.Handle
        if (-not $Closing) { Restore-MMTuiRemote -State $State -Stopped $stopped }
    }
    else { Stop-MMGalleryLookup $job }
}
