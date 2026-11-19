function Get-MMTuiSelectedVersion {
    <#
    .SYNOPSIS
        Returns the installed versions selected in the terminal UI's details view, across every module.
    #>
    param([hashtable]$State)
    if (-not $State.DSelected.Count) { return }
    foreach ($r in $State.Rows) {
        foreach ($i in @($r.Info.Installations)) {
            if ($State.DSelected.ContainsKey($i.ModuleBase)) { $i }
        }
    }
}
