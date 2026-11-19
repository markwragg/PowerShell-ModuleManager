function Request-MMTuiUninstallVersion {
    <#
    .SYNOPSIS
        Asks to uninstall the versions selected in the details view (of any module), or the one under the cursor, then uninstalls them.
    #>
    param([hashtable]$State)
    if (Test-MMTuiBusy $State) { return }
    # The versions selected in the details view, of this and any other module; with none, the
    # version under the cursor.
    $targets = @(Get-MMTuiSelectedVersion $State)
    if (-not $targets) { $targets = @(@($State.Detail.Info.Installations)[$State.DCursor]) }
    Request-MMTuiUninstallInstallation $State -Installation $targets -What (Format-MMTuiTarget $State $targets)
}
