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
    if ($c -gt 0) { return 'UpdateAvailable' }
    # The newest installed version has been unlisted (the module itself is still listed). An update
    # matters more, but this says more than up to date, or newer than the repository (which is what
    # it looks like when the newest version was the one unlisted).
    if ($Result.PSObject.Properties['UnlistedVersions'] -and @($Result.UnlistedVersions) -contains [string]$Module.Version) { return 'VersionUnlisted' }
    if ($c -lt 0) { 'LocalNewer' } else { 'UpToDate' }
}
