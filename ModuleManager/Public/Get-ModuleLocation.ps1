function Get-ModuleLocation {
    <#
    .SYNOPSIS
        Shows where modules are installed on disk.

    .DESCRIPTION
        By default returns one object per installed module version, with its scope, the
        folder it lives in and the PSModulePath entry that contains it.

        With -Summary, returns one object per PSModulePath entry in search order, with
        the number of modules and versions in each. Use -IncludeSize to add disk usage.

    .PARAMETER Name
        One or more module names. Wildcards are supported.

    .PARAMETER Scope
        Only include these scopes: CurrentUser, AllUsers, System, Other.

    .PARAMETER Summary
        Summarise by PSModulePath entry instead of listing each module version.

    .PARAMETER IncludeSize
        Calculate the size on disk of each module version (or each path, with -Summary).
        This reads every file, so it can be slow.

    .PARAMETER IncludeSystem
        Include modules that ship with PowerShell or Windows. -Summary always includes them.

    .EXAMPLE
        Get-ModuleLocation Pester

        Lists every installed Pester version and where it is.

    .EXAMPLE
        Get-ModuleLocation -Summary -IncludeSize

        Shows how many modules and versions are in each PSModulePath location, and the disk space they use.

    .EXAMPLE
        Get-ModuleInventory | Where-Object { ($_.Installations.ModuleRoot | Select-Object -Unique).Count -gt 1 }

        Finds modules installed in more than one PSModulePath location.
    #>
    [CmdletBinding()]
    [OutputType('ModuleManager.InstalledVersion', 'ModuleManager.ModuleRoot')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [SupportsWildcards()]
        [string[]]$Name = '*',

        [ValidateSet('CurrentUser', 'AllUsers', 'System', 'Other')]
        [string[]]$Scope,

        [switch]$Summary,

        [switch]$IncludeSize,

        [switch]$IncludeSystem
    )

    begin { $names = [System.Collections.Generic.List[string]]::new() }
    process { foreach ($n in $Name) { $names.Add($n) } }
    end {
        if ($names.Count -eq 0) { $names.Add('*') }

        if ($Summary) {
            $installs = @(Get-MMInstalledVersion -Name $names -Scope $Scope -IncludeSystem)
            foreach ($root in (Get-MMModuleRoot)) {
                if ($Scope -and $Scope -notcontains $root.Scope) { continue }
                $key = Get-MMPathKey $root.Path
                $inRoot = @($installs | Where-Object { (Get-MMPathKey $_.ModuleRoot) -eq $key })
                $size = $null
                if ($IncludeSize -and $root.Exists) { $size = Get-MMFolderSizeMB $root.Path }
                [pscustomobject]@{
                    PSTypeName = 'ModuleManager.ModuleRoot'
                    Order      = $root.Order
                    Path       = $root.Path
                    Scope      = $root.Scope
                    Exists     = $root.Exists
                    Modules    = @($inRoot | ForEach-Object { $_.Name } | Select-Object -Unique).Count
                    Versions   = $inRoot.Count
                    SizeMB     = $size
                }
            }
            return
        }

        $installs = Get-MMInstalledVersion -Name $names -Scope $Scope -IncludeSystem:$IncludeSystem
        foreach ($group in ($installs | Group-Object Name | Sort-Object Name)) {
            foreach ($i in (Get-MMSortedInstallation $group.Group)) {
                if ($IncludeSize) {
                    $i | Add-Member -NotePropertyName SizeMB -NotePropertyValue (Get-MMFolderSizeMB $i.ModuleBase) -Force
                }
                $i
            }
        }
    }
}
