function Start-MMTuiLookup {
    <#
    .SYNOPSIS
        Starts the background repository check for the terminal UI's modules.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    param([hashtable]$State, [switch]$Refresh)
    if ($State.Job) { Stop-MMGalleryLookup $State.Job; $State.Job = $null }
    $o = $State.Options
    if ($Refresh) { $State.Gallery = @{} }
    $requests = @(New-MMLookupRequest -ModuleInfo @($State.Rows | ForEach-Object { $_.Info }) -Repository $o.Repository -IncludePrerelease:$o.IncludePrerelease)
    if (-not $requests) { return }
    $State.Job = Start-MMGalleryLookup -Request $requests -ThrottleLimit $o.ThrottleLimit -Refresh:$Refresh
    foreach ($r in $State.Job.Results) { $State.Gallery[$r.RequestedName.ToLowerInvariant()] = $r }
    Update-MMTuiStatus $State
}
