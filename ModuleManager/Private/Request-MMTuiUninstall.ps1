function Request-MMTuiUninstall {
    <#
    .SYNOPSIS
        Asks to uninstall the targeted modules (every version), then uninstalls them.
    #>
    param([hashtable]$State)
    if (Test-MMTuiBusy $State) { return }
    $rows = @(Get-MMTuiTarget $State)
    if (-not $rows) { return }
    $installs = @($rows | ForEach-Object { $_.Info.Installations })
    if ($rows.Count -eq 1) { $what = "$($rows[0].Name) ($($installs.Count) version(s))" }
    else { $what = "$($rows.Count) modules ($($installs.Count) versions)" }
    $data = @{ Bases = @($installs | ForEach-Object { $_.ModuleBase }); What = $what }
    Request-MMTuiConfirm $State "Uninstall $what ?" -Data $data -Action {
        param($State, $Data)
        Invoke-MMTuiAction $State "Uninstalling $($Data.What)" -Data $Data -Action {
            param($Data)
            Uninstall-ManagedModule -ModuleBase $Data.Bases -Confirm:$false -Verbose
        } -OnComplete {
            param($State)
            foreach ($r in $State.Rows) { $r.Selected = $false }
        }
    }
}
