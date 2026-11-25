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
    # A module of the same name with none of the installed module's GUIDs is someone else's module
    # (such as a community module named after one that ships with Windows), so the installed module
    # isn't in the repository. Not checked when it was installed from that repository: the package
    # is the same one, and some publishers (Az's, for one) change a module's GUID between versions.
    # When either side's GUID is unknown (PSResourceGet doesn't report it), they're taken to be the
    # same module.
    $fromRepository = $Module.PSObject.Properties['Repository'] -and $Module.Repository -and
        $Result.PSObject.Properties['Repository'] -and $Module.Repository -eq $Result.Repository
    $repositoryGuid = [guid]::Empty
    if (-not $fromRepository -and $Result.PSObject.Properties['Guid'] -and [guid]::TryParse([string]$Result.Guid, [ref]$repositoryGuid)) {
        $installed = @()
        if ($Module.PSObject.Properties['Guids'] -and @($Module.Guids).Count) { $installed = @($Module.Guids) }
        elseif ($Module.PSObject.Properties['Guid']) { $installed = @($Module.Guid) }
        $known = @(foreach ($text in $installed) { $g = [guid]::Empty; if ([guid]::TryParse([string]$text, [ref]$g)) { $g } })
        if ($known.Count -and $known -notcontains $repositoryGuid) { return 'NotInRepository' }
    }
    $c = Compare-MMVersion $Result.ModuleVersion $Result.PrereleaseLabel $Module.ModuleVersion $Module.Prerelease
    if ($c -gt 0) { return 'UpdateAvailable' }
    # The newest installed version has been unlisted (the module itself is still listed). An update
    # matters more, but this says more than up to date, or newer than the repository (which is what
    # it looks like when the newest version was the one unlisted).
    if ($Result.PSObject.Properties['UnlistedVersions'] -and @($Result.UnlistedVersions) -contains [string]$Module.Version) { return 'VersionUnlisted' }
    if ($c -lt 0) { 'LocalNewer' } else { 'UpToDate' }
}
