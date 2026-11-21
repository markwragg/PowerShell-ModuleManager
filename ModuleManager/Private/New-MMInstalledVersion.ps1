function New-MMInstalledVersion {
    <#
    .SYNOPSIS
        Creates a ModuleManager.InstalledVersion object for one installed module version folder.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    param(
        [string]$Name,
        [AllowNull()][version]$FolderVersion,
        [string]$ModuleBase,
        [AllowNull()][string]$ManifestPath,
        [object]$Root,
        [hashtable]$Loaded,
        [bool]$Full = $true
    )

    # Parsed manifest/metadata is cached per folder for the session, invalidated when the
    # folder's last-write time changes, so rescans (e.g. after TUI actions) are fast.
    $cacheKey = "$(Get-MMPathKey $ModuleBase)|$Full"
    $stamp = [IO.Directory]::GetLastWriteTimeUtc($ModuleBase)
    $cached = $script:MMScanCache[$cacheKey]
    if ($cached -and $cached.Stamp -eq $stamp) {
        $manifest = $cached.Manifest
        $meta = $cached.Meta
    }
    else {
        $manifest = @{ ModuleVersion = $null; Prerelease = $null; Description = $null; Author = $null; ProjectUri = $null; RequiredModules = @(); Dependencies = @() }
        if ($ManifestPath) { $manifest = Read-MMManifest -Path $ManifestPath -Full:$Full }
        $meta = Read-MMInstallMetadata -ModuleBase $ModuleBase
        $script:MMScanCache[$cacheKey] = @{ Stamp = $stamp; Manifest = $manifest; Meta = $meta }
    }

    $version = $FolderVersion
    if (-not $version -and $manifest.ModuleVersion) {
        $parsed = $null
        if ([version]::TryParse($manifest.ModuleVersion, [ref]$parsed)) { $version = $parsed }
    }
    if (-not $version) { $version = [version]'0.0' }

    # The package manager's record (with version ranges) is authoritative. Modules copied in by hand
    # fall back to the manifest, which is only read in full for the newest version of each module.
    $dependencies = $meta.Dependencies
    $dependenciesKnown = $null -ne $dependencies -or $Full -or -not $ManifestPath
    if ($null -eq $dependencies) { $dependencies = $manifest.Dependencies }
    $projectUri = $meta.ProjectUri
    if (-not $projectUri) { $projectUri = $manifest.ProjectUri }

    $pre = $manifest.Prerelease
    $display = [string]$version
    if ($pre) { $display = "$display-$pre" }

    [pscustomobject]@{
        PSTypeName      = 'ModuleManager.InstalledVersion'
        Name            = $Name
        Version         = $display
        ModuleVersion   = $version
        Prerelease      = $pre
        Scope           = $Root.Scope
        Repository      = $meta.Repository
        InstalledDate   = $meta.InstalledDate
        IsManaged       = $meta.IsManaged
        IsLoaded        = $Loaded.ContainsKey((Get-MMPathKey $ModuleBase))
        ModuleBase      = $ModuleBase
        ModuleRoot      = $Root.Path
        RootOrder       = $Root.Order
        Description     = $manifest.Description
        Author          = $manifest.Author
        RequiredModules = $manifest.RequiredModules
        Dependencies    = @($dependencies)
        # False when the dependencies weren't read: for an older version with no install record,
        # whose manifest is only read in part.
        DependenciesKnown = $dependenciesKnown
        ProjectUri      = $projectUri
        SourceLocation  = $meta.SourceLocation
        # The package manager that installed this version (PSResourceGet or PowerShellGet), if known.
        InstalledBy     = $meta.InstalledBy
    }
}
