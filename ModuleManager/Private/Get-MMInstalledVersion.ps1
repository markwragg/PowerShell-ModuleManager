function Get-MMInstalledVersion {
    <#
    .SYNOPSIS
        Lists every installed module version on PSModulePath, quickly.

    .DESCRIPTION
        Fast scan of every module version on PSModulePath. Much quicker than
        Get-Module -ListAvailable because it only reads folder names and manifests as text.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name = '*',
        [string[]]$Scope,
        [switch]$IncludeSystem
    )

    $loaded = @{}
    foreach ($m in (Get-MMLoadedModule)) {
        if ($m.ModuleBase) { $loaded[(Get-MMPathKey $m.ModuleBase)] = $true }
    }

    foreach ($root in (Get-MMModuleRoot)) {
        if (-not $root.Exists) { continue }
        if ($Scope) { if ($Scope -notcontains $root.Scope) { continue } }
        elseif (-not $IncludeSystem -and $root.Scope -eq 'System') { continue }

        $moduleDirs = @()
        try { $moduleDirs = [IO.Directory]::GetDirectories($root.Path) }
        catch { Write-Verbose "Cannot read $($root.Path): $($_.Exception.Message)"; continue }

        foreach ($moduleDir in $moduleDirs) {
            $moduleName = [IO.Path]::GetFileName($moduleDir)
            if (-not (Test-MMNameMatch -Name $moduleName -Pattern $Name)) { continue }

            $subDirs = @()
            try { $subDirs = [IO.Directory]::GetDirectories($moduleDir) } catch { Write-Debug $_ }
            $versions = [System.Collections.Generic.List[object]]::new()
            $highest = $null
            foreach ($versionDir in $subDirs) {
                $folderVersion = $null
                if (-not [version]::TryParse([IO.Path]::GetFileName($versionDir), [ref]$folderVersion)) { continue }
                $psd1 = [IO.Path]::Combine($versionDir, "$moduleName.psd1")
                if (-not [IO.File]::Exists($psd1)) { continue }
                $versions.Add(@($folderVersion, $versionDir, $psd1))
                if ($null -eq $highest -or $folderVersion -gt $highest) { $highest = $folderVersion }
            }

            if ($versions.Count) {
                # Only the newest version's description/author/dependencies are shown or used,
                # so older versions get a lighter read (just the prerelease label).
                foreach ($v in $versions) {
                    New-MMInstalledVersion -Name $moduleName -FolderVersion $v[0] -ModuleBase $v[1] `
                        -ManifestPath $v[2] -Root $root -Loaded $loaded -Full ($v[0] -eq $highest)
                }
                continue
            }

            # Unversioned layout: <root>\<Name>\<Name>.psd1 (common for built-in modules)
            $psd1 = [IO.Path]::Combine($moduleDir, "$moduleName.psd1")
            if ([IO.File]::Exists($psd1)) {
                New-MMInstalledVersion -Name $moduleName -FolderVersion $null -ModuleBase $moduleDir `
                    -ManifestPath $psd1 -Root $root -Loaded $loaded
                continue
            }
            foreach ($ext in 'psm1', 'dll') {
                if ([IO.File]::Exists([IO.Path]::Combine($moduleDir, "$moduleName.$ext"))) {
                    New-MMInstalledVersion -Name $moduleName -FolderVersion $null -ModuleBase $moduleDir `
                        -ManifestPath $null -Root $root -Loaded $loaded
                    break
                }
            }
        }
    }
}
