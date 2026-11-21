function Request-MMTuiUpdate {
    <#
    .SYNOPSIS
        Asks to update the targeted modules that have updates, then updates them.

    .DESCRIPTION
        y updates them. o also removes their old versions afterwards, keeping the newest, in the
        same operation: for each module that was updated, including dependencies installed with
        them, as Update-ManagedModule -RemoveOldVersions does. Loaded old versions, and old versions
        that other installed modules depend on, are kept.
    #>
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
    if ($State.Remote) {
        $untrusted = @(Invoke-MMRemote -Remote $State.Remote -ArgumentList @(, $repositories) -ScriptBlock { param($Name) Get-MMUntrustedRepository -Name $Name })
    }
    else { $untrusted = @(Get-MMUntrustedRepository -Name $repositories) }
    $prompt = "Update $($rows.Count) module(s): $list"
    if ($untrusted) { $prompt += " - from untrusted repository $($untrusted -join ', ')" }

    $prompt += ' ? o also removes old versions.'
    # Updates install into the newest version's scope, so updating modules installed for all users
    # needs administrator rights, which on Windows the update gets if this session hasn't.
    $elevate = Test-MMTuiNeedsElevation $State -Installation @($rows | ForEach-Object { @($_.Info.Installations)[0] })
    # Once updated, every version installed now is an old version, and any of them may be installed
    # for all users. (Old versions of dependencies installed with them aren't known until then.)
    $elevateRemove = $elevate -or (Test-MMTuiNeedsElevation $State -Installation @($rows | ForEach-Object { @($_.Info.Installations) }))
    if ($elevate) { $prompt += " $script:MMElevationNote" }
    elseif ($elevateRemove) { $prompt += ' o runs as administrator: Windows asks first.' }

    $data = @{ Names = @($rows | ForEach-Object { $_.Name }); Trust = [bool]$untrusted; Elevate = $elevate; ElevateRemove = $elevateRemove }
    Request-MMTuiConfirm $State $prompt -Data $data -Choices 'yo' -Action {
        param($State, $Data, $Choice)
        $run = @{ Names = $Data.Names; Trust = $Data.Trust; RemoveOld = ($Choice -eq 'o') }
        $elevated = $Data.Elevate -or ($run.RemoveOld -and $Data.ElevateRemove)
        $title = "Updating $($Data.Names.Count) module(s)"
        if ($run.RemoveOld) { $title += ' and removing old versions' }
        Invoke-MMTuiAction $State $title -Data $run -Elevated:$elevated -Action {
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
                Write-MMTuiOutput "  Updated  $($m.Name) $($m.Version)$note" 'Green'
            }
            # -ErrorVariable also collects errors that were caught along the way (such as the
            # package manager's own error behind each 'Failed to update' error), so report the
            # module's own errors, or else each distinct message once.
            $failed = @($failed | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $own = @($failed | Where-Object { $_.FullyQualifiedErrorId -like 'ModuleManager.*' })
            if ($own) { $failed = $own }
            else { $failed = @($failed | Group-Object -Property { $_.Exception.Message } | ForEach-Object { $_.Group[0] }) }
            foreach ($e in $failed) { Write-MMTuiOutput "  Failed   $($e.Exception.Message)" 'Red' }
            $summary = "$($updated.Count) updated"
            if ($asDependency) { $summary += " ($asDependency as dependencies)" }
            Write-MMTuiOutput "$summary, $($failed.Count) failed."
            # Only for modules that were updated (a failed update keeps its old versions), and once,
            # for all of them, so old versions that depend on each other (an old Az rollup and the
            # Az.* versions it pins) go together. -Verbose shows a line per version removed.
            if ($Data.RemoveOld -and $updated.Count) {
                Uninstall-OldModuleVersion -Name @($updated | ForEach-Object { $_.Name }) -Keep 1 -Confirm:$false -Verbose
            }
        } -OnComplete {
            param($State)
            foreach ($r in $State.Rows) { $r.Selected = $false }
        }
    }
}
