function Test-MMTuiNeedsElevation {
    <#
    .SYNOPSIS
        Returns $true if a terminal UI operation should run as administrator (see Start-MMTuiElevatedAction).

    .DESCRIPTION
        True when this session isn't elevated, on Windows, managing this computer (remotely, the
        remote session's own rights apply), and the operation changes modules installed for all
        users: any of -Installation in the AllUsers scope, or always with -Always (moves, which
        are always to or from AllUsers).
    #>
    param([hashtable]$State, [object[]]$Installation, [switch]$Always)
    if ($State.Remote -or -not (Test-MMIsWindows) -or (Test-MMIsAdmin)) { return $false }
    if ($Always) { return $true }
    [bool]@($Installation | Where-Object { $_ -and $_.Scope -eq 'AllUsers' }).Count
}
