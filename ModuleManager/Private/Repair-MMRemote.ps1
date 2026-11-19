function Repair-MMRemote {
    <#
    .SYNOPSIS
        Reconnects the terminal UI's remote target when its runspace can no longer run commands.

    .DESCRIPTION
        Replaces the runspace (and, for another edition, its process) in the remote target it's
        given, so everything holding that target carries on with the new connection:
          - Another edition (Connect-MMEdition): its process is stopped and a new one started.
          - A remote computer (Connect-MMRemote): a new runspace is opened with the same
            connection details.
        Throws if it can't reconnect, or if the target has no connection details to reconnect with.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Remote)

    if ($Remote.ContainsKey('Edition') -and $Remote.Edition) {
        # Ending the process first means the old runspace has nothing to wait for when it's disposed.
        if ($Remote.ContainsKey('Process')) { Stop-MMEditionProcess $Remote.Process }
        try { $Remote.Runspace.Dispose() } catch { Write-Debug $_ }
        $new = Connect-MMEdition -Edition $Remote.Edition
        $Remote.Runspace = $new.Runspace
        $Remote.Process = $new.Process
        $Remote.Name = $new.Name
        return
    }
    if ($Remote.ContainsKey('ConnectionInfo') -and $Remote.ConnectionInfo) {
        try { $Remote.Runspace.Dispose() } catch { Write-Debug $_ }
        try {
            $runspace = [runspacefactory]::CreateRunspace($Remote.ConnectionInfo)
            $runspace.Open()
        }
        catch { throw "Could not reconnect to $($Remote.Name): $($_.Exception.Message)" }
        $Remote.Runspace = (Initialize-MMRemote -Runspace $runspace -Name $Remote.Name).Runspace
        return
    }
    throw "There are no connection details to reconnect to $($Remote.Name) with."
}
