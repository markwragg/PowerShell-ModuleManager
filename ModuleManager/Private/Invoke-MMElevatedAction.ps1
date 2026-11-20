function Invoke-MMElevatedAction {
    <#
    .SYNOPSIS
        Runs a terminal UI action in the elevated process started for it, writing its output back in batches.

    .DESCRIPTION
        Runs in the elevated PowerShell process started by Start-MMTuiElevatedAction. Reads the
        request from $Directory, runs the action the same way as in the UI (Start-MMTuiLocalAction,
        with the UI session's loaded modules and PSModulePath), and writes its output lines and
        progress as numbered batches (0.xml, 1.xml, ...) for Wait-MMElevatedAction, then 'done'.

        Stops the action if 'stop' appears. If the administrator rights were given as another
        user (a standard user entering an administrator's credentials), nothing is run, as
        CurrentUser would then mean that user's modules.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Runs an action the user already confirmed.')]
    param([Parameter(Mandatory)][string]$Directory)

    $stopFile = Join-Path $Directory 'stop'
    $items = [System.Collections.Generic.List[object]]::new()
    $state = @{ Batch = 0 }
    $line = { param([string]$Text, [string]$Style) $items.Add(@{ Kind = 'Line'; Text = $Text; Style = $Style }) }
    $flush = {
        if (-not $items.Count) { return }
        $path = Join-Path $Directory "$($state.Batch)"
        Export-Clixml -InputObject $items.ToArray() -LiteralPath "$path.tmp" -Depth 3
        # Renamed once complete, so a batch is never read half-written.
        [IO.File]::Move("$path.tmp", "$path.xml")
        $state.Batch++
        $items.Clear()
    }

    $task = $null
    try {
        $request = Import-Clixml -LiteralPath (Join-Path $Directory 'request.xml')
        $identity = Get-MMUserIdentity
        if ($identity.Sid -ne $request.UserSid) {
            & $line ("ERROR: Administrator rights were given as $($identity.Name), not $($request.UserName), so nothing was changed: " +
                "CurrentUser would mean that user's modules. Run PowerShell as administrator as $($request.UserName) instead.") 'Red'
            return
        }

        $env:PSModulePath = $request.PSModulePath
        $script:MMLoadedModule = @($request.Loaded)
        foreach ($k in $request.Gallery.Keys) { $script:MMGalleryCache[$k] = $request.Gallery[$k] }

        $task = @{}
        Start-MMTuiLocalAction -Task $task -Action ([scriptblock]::Create($request.Action)) -Data $request.Data -Options $request.Options
        $drain = {
            foreach ($r in $task.Output.ReadAll()) { $e = ConvertTo-MMTuiLogEntry $r; & $line $e.Text $e.Style }
            foreach ($p in $task.PowerShell.Streams.Progress.ReadAll()) {
                if ($p.ParentActivityId -ge 0) { continue }
                $items.Add(@{
                        Kind      = 'Progress'
                        Activity  = $p.Activity
                        Status    = $p.StatusDescription
                        Percent   = $p.PercentComplete
                        Completed = $p.RecordType -eq [System.Management.Automation.ProgressRecordType]::Completed
                    })
            }
        }

        $stopped = $false
        while ($true) {
            $finished = $task.Handle.IsCompleted
            & $drain
            & $flush
            if ($finished) { break }
            if (Test-Path -LiteralPath $stopFile) { $task.PowerShell.Stop(); $stopped = $true; break }
            Start-Sleep -Milliseconds 100
        }
        if (-not $stopped) {
            try { $null = $task.PowerShell.EndInvoke($task.Handle) }
            catch {
                $e = $_.Exception
                while ($e.InnerException -and $e -is [System.Management.Automation.MethodInvocationException]) { $e = $e.InnerException }
                & $line "ERROR: $($e.Message)" 'Red'
            }
        }
        & $drain
    }
    catch { & $line "ERROR: $($_.Exception.Message)" 'Red' }
    finally {
        if ($task -and $task.PowerShell) {
            $runspace = $task.PowerShell.Runspace
            $task.PowerShell.Dispose()
            if ($runspace) { $runspace.Dispose() }
        }
        try { & $flush } catch { Write-Debug $_ }
        $null = New-Item -ItemType File -Path (Join-Path $Directory 'done') -Force -ErrorAction Ignore
        # Stopped, so nothing is waiting for the output any more.
        if (Test-Path -LiteralPath $stopFile) { Remove-Item -LiteralPath $Directory -Recurse -Force -ErrorAction Ignore }
    }
}
