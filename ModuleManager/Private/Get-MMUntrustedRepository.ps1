function Get-MMUntrustedRepository {
    <#
    .SYNOPSIS
        Returns which of the given repositories aren't trusted.

    .DESCRIPTION
        Returns the names of the given repositories that aren't trusted, so installing from them
        would ask for confirmation. The terminal UI runs installs where nothing can answer that
        prompt, so it asks first instead. Repositories that can't be checked are left out.

        PowerShellGet and PSResourceGet keep their own lists of repositories, each with its own
        trust setting, and an update uses whichever installed the module. So a repository counts
        as untrusted if either package manager that's available doesn't trust it.
    #>
    param([string[]]$Name)
    $Name = @($Name | Where-Object { $_ } | Sort-Object -Unique)
    if (-not $Name) { return }
    $backend = Get-MMBackend
    if ($backend -eq 'None') { return }
    $untrusted = @(
        if ($backend -eq 'PSResourceGet') {
            try {
                Microsoft.PowerShell.PSResourceGet\Get-PSResourceRepository -Name $Name -ErrorAction Stop |
                    Where-Object { -not $_.Trusted } | ForEach-Object { $_.Name }
            }
            catch { Write-Verbose "Could not check repository trust with PSResourceGet: $($_.Exception.Message)" }
        }
        if ($backend -eq 'PowerShellGet' -or (Get-Command -Name PowerShellGet\Get-PSRepository -ErrorAction Ignore)) {
            try {
                # Listed in full, as a repository only PSResourceGet knows about would fail -Name.
                PowerShellGet\Get-PSRepository -ErrorAction Stop |
                    Where-Object { $_.Name -in $Name -and $_.InstallationPolicy -ne 'Trusted' } | ForEach-Object { $_.Name }
            }
            catch { Write-Verbose "Could not check repository trust with PowerShellGet: $($_.Exception.Message)" }
        }
    )
    $untrusted | Sort-Object -Unique
}
