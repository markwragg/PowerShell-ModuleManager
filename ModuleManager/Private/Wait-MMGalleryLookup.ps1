function Wait-MMGalleryLookup {
    <#
    .SYNOPSIS
        Waits for a repository lookup job to finish, showing a progress bar, and returns every result.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Job,
        [string]$Activity = 'Checking repositories for newer module versions'
    )
    try {
        while ($true) {
            $null = Receive-MMGalleryLookup -Job $Job
            if (Test-MMGalleryLookupComplete -Job $Job) { break }
            $percent = 0
            if ($Job.Total -gt 0) { $percent = [int](100 * $Job.Done / $Job.Total) }
            Write-Progress -Activity $Activity -Status "$($Job.Done) of $($Job.Total) modules" -PercentComplete $percent
            Start-Sleep -Milliseconds 100
        }
    }
    finally {
        Stop-MMGalleryLookup -Job $Job
        Write-Progress -Activity $Activity -Completed
    }
    $Job.Results
}
