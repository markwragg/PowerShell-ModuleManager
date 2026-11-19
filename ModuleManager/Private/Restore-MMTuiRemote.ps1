function Restore-MMTuiRemote {
    <#
    .SYNOPSIS
        After a remote command was stopped, makes sure the terminal UI's remote connection can still
        run commands, reconnecting if it can't.

    .DESCRIPTION
        If the command didn't stop within its time limit, or the runspace then doesn't answer
        within a few seconds, something is still running there, and the runspace runs one command
        at a time, so it reconnects. Says on the status line when it reconnected, or couldn't.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Reconnects the terminal UI''s own connection; changes no system state.')]
    param([hashtable]$State, [bool]$Stopped)
    $remote = $State.Remote
    if (-not $remote) { return }
    if ($Stopped -and (Test-MMRemote -Remote $remote)) { return }

    $name = $remote.Name
    try {
        Repair-MMRemote -Remote $remote
        Set-MMTuiMessage $State "Reconnected to $name, as it was still busy with the stopped command." 'Yellow'
    }
    catch {
        Set-MMTuiMessage $State "Lost the connection to $name, which is still busy with the stopped command: $($_.Exception.Message) Quit and start again." 'Red'
    }
}
