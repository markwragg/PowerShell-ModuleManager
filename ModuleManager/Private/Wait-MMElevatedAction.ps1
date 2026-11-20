function Wait-MMElevatedAction {
    <#
    .SYNOPSIS
        Starts the elevated PowerShell process for an action, and relays its output until it finishes.

    .DESCRIPTION
        Runs in the background runspace of an action started with Start-MMTuiElevatedAction. Starts
        the elevated process (Windows asks for administrator rights first), then reads the batches
        of output and progress it writes to $Directory (numbered 0.xml, 1.xml, ...) and repeats them
        as output pane lines (Write-MMTuiOutput) and progress, until it writes 'done'.

        When the action is stopped, writes 'stop', which the elevated process checks for: it stops
        the action and removes the folder. Whichever side finishes last removes the folder.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Runs an action the user already confirmed.')]
    param([string]$Directory, [string]$FilePath, [string]$ArgumentList)

    $doneFile = Join-Path $Directory 'done'
    Write-MMTuiOutput '  Waiting for administrator rights (Windows asks)...' 'Dim'
    try {
        $start = @{ FilePath = $FilePath; Verb = 'RunAs'; WindowStyle = 'Hidden'; PassThru = $true; ErrorAction = 'Stop' }
        # Windows PowerShell's Start-Process doesn't take an empty argument list.
        if ($ArgumentList) { $start.ArgumentList = $ArgumentList }
        $process = Start-Process @start
    }
    catch {
        Remove-Item -LiteralPath $Directory -Recurse -Force -ErrorAction Ignore
        $e = $_.Exception
        while ($e.InnerException) { $e = $e.InnerException }
        # 1223: ERROR_CANCELLED, when No is chosen at the administrator prompt.
        if ($e -is [ComponentModel.Win32Exception] -and $e.NativeErrorCode -eq 1223) {
            Write-MMTuiOutput "ERROR: Administrator rights weren't given, so nothing was changed." 'Red'
        }
        else { Write-MMTuiOutput "ERROR: Couldn't start PowerShell as administrator: $($e.Message)" 'Red' }
        return
    }

    $next = 0
    $done = $false
    try {
        while ($true) {
            # Check before reading, so the last batch (written before 'done') is read too.
            $finished = (Test-Path -LiteralPath $doneFile) -or $process.HasExited
            while (Test-Path -LiteralPath ($batch = Join-Path $Directory "$next.xml")) {
                # A batch is an array, which comes back as one ArrayList.
                $batchItems = Import-Clixml -LiteralPath $batch
                foreach ($item in $batchItems) {
                    if ($item.Kind -eq 'Progress') {
                        $activity = if ($item.Activity) { [string]$item.Activity } else { 'Working' }
                        if ($item.Completed) { Write-Progress -Activity $activity -Completed }
                        else {
                            $progress = @{ Activity = $activity; PercentComplete = [int]$item.Percent }
                            if ($item.Status) { $progress.Status = [string]$item.Status }
                            Write-Progress @progress
                        }
                    }
                    else { Write-MMTuiOutput -Text $item.Text -Style $item.Style }
                }
                Remove-Item -LiteralPath $batch -Force -ErrorAction Ignore
                $next++
            }
            if ($finished) { break }
            Start-Sleep -Milliseconds 100
        }
        $done = Test-Path -LiteralPath $doneFile
        if (-not $done) {
            $code = try { $process.ExitCode } catch { '?' }
            Write-MMTuiOutput "ERROR: PowerShell running as administrator ended unexpectedly (exit code $code)." 'Red'
        }
    }
    finally {
        # Stopped (or failed) before the elevated process finished: ask it to stop. It removes the
        # folder when it ends, unless it already had, in which case it's removed here.
        if (-not $done) { $null = New-Item -ItemType File -Path (Join-Path $Directory 'stop') -Force -ErrorAction Ignore }
        if ($done -or (Test-Path -LiteralPath $doneFile) -or $process.HasExited) {
            Remove-Item -LiteralPath $Directory -Recurse -Force -ErrorAction Ignore
        }
    }
}
