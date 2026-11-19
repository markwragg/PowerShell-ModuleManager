function Request-MMTuiUninstall {
    <#
    .SYNOPSIS
        Asks to uninstall everything selected (modules and versions), or the module under the cursor, then uninstalls it.
    #>
    param([hashtable]$State)
    if (Test-MMTuiBusy $State) { return }
    # Everything selected: whole modules, and versions selected in the details view (of any
    # module). With nothing selected, the module (or collapsed family) under the cursor.
    $rows = @($State.Rows | Where-Object Selected)
    $versions = @(Get-MMTuiSelectedVersion $State)
    if (-not $rows -and -not $versions) { $rows = @(Get-MMTuiTarget $State) }
    $seen = @{}
    $installs = @(foreach ($i in @(@($rows | ForEach-Object { $_.Info.Installations }) + $versions)) {
            if ($i -and -not $seen.ContainsKey($i.ModuleBase)) { $seen[$i.ModuleBase] = $true; $i }
        })
    if (-not $installs) { return }
    Request-MMTuiUninstallInstallation $State -Installation $installs -What (Format-MMTuiTarget $State $installs) -ClearSelection
}
