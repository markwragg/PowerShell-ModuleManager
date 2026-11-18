function Get-MMRegisteredRepository {
    <#
    .SYNOPSIS
        Returns the names of the registered repositories, cached after the first call.
    #>
    if ($null -eq $script:MMRepositories) {
        $names = @()
        try {
            switch (Get-MMBackend) {
                'PSResourceGet' { $names = @(Microsoft.PowerShell.PSResourceGet\Get-PSResourceRepository -ErrorAction Stop | ForEach-Object { $_.Name }) }
                'PowerShellGet' { $names = @(PowerShellGet\Get-PSRepository -ErrorAction Stop | ForEach-Object { $_.Name }) }
            }
        }
        catch { Write-Verbose "Could not list repositories: $_" }
        $script:MMRepositories = $names
    }
    $script:MMRepositories
}
