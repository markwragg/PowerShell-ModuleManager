function Request-MMTuiUninstallVersion {
    <#
    .SYNOPSIS
        Asks to uninstall the selected versions in the details view, then uninstalls them.
    #>
    param([hashtable]$State)
    if (Test-MMTuiBusy $State) { return }
    $installs = @($State.Detail.Info.Installations)
    $bases = @($State.DSelected.Keys)
    if (-not $bases) { $bases = @($installs[$State.DCursor].ModuleBase) }
    $versions = @($installs | Where-Object { $bases -contains $_.ModuleBase } | ForEach-Object { $_.Version })
    $data = @{ Bases = $bases; What = "$($State.Detail.Name) $($versions -join ', ')" }
    Request-MMTuiConfirm $State "Uninstall $($data.What) ?" -Data $data -Action {
        param($State, $Data)
        Invoke-MMTuiAction $State "Uninstalling $($Data.What)" -Data $Data -Action {
            param($Data)
            Uninstall-ManagedModule -ModuleBase $Data.Bases -Confirm:$false -Verbose
        }
    }
}
