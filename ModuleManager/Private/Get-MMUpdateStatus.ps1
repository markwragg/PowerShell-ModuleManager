function Get-MMUpdateStatus {
    <#
    .SYNOPSIS
        Compares an installed module with a repository lookup result and returns its update status.
    #>
    param([object]$Module, [object]$Result)
    if (-not $Result) { return 'Unknown' }
    switch ($Result.Status) {
        'NotFound' { return 'NotInRepository' }
        'Unlisted' { return 'Unlisted' }
        'Error' { return 'Error' }
    }
    $c = Compare-MMVersion $Result.ModuleVersion $Result.PrereleaseLabel $Module.ModuleVersion $Module.Prerelease
    if ($c -gt 0) { 'UpdateAvailable' } elseif ($c -lt 0) { 'LocalNewer' } else { 'UpToDate' }
}
