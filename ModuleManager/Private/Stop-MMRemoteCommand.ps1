function Stop-MMRemoteCommand {
    <#
    .SYNOPSIS
        Stops a command started by Start-MMRemoteCommand, without waiting longer than a time limit.

    .DESCRIPTION
        A stop sent before the remote process has started running the command is lost: the
        command carries on there, and the remote runspace can't run anything else until it ends.
        So this waits for the command to say it's running (see Start-MMRemoteCommand) before
        stopping it.

        Returns $true if the command stopped within the time limit. If it didn't, the remote
        runspace may still be busy: check it with Test-MMRemote.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stops a command ModuleManager started itself.')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][System.Management.Automation.PowerShell]$PowerShell,
        [System.IAsyncResult]$Handle,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 10
    )
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not $PowerShell.Streams.Information.Count -and -not ($Handle -and $Handle.IsCompleted) -and [datetime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 10
    }

    $stopped = $false
    try {
        $remaining = [Math]::Max(1000, [int]($deadline - [datetime]::UtcNow).TotalMilliseconds)
        $stopped = $PowerShell.BeginStop($null, $null).AsyncWaitHandle.WaitOne($remaining)
    }
    catch { Write-Debug $_ }
    # Disposing a command that hasn't stopped would wait for it, so it's left for the runspace to clean up.
    if ($stopped) { try { $PowerShell.Dispose() } catch { Write-Debug $_ } }
    $stopped
}
