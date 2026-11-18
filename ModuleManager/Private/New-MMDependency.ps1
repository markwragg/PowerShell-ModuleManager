function New-MMDependency {
    <#
    .SYNOPSIS
        Creates a dependency object: a module name and NuGet-style version range.

    .DESCRIPTION
        Builds a dependency (module name and NuGet-style version range) from the forms the
        package managers and manifests use: a range string, or minimum/maximum/required versions.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory object; changes no system state.')]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$VersionRange,
        [string]$MinimumVersion,
        [string]$MaximumVersion,
        [string]$RequiredVersion
    )
    $range = $VersionRange
    if (-not $range) {
        if ($RequiredVersion) { $range = "[$RequiredVersion]" }
        elseif ($MinimumVersion -and $MaximumVersion) { $range = "[$MinimumVersion, $MaximumVersion]" }
        elseif ($MinimumVersion) { $range = "[$MinimumVersion, )" }
        elseif ($MaximumVersion) { $range = "(, $MaximumVersion]" }
        else { $range = '' }
    }
    [pscustomobject]@{
        PSTypeName   = 'ModuleManager.Dependency'
        Name         = $Name.Trim()
        VersionRange = $range
    }
}
