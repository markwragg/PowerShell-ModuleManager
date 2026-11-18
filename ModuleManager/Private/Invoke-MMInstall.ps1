function Invoke-MMInstall {
    <#
    .SYNOPSIS
        Installs a specific module version using whichever package manager is available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version,
        [bool]$Prerelease,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][ValidateSet('CurrentUser', 'AllUsers')][string]$Scope,
        [switch]$TrustRepository
    )
    # The installers' own verbose and progress output is noisy and would fight with the
    # caller's progress bar, so keep them quiet. Errors and warnings still come through.
    $ProgressPreference = 'SilentlyContinue'
    switch (Get-MMBackend) {
        'PSResourceGet' {
            $params = @{
                Name        = $Name
                Version     = "[$Version]"
                Repository  = $Repository
                Scope       = $Scope
                ErrorAction = 'Stop'
                Confirm     = $false
            }
            if ($Prerelease) { $params.Prerelease = $true }
            if ($TrustRepository) { $params.TrustRepository = $true }
            Microsoft.PowerShell.PSResourceGet\Install-PSResource @params
        }
        'PowerShellGet' {
            $params = @{
                Name            = $Name
                RequiredVersion = $Version
                Repository      = $Repository
                Scope           = $Scope
                AllowClobber    = $true
                ErrorAction     = 'Stop'
                Confirm         = $false
            }
            if ($Prerelease) { $params.AllowPrerelease = $true }
            if ($TrustRepository) { $params.Force = $true }
            PowerShellGet\Install-Module @params
        }
        default { throw 'Neither Microsoft.PowerShell.PSResourceGet nor PowerShellGet is available to install modules.' }
    }
}
