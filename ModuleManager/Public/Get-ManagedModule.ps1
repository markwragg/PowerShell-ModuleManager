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

    .EXAMPLE
        Get-ManagedModule

        Lists all user-installed modules.

    .EXAMPLE
        Get-ManagedModule -MultipleVersions | Sort-Object VersionCount -Descending

        Shows which modules have accumulated the most old versions.

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

        [switch]$AllVersions
    )

    begin { $names = [System.Collections.Generic.List[string]]::new() }
    process { foreach ($n in $Name) { $names.Add($n) } }
    end {
        if ($names.Count -eq 0) { $names.Add('*') }
        $installs = @(Get-MMInstalledVersion -Name $names -Scope $Scope -IncludeSystem:$IncludeSystem)
        $modules = @(Group-MMInstallation -Installation $installs)
        if ($MultipleVersions) { $modules = @($modules | Where-Object VersionCount -GT 1) }

        if ($AllVersions) { $modules | ForEach-Object { $_.Installations } }
        else { $modules }
    }
}
