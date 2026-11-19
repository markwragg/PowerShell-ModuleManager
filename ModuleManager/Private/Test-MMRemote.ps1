function Test-MMRemote {
    <#
    .SYNOPSIS
        Returns $true if the remote runspace can run a command, checking for no longer than a time limit.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][hashtable]$Remote,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 5
    )
    $runspace = $Remote.Runspace
    if (-not $runspace -or $runspace.RunspaceStateInfo.State -ne 'Opened') { return $false }
    $ps = $null
    try {
        $ps = [powershell]::Create()
        $ps.Runspace = $runspace
        [void]$ps.AddScript("'MMReady'")
        $handle = $ps.BeginInvoke()
        if (-not $handle.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            # Busy with a command that didn't stop. Leave this one to be cleaned up with the runspace.
            $null = $ps.BeginStop($null, $null)
            $ps = $null
            return $false
        }
        return (@($ps.EndInvoke($handle)) -contains 'MMReady')
    }
    catch { return $false }
    finally { if ($ps) { $ps.Dispose() } }
}
