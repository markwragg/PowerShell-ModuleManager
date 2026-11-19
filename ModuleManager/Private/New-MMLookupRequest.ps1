function New-MMLookupRequest {
    <#
    .SYNOPSIS
        Works out which repository (and prerelease setting) to query for each module.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    param(
        [object[]]$ModuleInfo,
        [string]$Repository,
        [switch]$IncludePrerelease
    )
    $registered = @(Get-MMRegisteredRepository)
    foreach ($m in $ModuleInfo) {
        $repo = 'PSGallery'
        if ($Repository) { $repo = $Repository }
        elseif ($m.Repository -and $registered -contains $m.Repository) { $repo = $m.Repository }
        $installed = $null
        if ($m.PSObject.Properties['Version']) { $installed = [string]$m.Version }
        [pscustomobject]@{
            Name             = $m.Name
            Repository       = $repo
            Prerelease       = [bool]($IncludePrerelease -or $m.Prerelease)
            # The newest installed version, so the lookup can tell an unlisted module from a missing one.
            InstalledVersion = $installed
        }
    }
}
