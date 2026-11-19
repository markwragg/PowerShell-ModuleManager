function Request-MMTuiUninstallInstallation {
    <#
    .SYNOPSIS
        Asks to uninstall the given module versions, offering to unload any that are loaded, then uninstalls them.

    .DESCRIPTION
        Loaded versions can't be uninstalled while they're loaded. Those that can be unloaded
        safely (see Get-MMUnloadBlocker) are offered as a choice: y uninstalls the rest and skips
        them, f unloads them from this session first and uninstalls them too. Those that can't be
        unloaded are skipped, and the output says why.
    #>
    param([hashtable]$State, [object[]]$Installation, [string]$What, [switch]$ClearSelection)

    # Remotely, "loaded" means loaded in ModuleManager's own session there, which this UI can't unload.
    $assemblies = @()
    if (-not $State.Remote) { $assemblies = @(Get-MMLoadedAssemblyPath) }
    $free = [System.Collections.Generic.List[string]]::new()
    $unloadable = [System.Collections.Generic.List[object]]::new()
    $blocked = [System.Collections.Generic.List[string]]::new()
    foreach ($i in $Installation) {
        if (-not $i.IsLoaded) { $free.Add($i.ModuleBase); continue }
        $reason = Get-MMUnloadBlocker -Installation $i -AssemblyPath $assemblies
        if (-not $reason -and $State.Remote) { $reason = "ModuleManager's session on $($State.Remote.Name) is using it" }
        if ($reason) { $blocked.Add("$($i.Name) $($i.Version): it is loaded in this session and $reason. Uninstall it from a new session.") }
        else { $unloadable.Add($i) }
    }

    if (-not $free.Count -and -not $unloadable.Count) {
        Set-MMTuiMessage $State "Can't uninstall $What`: $($blocked[0])" 'Yellow'
        return
    }

    $prompt = "Uninstall $What ?"
    $choices = 'y'
    if ($unloadable.Count) {
        $names = @($unloadable | Select-Object -First 2 | ForEach-Object { "$($_.Name) $($_.Version)" }) -join ', '
        if ($unloadable.Count -gt 2) { $names += " and $($unloadable.Count - 2) more" }
        if ($free.Count) {
            $prompt += " $names is loaded: y skips it, f unloads it first."
            $choices = 'yf'
        }
        else {
            $prompt += " $names is loaded: f unloads it first."
            $choices = 'f'
        }
    }
    if ($blocked.Count) { $prompt += " Skips $($blocked.Count) loaded version(s) that can't be unloaded." }

    $data = @{
        What           = $What
        Bases          = $free.ToArray()
        UnloadBases    = @($unloadable | ForEach-Object { $_.ModuleBase })
        UnloadSkipped  = @($unloadable | ForEach-Object { "$($_.Name) $($_.Version): it is loaded in this session (press f to unload and uninstall it)." })
        Blocked        = $blocked.ToArray()
        ClearSelection = [bool]$ClearSelection
    }
    Request-MMTuiConfirm $State $prompt -Data $data -Choices $choices -Action {
        param($State, $Data, $Choice)
        $run = @{ What = $Data.What; Bases = @($Data.Bases); Skipped = @($Data.Blocked); Notes = @(); ClearSelection = $Data.ClearSelection }
        if ($Choice -eq 'f') {
            $run.Notes = @(Remove-MMSessionModule -ModuleBase $Data.UnloadBases -Confirm:$false)
            $run.Bases += $Data.UnloadBases
        }
        else { $run.Skipped = @($Data.UnloadSkipped) + $run.Skipped }

        Invoke-MMTuiAction $State "Uninstalling $($Data.What)" -Data $run -Action {
            param($Data)
            foreach ($n in $Data.Notes) { Write-MMTuiOutput "  $n" 'Yellow' }
            if ($Data.Bases) { Uninstall-ManagedModule -ModuleBase $Data.Bases -Confirm:$false -Verbose }
            foreach ($s in $Data.Skipped) { Write-MMTuiOutput "  Skipped  $s" 'Yellow' }
        } -OnComplete {
            param($State, $Data)
            $State.DSelected = @{}
            if ($Data.ClearSelection) { foreach ($r in $State.Rows) { $r.Selected = $false } }
        }
    }
}
