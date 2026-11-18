function Get-MMNewestVersionMap {
    <#
    .SYNOPSIS
        Returns the newest installed version of each module, read from folder names only.

    .DESCRIPTION
        Returns a hashtable of lower-case module name -> @{ Name; Version } giving the highest
        version folder of each module outside the System scope. Only folder names are read, so it is
        cheap enough to run after every install to see what that install pulled in as dependencies.
    #>
    [CmdletBinding()]
    param()

    $map = @{}
    foreach ($root in (Get-MMModuleRoot)) {
        if (-not $root.Exists -or $root.Scope -eq 'System') { continue }
        $moduleDirs = @()
        try { $moduleDirs = [IO.Directory]::GetDirectories($root.Path) } catch { Write-Debug $_; continue }
        foreach ($moduleDir in $moduleDirs) {
            $name = [IO.Path]::GetFileName($moduleDir)
            $subDirs = @()
            try { $subDirs = [IO.Directory]::GetDirectories($moduleDir) } catch { Write-Debug $_; continue }
            foreach ($versionDir in $subDirs) {
                $v = $null
                if (-not [version]::TryParse([IO.Path]::GetFileName($versionDir), [ref]$v)) { continue }
                $key = $name.ToLowerInvariant()
                if (-not $map.ContainsKey($key) -or $v -gt $map[$key].Version) { $map[$key] = @{ Name = $name; Version = $v } }
            }
        }
    }
    $map
}
