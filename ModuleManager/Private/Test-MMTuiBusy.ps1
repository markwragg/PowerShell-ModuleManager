function Test-MMTuiBusy {
    <#
    .SYNOPSIS
        Returns $true, and says so on the status line, when a terminal UI operation is still running.
    #>
    param([hashtable]$State)
    if (-not $State.Task) { return $false }
    Set-MMTuiMessage $State "Wait for '$($State.Task.Title)' to finish first." 'Yellow'
    $State.LogOpen = $true
    $true
}
