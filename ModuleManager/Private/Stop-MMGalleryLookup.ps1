function Stop-MMGalleryLookup {
    <#
    .SYNOPSIS
        Stops a repository lookup job and releases its runspaces.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Disposes this module''s own background runspaces; changes no system state.')]
    param([object]$Job)
    if (-not $Job) { return }
    foreach ($task in $Job.Tasks) {
        if ($task.Collected) { continue }
        $task.Collected = $true
        try { $task.PowerShell.Stop(); $task.PowerShell.Dispose() } catch { Write-Debug $_ }
    }
    if ($Job.Pool) {
        try { $Job.Pool.Close(); $Job.Pool.Dispose() } catch { Write-Debug $_ }
        $Job.Pool = $null
    }
}
