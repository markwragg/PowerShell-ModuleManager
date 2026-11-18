function Group-MMInstallation {
    <#
    .SYNOPSIS
        Groups installed versions into one ModuleManager.ModuleInfo object per module.
    #>
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Installation)

    if (-not $Installation) { return }
    $groups = [ordered]@{}
    foreach ($i in $Installation) {
        $key = $i.Name.ToLowerInvariant()
        if (-not $groups.Contains($key)) { $groups[$key] = [System.Collections.Generic.List[object]]::new() }
        $groups[$key].Add($i)
    }
    $modules = foreach ($key in $groups.Keys) {
        $sorted = @(Get-MMSortedInstallation $groups[$key].ToArray())
        $latest = $sorted[0]
        $scopes = [System.Collections.Generic.List[string]]::new()
        $anyLoaded = $false
        foreach ($s in $sorted) {
            if (-not $scopes.Contains($s.Scope)) { $scopes.Add($s.Scope) }
            if ($s.IsLoaded) { $anyLoaded = $true }
        }
        [pscustomobject]@{
            PSTypeName    = 'ModuleManager.ModuleInfo'
            Name          = $latest.Name
            Version       = $latest.Version
            ModuleVersion = $latest.ModuleVersion
            Prerelease    = $latest.Prerelease
            Versions      = @($sorted | ForEach-Object { $_.Version })
            VersionCount  = $sorted.Count
            Scope         = $scopes -join ', '
            Repository    = $latest.Repository
            IsManaged     = $latest.IsManaged
            IsLoaded      = $anyLoaded
            Path          = $latest.ModuleBase
            Description   = $latest.Description
            Dependencies  = $latest.Dependencies
            Installations = $sorted
        }
    }
    $modules | Sort-Object -Property Name
}
