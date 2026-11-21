function Request-MMTuiRemoveOld {
    <#
    .SYNOPSIS
        Asks to remove the old versions of the targeted modules, then removes them.

    .DESCRIPTION
        Loaded old versions that can be unloaded safely (see Get-MMUnloadBlocker) are offered as a
        choice: y skips them, f unloads them from this session first so they're removed too.
    #>
    param([hashtable]$State, [object[]]$Rows)
    if (Test-MMTuiBusy $State) { return }
    $rows = @($Rows | Where-Object { $_.Info.VersionCount -gt 1 })
    if (-not $rows) { Set-MMTuiMessage $State 'Nothing to remove: only one version installed.' 'Yellow'; return }
    # The newest version of each is kept, so only older versions that are loaded matter.
    $old = @(foreach ($r in $rows) { @($r.Info.Installations) | Select-Object -Skip 1 })
    # Remotely, "loaded" means loaded in ModuleManager's own session there, which this UI can't unload.
    $assemblies = @()
    if (-not $State.Remote) { $assemblies = @(Get-MMLoadedAssemblyPath) }
    $unloadable = @(); $blocked = @()
    foreach ($i in @($old | Where-Object IsLoaded)) {
        $reason = Get-MMUnloadBlocker -Installation $i -AssemblyPath $assemblies
        if (-not $reason -and $State.Remote) { $reason = "ModuleManager's session on $($State.Remote.Name) is using it" }
        if ($reason) { $blocked += "$($i.Name) $($i.Version): it is loaded in this session and $reason. Remove it from a new session." }
        else { $unloadable += $i }
    }

    $prompt = "Remove $($old.Count) old version(s) of $($rows.Count) module(s), keeping the newest?"
    $choices = 'y'
    if ($unloadable) {
        $names = @($unloadable | Select-Object -First 2 | ForEach-Object { "$($_.Name) $($_.Version)" }) -join ', '
        if ($unloadable.Count -gt 2) { $names += " and $($unloadable.Count - 2) more" }
        $prompt += " $names is loaded: y skips it, f unloads it first."
        $choices = 'yf'
    }
    if ($blocked) { $prompt += " Skips $($blocked.Count) loaded version(s) that can't be unloaded." }
    # Old versions installed for all users need administrator rights, which on Windows the
    # removal gets if this session hasn't.
    $elevate = Test-MMTuiNeedsElevation $State -Installation $old
    if ($elevate) { $prompt += " $script:MMElevationNote" }

    $data = @{ Elevate = $elevate; Names = @($rows | ForEach-Object { $_.Name }); UnloadBases = @($unloadable | ForEach-Object { $_.ModuleBase }); Blocked = $blocked }
    Request-MMTuiConfirm $State $prompt -Data $data -Choices $choices -Action {
        param($State, $Data, $Choice)
        $run = @{ Names = $Data.Names; Blocked = $Data.Blocked; Notes = @() }
        if ($Choice -eq 'f') { $run.Notes = @(Remove-MMSessionModule -ModuleBase $Data.UnloadBases -Confirm:$false) }
        Invoke-MMTuiAction $State "Removing old versions of $($Data.Names.Count) module(s)" -Data $run -Elevated:$Data.Elevate -Action {
            param($Data)
            foreach ($n in $Data.Notes) { Write-MMTuiOutput "  $n" 'Yellow' }
            Uninstall-ManagedModule -Name $Data.Names -OldVersions -Confirm:$false -Verbose
            foreach ($b in $Data.Blocked) { Write-MMTuiOutput "  Skipped  $b" 'Yellow' }
        } -OnComplete {
            param($State)
            foreach ($r in $State.Rows) { $r.Selected = $false }
        }
    }
}
