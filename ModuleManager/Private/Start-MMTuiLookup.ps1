function Start-MMTuiLookup {
    <#
    .SYNOPSIS
        Starts the background repository check for the terminal UI's modules.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    param([hashtable]$State, [switch]$Refresh)
    Stop-MMTuiLookup $State
    $o = $State.Options
    if ($Refresh) { $State.Gallery = @{} }

    if ($State.Remote) {
        # Look up from the remote computer, which may use repositories this one doesn't know,
        # and send back each result as it arrives.
        $modules = @($State.Rows | ForEach-Object { [pscustomobject]@{ Name = $_.Info.Name; Repository = $_.Info.Repository; Prerelease = $_.Info.Prerelease; Version = $_.Info.Version } })
        if (-not $modules) { return }
        $command = Start-MMRemoteCommand -Remote $State.Remote -ArgumentList (@(, $modules) + @($o.Repository, [bool]$o.IncludePrerelease, [bool]$Refresh, $o.ThrottleLimit)) -ScriptBlock {
            param($Modules, $Repository, $IncludePrerelease, $Refresh, $ThrottleLimit)
            $requests = @(New-MMLookupRequest -ModuleInfo $Modules -Repository $Repository -IncludePrerelease:$IncludePrerelease)
            $job = Start-MMGalleryLookup -Request $requests -ThrottleLimit $ThrottleLimit -Refresh:$Refresh
            try {
                foreach ($r in @($job.Results)) { [System.Management.Automation.PSSerializer]::Serialize($r, 5) }
                while ($true) {
                    foreach ($r in @(Receive-MMGalleryLookup -Job $job)) { [System.Management.Automation.PSSerializer]::Serialize($r, 5) }
                    if (Test-MMGalleryLookupComplete -Job $job) { break }
                    Start-Sleep -Milliseconds 100
                }
            }
            finally { Stop-MMGalleryLookup -Job $job }
        }
        $State.Job = [pscustomobject]@{ Remote = $true; Command = $command; Total = $modules.Count; Done = 0 }
        return
    }

    $requests = @(New-MMLookupRequest -ModuleInfo @($State.Rows | ForEach-Object { $_.Info }) -Repository $o.Repository -IncludePrerelease:$o.IncludePrerelease)
    if (-not $requests) { return }
    $State.Job = Start-MMGalleryLookup -Request $requests -ThrottleLimit $o.ThrottleLimit -Refresh:$Refresh
    foreach ($r in $State.Job.Results) { $State.Gallery[$r.RequestedName.ToLowerInvariant()] = $r }
    Update-MMTuiStatus $State
}
