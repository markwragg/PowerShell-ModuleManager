function Test-MMGalleryLookupComplete {
    <#
    .SYNOPSIS
        Returns $true when every lookup in a repository lookup job has been collected.
    #>
    param([Parameter(Mandatory)][object]$Job)
    -not ($Job.Tasks | Where-Object { -not $_.Collected })
}
