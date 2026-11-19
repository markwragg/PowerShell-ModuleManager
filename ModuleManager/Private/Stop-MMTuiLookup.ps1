function Stop-MMTuiLookup {
    <#
    .SYNOPSIS
        Stops the terminal UI's repository check, if one is running, on this computer or the remote one.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stops the terminal UI''s own background lookups; changes no system state.')]
    param([hashtable]$State)
    $job = $State.Job
    if (-not $job) { return }
    $State.Job = $null
    if ($job.PSObject.Properties['Remote']) {
        try { $job.Command.PowerShell.Stop(); $job.Command.PowerShell.Dispose() } catch { Write-Debug $_ }
    }
    else { Stop-MMGalleryLookup $job }
}
