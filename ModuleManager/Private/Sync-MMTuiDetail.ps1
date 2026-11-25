function Sync-MMTuiDetail {
    <#
    .SYNOPSIS
        Points the details view at the refreshed row after an operation, or goes back if the module is gone.
    #>
    param([hashtable]$State)
    if (-not $State.Detail) { return }
    # By Key, as different modules can share a name (see Group-MMInstallation).
    $key = $State.Detail.Name.ToLowerInvariant()
    if ($State.Detail.PSObject.Properties['Key'] -and $State.Detail.Key) { $key = $State.Detail.Key }
    $fresh = $State.Rows | Where-Object Key -EQ $key | Select-Object -First 1
    if ($fresh) {
        $State.Detail = $fresh
        $State.DCursor = [Math]::Min($State.DCursor, [Math]::Max(0, $fresh.Info.VersionCount - 1))
    }
    else {
        $State.Detail = $null
        $State.Mode = 'list'
    }
}
