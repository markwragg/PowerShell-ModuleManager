function Request-MMTuiUpdate {
    <#
    .SYNOPSIS
        Asks to update the targeted modules that have updates, then updates them.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The update runs in a background runspace, where Write-Host output (with its colour) is collected for the output pane.')]
    param([hashtable]$State, [object[]]$Rows)
    if (Test-MMTuiBusy $State) { return }
    $rows = @($Rows | Where-Object Status -EQ 'UpdateAvailable')
    if (-not $rows) {
        if ($State.Job) { Set-MMTuiMessage $State 'Still checking repositories - try again in a moment.' 'Yellow' }
        else { Set-MMTuiMessage $State 'Nothing to update: no updates available for the selected module(s).' 'Yellow' }
        return
    }
    $list = ($rows | Select-Object -First 4 | ForEach-Object { "$($_.Name) $($_.Info.Version) -> $($_.Latest)" }) -join ', '
    if ($rows.Count -gt 4) { $list += " and $($rows.Count - 4) more" }

    # The update runs where nothing can answer the package manager's "untrusted repository"
    # prompt, so ask here: confirming the update also confirms installing from that repository.
    $repositories = @($rows | ForEach-Object { if ($_.Result -and $_.Result.PSObject.Properties['Repository']) { $_.Result.Repository } })
    $untrusted = @(Get-MMUntrustedRepository -Name $repositories)
    $prompt = "Update $($rows.Count) module(s): $list"
    if ($untrusted) { $prompt += " - from untrusted repository $($untrusted -join ', ')" }

    $data = @{ Names = @($rows | ForEach-Object { $_.Name }); Trust = [bool]$untrusted }
    Request-MMTuiConfirm $State "$prompt ?" -Data $data -Action {
        param($State, $Data)
        Invoke-MMTuiAction $State "Updating $($Data.Names.Count) module(s)" -Data $Data -Action {
            param($Data, $Options)
            # Update-ManagedModule reports progress (shown above the output), and we print one
            # line per module afterwards. Warnings (e.g. module is loaded) still show.
            $failed = @()
            $updated = @(Update-ManagedModule -Name $Data.Names -Repository $Options.Repository `
                    -IncludePrerelease:$Options.IncludePrerelease -TrustRepository:$Data.Trust -Confirm:$false -PassThru `
                    -ErrorAction SilentlyContinue -ErrorVariable failed)
            $asDependency = 0
            foreach ($m in $updated) {
                $note = ''
                if ($m.UpdatedAsDependencyOf) { $note = "  (dependency of $($m.UpdatedAsDependencyOf))"; $asDependency++ }
                Write-Host "  Updated  $($m.Name) $($m.Version)$note" -ForegroundColor Green
            }
            # -ErrorVariable also collects errors that were caught along the way (such as the
            # package manager's own error behind each 'Failed to update' error), so report the
            # module's own errors, or else each distinct message once.
            $failed = @($failed | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $own = @($failed | Where-Object { $_.FullyQualifiedErrorId -like 'ModuleManager.*' })
            if ($own) { $failed = $own }
            else { $failed = @($failed | Group-Object -Property { $_.Exception.Message } | ForEach-Object { $_.Group[0] }) }
            foreach ($e in $failed) { Write-Host "  Failed   $($e.Exception.Message)" -ForegroundColor Red }
            $summary = "$($updated.Count) updated"
            if ($asDependency) { $summary += " ($asDependency as dependencies)" }
            Write-Host "$summary, $($failed.Count) failed."
        } -OnComplete {
            param($State)
            foreach ($r in $State.Rows) { $r.Selected = $false }
        }
    }
}
