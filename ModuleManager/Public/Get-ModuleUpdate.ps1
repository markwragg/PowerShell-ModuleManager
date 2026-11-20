function Get-ModuleUpdate {
    <#
    .SYNOPSIS
        Compares the installed version of each module with the latest version in its repository.

    .DESCRIPTION
        For every installed module, looks up the newest version available in the repository
        it was installed from (or PSGallery for modules installed manually) and reports
        whether an update is available.

        Lookups run in parallel and are cached for 30 minutes, so running this again, or
        running Update-ManagedModule afterwards, doesn't query the repository again. Use
        -Refresh to bypass the cache.

        Status values:
          UpdateAvailable  A newer version exists in the repository.
          UpToDate         The newest installed version matches the repository.
          LocalNewer       The installed version is newer than the repository version.
          NotInRepository  The module was not found in the repository.
          Unlisted         The module is in the repository but its publisher has unlisted it
                           (usually because it is deprecated), so it can't be updated.
          Error            The repository could not be queried.

    .PARAMETER Name
        One or more module names. Wildcards are supported. Accepts pipeline input from
        Get-ModuleInventory.

    .PARAMETER Scope
        Only check modules installed in these scopes.

    .PARAMETER Repository
        Query this repository for every module instead of the one each was installed from.

    .PARAMETER IncludePrerelease
        Consider prerelease versions when finding the latest version. Modules whose newest
        installed version is a prerelease always consider prereleases.

    .PARAMETER Outdated
        Only return modules with an update available.

    .PARAMETER Refresh
        Ignore cached results and query the repository again.

    .PARAMETER IncludeSystem
        Include modules that ship with PowerShell or Windows.

    .PARAMETER ThrottleLimit
        The maximum number of concurrent repository queries. Queries made with PowerShellGet's own commands (for a repository that isn't a NuGet v2 feed, or a feed that can't be reached) still run one at a time.

    .EXAMPLE
        Get-ModuleUpdate -Outdated

        Lists only the installed modules that have a newer version available in their repository.

    .EXAMPLE
        Get-ModuleUpdate Pester, PSReadLine

        Compares the installed versions of Pester and PSReadLine with the latest available.

    .EXAMPLE
        Get-ModuleUpdate -Outdated | Update-ManagedModule -WhatIf

        Shows which updates would be installed, without installing anything.
    #>
    [CmdletBinding()]
    [OutputType('ModuleManager.ModuleUpdate')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [SupportsWildcards()]
        [string[]]$Name = '*',

        [ValidateSet('CurrentUser', 'AllUsers', 'System', 'Other')]
        [string[]]$Scope,

        [string]$Repository,

        [switch]$IncludePrerelease,

        [switch]$Outdated,

        [switch]$Refresh,

        [switch]$IncludeSystem,

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 16
    )

    begin { $names = [System.Collections.Generic.List[string]]::new() }
    process { foreach ($n in $Name) { $names.Add($n) } }
    end {
        if ($names.Count -eq 0) { $names.Add('*') }
        $modules = @(Group-MMInstallation -Installation @(Get-MMInstalledVersion -Name $names -Scope $Scope -IncludeSystem:$IncludeSystem))
        if (-not $modules) { return }

        $requests = @(New-MMLookupRequest -ModuleInfo $modules -Repository $Repository -IncludePrerelease:$IncludePrerelease)
        $job = Start-MMGalleryLookup -Request $requests -ThrottleLimit $ThrottleLimit -Refresh:$Refresh
        $results = @(Wait-MMGalleryLookup -Job $job)

        $byKey = @{}
        foreach ($r in $results) { $byKey[(Get-MMCacheKey $r.RequestedName $r.Repository $r.Prerelease)] = $r }

        for ($i = 0; $i -lt $modules.Count; $i++) {
            $m = $modules[$i]
            $req = $requests[$i]
            $result = $byKey[(Get-MMCacheKey $req.Name $req.Repository $req.Prerelease)]
            if (-not $result) {
                $result = [pscustomobject]@{
                    Status = 'Error'; Version = $null; PublishedDate = $null; Dependencies = @()
                    Error = 'The repository lookup returned no result.'
                }
            }
            $status = Get-MMUpdateStatus -Module $m -Result $result
            if ($Outdated -and $status -ne 'UpdateAvailable') { continue }
            $latestDeps = @()
            if ($result -and $result.PSObject.Properties['Dependencies']) { $latestDeps = @($result.Dependencies) }

            [pscustomobject]@{
                PSTypeName       = 'ModuleManager.ModuleUpdate'
                Name             = $m.Name
                InstalledVersion = $m.Version
                LatestVersion    = $result.Version
                Status           = $status
                Repository       = $req.Repository
                Scope            = $m.Scope
                VersionCount     = $m.VersionCount
                PublishedDate    = $result.PublishedDate
                IsLoaded         = $m.IsLoaded
                Path             = $m.Path
                Error            = $result.Error
                Dependencies     = $m.Dependencies
                LatestDependencies = $latestDeps
                Installations    = $m.Installations
            }
        }
    }
}
