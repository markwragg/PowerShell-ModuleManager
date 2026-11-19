function Get-MMDestinationRoot {
    <#
    .SYNOPSIS
        Works out which module folder to move an installed module version to, for a scope.

    .DESCRIPTION
        On Windows, Windows PowerShell and PowerShell 7 have their own module folders
        (...\WindowsPowerShell\Modules and ...\PowerShell\Modules). A module in one edition's folder
        moves to that edition's folder for the new scope, so the edition it was installed for still
        finds it, even if that folder isn't on this session's PSModulePath. For example, from
        PowerShell 7, a module in Program Files\WindowsPowerShell\Modules moved to CurrentUser goes
        to Documents\WindowsPowerShell\Modules, not Documents\PowerShell\Modules, which Windows
        PowerShell doesn't look in.

        Anything else goes to the first PSModulePath entry for the scope.

        Returns @{ Path; Scope; OnPath }, where OnPath says whether the folder is on PSModulePath,
        or nothing if there is no folder for the scope.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Installation,
        [Parameter(Mandatory)][ValidateSet('CurrentUser', 'AllUsers')][string]$Scope
    )

    $roots = @(Get-MMModuleRoot | Where-Object Scope -EQ $Scope)

    if (Test-MMIsWindows) {
        $edition = $null
        if ($Installation.ModuleRoot -match '[\\/]WindowsPowerShell[\\/]Modules$') { $edition = 'WindowsPowerShell' }
        elseif ($Installation.ModuleRoot -match '[\\/]PowerShell[\\/]Modules$') { $edition = 'PowerShell' }
        if ($edition) {
            $base = Get-MMKnownFolder -Name $(if ($Scope -eq 'CurrentUser') { 'Documents' } else { 'ProgramFiles' })
            if ($base) {
                $path = [IO.Path]::Combine($base, $edition, 'Modules')
                $key = Get-MMPathKey $path
                $onPath = $roots | Where-Object { (Get-MMPathKey $_.Path) -eq $key } | Select-Object -First 1
                if ($onPath) { return [pscustomobject]@{ Path = $onPath.Path; Scope = $Scope; OnPath = $true } }
                return [pscustomobject]@{ Path = $path; Scope = $Scope; OnPath = $false }
            }
        }
    }

    if ($roots) { return [pscustomobject]@{ Path = $roots[0].Path; Scope = $Scope; OnPath = $true } }
}
