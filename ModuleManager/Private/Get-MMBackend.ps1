function Get-MMBackend {
    <#
    .SYNOPSIS
        Returns which package manager is available: PSResourceGet, PowerShellGet or None.
    #>
    if (-not $script:MMBackend) {
        if (Get-Command -Name Find-PSResource -ErrorAction Ignore) { $script:MMBackend = 'PSResourceGet' }
        elseif (Get-Command -Name Find-Module -ErrorAction Ignore) { $script:MMBackend = 'PowerShellGet' }
        else { $script:MMBackend = 'None' }
    }
    $script:MMBackend
}
