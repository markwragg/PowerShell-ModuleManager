function Disconnect-MMRemote {
    <#
    .SYNOPSIS
        Closes the terminal UI's remote runspace (see Connect-MMRemote), and ends the other edition's
        process if it was started for it (see Connect-MMEdition).
    #>
    param([hashtable]$Remote)
    if (-not $Remote) { return }
    try { $Remote.Runspace.Dispose() } catch { Write-Debug $_ }
    if ($Remote.ContainsKey('Process')) { Stop-MMEditionProcess $Remote.Process }
}
