function Get-MMOldVersion {
    <#
    .SYNOPSIS
        Works out which old versions of the named modules Uninstall-ManagedModule -OldVersions would remove.

    .DESCRIPTION
        The old versions of a module are all but its newest -Keep, counting every scope. Of those,
        only versions in -Scope (when given) are considered, and these are held back instead of
        being returned as Removable:
          - System: versions that ship with PowerShell or Windows (never removed).
          - Loaded: versions loaded in this session (removable with -Force).
          - Required: versions other installed modules depend on, as Get-MMRequiredInstallation
            returns them, with who needs them (removable with -Force).

        Writes no messages, so it can also be used to report what a cleanup would free
        (Get-ManagedModule -IncludeSize); Remove-MMOldVersion says why versions are kept.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Installation,
        [string[]]$Name = '*',
        [int]$Keep = 1,
        [string[]]$Scope,
        [switch]$Force
    )

    $result = [pscustomobject]@{ Removable = @(); System = @(); Loaded = @(); Required = @() }
    $modules = @(Group-MMInstallation -Installation @($Installation | Where-Object { Test-MMNameMatch $_.Name $Name }))

    $candidates = [System.Collections.Generic.List[object]]::new()
    $system = [System.Collections.Generic.List[object]]::new()
    $loaded = [System.Collections.Generic.List[object]]::new()
    foreach ($m in $modules) {
        if ($m.VersionCount -le $Keep) { continue }
        foreach ($i in @($m.Installations | Select-Object -Skip $Keep)) {
            if ($Scope -and $Scope -notcontains $i.Scope) { continue }
            if ($i.Scope -eq 'System') { $system.Add($i); continue }
            if ($i.IsLoaded -and -not $Force) { $loaded.Add($i); continue }
            $candidates.Add($i)
        }
    }
    $result.System = $system.ToArray()
    $result.Loaded = $loaded.ToArray()
    if (-not $candidates.Count) { return $result }

    # Keep old versions that other installed modules still depend on, such as the exact Az.*
    # versions each older Az rollup pins.
    $requiredKeys = @{}
    if (-not $Force) {
        $result.Required = @(Get-MMRequiredInstallation -Removing $candidates.ToArray() -AllInstallation $Installation)
        foreach ($k in $result.Required) { $requiredKeys[(Get-MMPathKey $k.Installation.ModuleBase)] = $true }
    }
    $result.Removable = @($candidates | Where-Object { -not $requiredKeys.ContainsKey((Get-MMPathKey $_.ModuleBase)) })
    $result
}
