function Get-ManagedModule {
    <#
    .SYNOPSIS
        Lists the PowerShell modules installed on this machine, one row per module.

    .DESCRIPTION
        Scans every folder on $env:PSModulePath and summarises each module: the newest
        installed version, every other installed version, the scope it is installed in,
        the repository it came from and whether it is loaded in the current session.

        The scan reads folders and manifests directly, so it is much faster than
        Get-Module -ListAvailable.

        Modules that ship with PowerShell or Windows (scope 'System') are hidden unless
        -IncludeSystem or -Scope System is used.

        With -IncludeSize, each module also has its size on disk (SizeMB, all its versions) and
        the space removing its old versions would free (ReclaimableMB): the versions
        Uninstall-ManagedModule -OldVersions would remove, so not the newest, versions that ship
        with PowerShell, versions loaded in this session, or old versions other installed modules
        depend on.

    .PARAMETER Name
        One or more module names. Wildcards are supported.

    .PARAMETER Scope
        Only include installations in these scopes: CurrentUser, AllUsers, System, Other.

    .PARAMETER IncludeSystem
        Include modules that ship with PowerShell or Windows.

    .PARAMETER MultipleVersions
        Only return modules that have more than one version installed.

    .PARAMETER AllVersions
        Return one object per installed version instead of one per module.

    .PARAMETER IncludeSize
        Add each module's size on disk (SizeMB) and how much removing its old versions would free
        (ReclaimableMB). With -AllVersions, adds each version's size (SizeMB). This reads every
        file of every version, so it takes longer, most of all the first time.

    .EXAMPLE
        Get-ManagedModule

        Lists all user-installed modules.

    .EXAMPLE
        Get-ManagedModule -MultipleVersions | Sort-Object VersionCount -Descending

        Shows which modules have accumulated the most old versions.

    .EXAMPLE
        Get-ManagedModule -MultipleVersions -IncludeSize | Sort-Object ReclaimableMB -Descending

        Shows how much space removing each module's old versions would free, largest first.

    .EXAMPLE
        (Get-ManagedModule -IncludeSize | Measure-Object ReclaimableMB -Sum).Sum

        Totals the space Uninstall-ManagedModule -OldVersions would free, in MB.

    .EXAMPLE
        Get-ManagedModule Az.* -AllVersions

        Lists every installed version of the Az modules, one row per version.
    #>
    [CmdletBinding()]
    [OutputType('ModuleManager.ModuleInfo', 'ModuleManager.InstalledVersion')]
    [Alias('Get-ModuleInventory')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [SupportsWildcards()]
        [string[]]$Name = '*',

        [ValidateSet('CurrentUser', 'AllUsers', 'System', 'Other')]
        [string[]]$Scope,

        [switch]$IncludeSystem,

        [switch]$MultipleVersions,

        [switch]$AllVersions,

        [switch]$IncludeSize
    )

    begin { $names = [System.Collections.Generic.List[string]]::new() }
    process { foreach ($n in $Name) { $names.Add($n) } }
    end {
        if ($names.Count -eq 0) { $names.Add('*') }
        $installs = @(Get-MMInstalledVersion -Name $names -Scope $Scope -IncludeSystem:$IncludeSystem)
        $modules = @(Group-MMInstallation -Installation $installs)
        if ($MultipleVersions) { $modules = @($modules | Where-Object VersionCount -GT 1) }

        if ($IncludeSize -and $modules) {
            # Each folder is read once, however many times it's counted.
            $bytes = @{}
            foreach ($i in @($modules | ForEach-Object { $_.Installations })) {
                $key = Get-MMPathKey $i.ModuleBase
                if (-not $bytes.ContainsKey($key)) { $bytes[$key] = [long](Get-MMFolderSize $i.ModuleBase) }
                $i | Add-Member -NotePropertyName SizeMB -NotePropertyValue ([Math]::Round($bytes[$key] / 1MB, 1)) -Force
            }

            # What Uninstall-ManagedModule -OldVersions would remove. Dependencies are checked
            # against every installed module, so this needs them all, not just the ones listed.
            $old = Get-MMOldVersion -Installation @(Get-MMInstalledVersion -IncludeSystem) -Name $names.ToArray() -Scope $Scope
            $reclaimable = @{}
            foreach ($i in $old.Removable) {
                $key = Get-MMPathKey $i.ModuleBase
                if (-not $bytes.ContainsKey($key)) { $bytes[$key] = [long](Get-MMFolderSize $i.ModuleBase) }
                $moduleKey = $i.Name.ToLowerInvariant()
                $reclaimable[$moduleKey] = [long]$reclaimable[$moduleKey] + $bytes[$key]
            }

            foreach ($m in $modules) {
                $total = 0L
                foreach ($i in $m.Installations) { $total += $bytes[(Get-MMPathKey $i.ModuleBase)] }
                $m | Add-Member -NotePropertyName SizeMB -NotePropertyValue ([Math]::Round($total / 1MB, 1)) -Force
                $m | Add-Member -NotePropertyName ReclaimableMB -Force -NotePropertyValue (
                    [Math]::Round([long]$reclaimable[$m.Name.ToLowerInvariant()] / 1MB, 1))
                # Shown with the size columns (see ModuleManager.Format.ps1xml).
                $m.PSObject.TypeNames.Insert(0, 'ModuleManager.ModuleInfo.Size')
            }
        }

        if ($AllVersions) { $modules | ForEach-Object { $_.Installations } }
        else { $modules }
    }
}
