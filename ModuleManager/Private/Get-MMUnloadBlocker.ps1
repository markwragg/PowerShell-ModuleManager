function Get-MMUnloadBlocker {
    <#
    .SYNOPSIS
        Returns why a loaded module version can't safely be unloaded so it can be uninstalled, or $null if it can.

    .DESCRIPTION
        Remove-Module doesn't unload .NET assemblies, and on Windows a loaded assembly stays locked
        until PowerShell exits, so deleting a binary module's folder would fail part-way and leave
        it half removed. ModuleManager itself (the terminal UI imports it to run operations) and
        the package manager it installs and removes modules with can't be unloaded either.

        -AssemblyPath is the paths of the assemblies loaded in this session; pass it when checking
        several versions so they are only listed once.
    #>
    param(
        [Parameter(Mandatory)][object]$Installation,
        [string[]]$AssemblyPath = @(Get-MMLoadedAssemblyPath)
    )
    $name = $Installation.Name
    if ($name -eq 'ModuleManager') { return 'ModuleManager is running this UI' }
    if ($name -in 'Microsoft.PowerShell.PSResourceGet', 'PowerShellGet', 'PackageManagement') {
        return 'ModuleManager uses it to install and remove modules'
    }
    foreach ($path in $AssemblyPath) {
        if (Test-MMPathUnder -Path $path -Base $Installation.ModuleBase) {
            return 'it has .NET assemblies loaded, which stay locked until PowerShell exits'
        }
    }
    $null
}
