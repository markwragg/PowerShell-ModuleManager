function Test-MMTuiBusy {
    <#
    .SYNOPSIS
        Returns $true, and says so on the status line, when a terminal UI operation is still running.
    #>
    param([hashtable]$State, [switch]$AllowLookup)
    if ($State.Task) {
        Set-MMTuiMessage $State "Wait for '$($State.Task.Title)' to finish first." 'Yellow'
        $State.LogOpen = $true
        return $true
    }
    # Remotely, the repository check and actions share one runspace, which runs one command at a time.
    if ($State.Remote -and $State.Job -and -not $AllowLookup) {
        Set-MMTuiMessage $State "Wait for the repository check on $($State.Remote.Name) to finish first." 'Yellow'
        return $true
    }
    $false
}
