function Get-MMInstalledBy {
    <#
    .SYNOPSIS
        Works out which package manager wrote a PSGetModuleInfo.xml: PSResourceGet, PowerShellGet or $null.

    .DESCRIPTION
        Each package manager only recognises the modules it installed itself (Update-Module, for
        example, says a module installed by Install-PSResource "was not installed by using
        Install-Module"), so updates should use the one that installed the module.

        The record's type names say which one wrote it. Failing that, InstalledLocation does:
        PowerShellGet records the version folder, PSResourceGet the module root above it.
    #>
    param([string]$Text, [string]$ModuleBase)

    if (-not $Text) { return $null }
    if ($Text.IndexOf('Microsoft.PowerShell.PSResourceGet.', [StringComparison]::Ordinal) -ge 0) { return 'PSResourceGet' }
    if ($Text.IndexOf('Microsoft.PowerShell.Commands.PSRepositoryItemInfo', [StringComparison]::Ordinal) -ge 0) { return 'PowerShellGet' }

    $location = Get-MMXmlValue $Text '<S N="InstalledLocation">' '</S>'
    if (-not $location -or -not $ModuleBase) { return $null }
    $location = [Net.WebUtility]::HtmlDecode($location)
    if ((Get-MMPathKey $location) -eq (Get-MMPathKey $ModuleBase)) { return 'PowerShellGet' }
    if (Test-MMPathUnder $ModuleBase $location) { return 'PSResourceGet' }
    $null
}
