function Group-MMInstallation {
    <#
    .SYNOPSIS
        Groups installed versions into one ModuleManager.ModuleInfo object per module.

    .DESCRIPTION
        Versions of the same name are one module, except where their GUIDs show they're different
        modules that happen to share a name (such as a module that ships with Windows and a
        community module of the same name from the PowerShell Gallery):
          - Versions installed from a repository are one module whatever their GUIDs, as a
            package name belongs to one publisher, and some publishers (Az's, for one) change a
            module's GUID between versions.
          - Other versions (shipped with Windows or PowerShell, or copied in by hand) join the
            module with their GUID, or start a module of their own.
          - Versions with no GUID join the main module.
        The main module of a name is the one installed from a repository, or failing that the one
        with the newest version. Its Key is its lower-case name; another module of the same name
        has its GUID added ('name|guid'), so Key is unique.
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
        foreach ($set in (Split-MMInstallationSet $groups[$key].ToArray())) {
            $sorted = @(Get-MMSortedInstallation $set.Items.ToArray())
            $latest = $sorted[0]
            $scopes = [System.Collections.Generic.List[string]]::new()
            $anyLoaded = $false
            $projectUri = $null
            foreach ($s in $sorted) {
                if (-not $scopes.Contains($s.Scope)) { $scopes.Add($s.Scope) }
                if ($s.IsLoaded) { $anyLoaded = $true }
                # The newest version's, or failing that the newest one that has one.
                if (-not $projectUri -and $s.PSObject.Properties['ProjectUri'] -and $s.ProjectUri) { $projectUri = $s.ProjectUri }
            }
            $moduleKey = $key
            if (-not $set.Main) { $moduleKey = "$key|$(@($set.Guids)[0])" }
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
                Guid          = $(if ($latest.PSObject.Properties['Guid']) { $latest.Guid })
                # Every GUID its versions have (normalised), to match it with a repository's module.
                Guids         = [string[]]@($set.Guids)
                # Unique, unlike Name: see the description.
                Key           = $moduleKey
                ProjectUri    = $projectUri
                Dependencies  = $latest.Dependencies
                Installations = $sorted
            }
        }
    }
    # The main module of a name first (its Key is the shortest).
    $modules | Sort-Object -Property Name, Key
}
