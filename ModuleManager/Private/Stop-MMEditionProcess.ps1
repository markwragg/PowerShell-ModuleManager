function Stop-MMEditionProcess {
    <#
    .SYNOPSIS
        Ends a process started by Connect-MMEdition: closing its standard input lets it exit by
        itself, and it's stopped if it hasn't within a few seconds.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stops a hidden process ModuleManager started itself.')]
    param([System.Diagnostics.Process]$Process)
    if (-not $Process) { return }
    try {
        if (-not $Process.HasExited) {
            $Process.StandardInput.Close()
            if (-not $Process.WaitForExit(3000)) { $Process.Kill() }
        }
    }
    catch { Write-Debug $_ }
    finally { $Process.Dispose() }
}
