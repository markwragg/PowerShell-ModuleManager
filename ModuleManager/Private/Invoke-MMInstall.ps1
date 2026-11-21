function Invoke-MMInstall {
    <#
    .SYNOPSIS
        Installs a specific module version using whichever package manager is available.

    .DESCRIPTION
        With -InstalledBy, uses that package manager when it's available, so a module stays
        recognised by the one that installed it (Update-Module and Get-InstalledModule only see
        modules installed by PowerShellGet, and Update-PSResource only those installed by
        PSResourceGet). Otherwise uses PSResourceGet when available, or PowerShellGet.

        It warns when it has to use the other package manager for a module that has an install
        record: when the one that installed it isn't available, or for a prerelease when that is
        PowerShellGet 1.x (as shipped with Windows PowerShell), which can't install prereleases.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version,
        [bool]$Prerelease,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][ValidateSet('CurrentUser', 'AllUsers')][string]$Scope,
        [switch]$TrustRepository,
        [AllowNull()][AllowEmptyString()][ValidateSet('PSResourceGet', 'PowerShellGet', '')][string]$InstalledBy
    )
    # The installers' own verbose and progress output is noisy and would fight with the
    # caller's progress bar, so keep them quiet. Errors and warnings still come through.
    $ProgressPreference = 'SilentlyContinue'
    $backend = Get-MMBackend
    $commands = @{ PowerShellGet = 'Update-Module or Get-InstalledModule'; PSResourceGet = 'Update-PSResource or Get-InstalledPSResource' }
    if ($InstalledBy -and $InstalledBy -ne $backend) {
        $command = 'PowerShellGet\Install-Module'
        if ($InstalledBy -eq 'PSResourceGet') { $command = 'Microsoft.PowerShell.PSResourceGet\Install-PSResource' }
        if (Get-Command -Name $command -ErrorAction Ignore) {
            Write-Verbose "Installing $Name $Version with $InstalledBy, which installed the existing version."
            $backend = $InstalledBy
        }
        elseif ($backend -ne 'None') {
            Write-Warning ("$Name was installed with $InstalledBy, which isn't available in this session, so $Version is being installed with $backend. " +
                "$InstalledBy's own commands, such as $($commands[$InstalledBy]), may not recognise the new version.")
        }
    }
    # PowerShellGet 1.x can't install prereleases; PSResourceGet, if it's here, can.
    if ($backend -eq 'PowerShellGet' -and $Prerelease -and
        -not (Get-Command -Name PowerShellGet\Install-Module).Parameters.ContainsKey('AllowPrerelease') -and
        (Get-Command -Name 'Microsoft.PowerShell.PSResourceGet\Install-PSResource' -ErrorAction Ignore)) {
        Write-Warning ("$Name was installed with PowerShellGet, but this version of PowerShellGet can't install prereleases, so $Version is being installed with PSResourceGet. " +
            "PowerShellGet's own commands, such as $($commands.PowerShellGet), may not recognise the new version.")
        $backend = 'PSResourceGet'
    }
    switch ($backend) {
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
                ErrorAction     = 'Stop'
                Confirm         = $false
            }
            # PowerShellGet 1.x (as shipped with Windows PowerShell) has neither of these.
            $available = (Get-Command -Name PowerShellGet\Install-Module).Parameters
            if ($available.ContainsKey('AllowClobber')) { $params.AllowClobber = $true }
            if ($Prerelease) {
                if (-not $available.ContainsKey('AllowPrerelease')) {
                    throw "This version of PowerShellGet can't install prerelease versions. Install PowerShellGet 2 or Microsoft.PowerShell.PSResourceGet."
                }
                $params.AllowPrerelease = $true
            }
            if ($TrustRepository) { $params.Force = $true }
            PowerShellGet\Install-Module @params
        }
        default { throw 'Neither Microsoft.PowerShell.PSResourceGet nor PowerShellGet is available to install modules.' }
    }
}
