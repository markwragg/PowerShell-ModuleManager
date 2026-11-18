function Sync-MMTuiDetail {
    <#
    .SYNOPSIS
        Points the details view at the refreshed row after an operation, or goes back if the module is gone.
    #>
    param([hashtable]$State)
    if (-not $State.Detail) { return }
    $fresh = $State.Rows | Where-Object Name -EQ $State.Detail.Name | Select-Object -First 1
    $State.DSelected = @{}
    if ($fresh) {
        $State.Detail = $fresh
        $State.DCursor = [Math]::Min($State.DCursor, [Math]::Max(0, $fresh.Info.VersionCount - 1))
    }
    else {
        $State.Detail = $null
        $State.Mode = 'list'
    }
}
