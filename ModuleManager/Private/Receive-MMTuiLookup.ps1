function Receive-MMTuiLookup {
    <#
    .SYNOPSIS
        Applies finished repository lookups to the terminal UI rows.

    .DESCRIPTION
        Returns $true if anything changed.
    #>
    param([hashtable]$State)
    if (-not $State.Job) { return $false }
    $new = @(Receive-MMGalleryLookup -Job $State.Job)
    foreach ($r in $new) { $State.Gallery[$r.RequestedName.ToLowerInvariant()] = $r }
    $changed = $new.Count -gt 0
    $finished = Test-MMGalleryLookupComplete -Job $State.Job
    if ($finished) { $State.Job = $null; $changed = $true }
    if ($changed) { Update-MMTuiStatus $State }
    if ($finished) {
        $count = @($State.Rows | Where-Object Status -EQ 'UpdateAvailable').Count
        $errors = @($State.Rows | Where-Object Status -EQ 'Error').Count
        $text = "Update check complete: $count update(s) available."
        if ($errors) { $text += " $errors lookup(s) failed." }
        Set-MMTuiMessage $State $text 'Green'
    }
    $changed
}
