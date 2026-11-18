function Request-MMTuiRemoveOld {
    <#
    .SYNOPSIS
        Asks to remove the old versions of the targeted modules, then removes them.
    #>
    param([hashtable]$State, [object[]]$Rows)
    if (Test-MMTuiBusy $State) { return }
    $rows = @($Rows | Where-Object { $_.Info.VersionCount -gt 1 })
    if (-not $rows) { Set-MMTuiMessage $State 'Nothing to remove: only one version installed.' 'Yellow'; return }
    $old = 0; foreach ($r in $rows) { $old += $r.Info.VersionCount - 1 }
    $data = @{ Names = @($rows | ForEach-Object { $_.Name }) }
    Request-MMTuiConfirm $State "Remove $old old version(s) of $($rows.Count) module(s), keeping the newest?" -Data $data -Action {
        param($State, $Data)
        Invoke-MMTuiAction $State "Removing old versions of $($Data.Names.Count) module(s)" -Data $Data -Action {
            param($Data)
            Remove-OldModuleVersion -Name $Data.Names -Keep 1 -Confirm:$false -Verbose
        } -OnComplete {
            param($State)
            foreach ($r in $State.Rows) { $r.Selected = $false }
        }
    }
}
