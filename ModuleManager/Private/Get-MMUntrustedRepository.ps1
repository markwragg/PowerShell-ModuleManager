function Get-MMUntrustedRepository {
    <#
    .SYNOPSIS
        Returns which of the given repositories aren't trusted.

    .DESCRIPTION
        Returns the names of the given repositories that aren't trusted, so installing from them
        would ask for confirmation. The terminal UI runs installs where nothing can answer that
        prompt, so it asks first instead. Repositories that can't be checked are left out.
    #>
    param([string[]]$Name)
    $Name = @($Name | Where-Object { $_ } | Sort-Object -Unique)
    if (-not $Name) { return }
    try {
        switch (Get-MMBackend) {
            'PSResourceGet' {
                Microsoft.PowerShell.PSResourceGet\Get-PSResourceRepository -Name $Name -ErrorAction Stop |
                    Where-Object { -not $_.Trusted } | ForEach-Object { $_.Name }
            }
            'PowerShellGet' {
                PowerShellGet\Get-PSRepository -Name $Name -ErrorAction Stop |
                    Where-Object { $_.InstallationPolicy -ne 'Trusted' } | ForEach-Object { $_.Name }
            }
        }
    }
    catch { Write-Verbose "Could not check repository trust: $($_.Exception.Message)" }
}
