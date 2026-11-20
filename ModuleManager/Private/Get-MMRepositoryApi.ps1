function Get-MMRepositoryApi {
    <#
    .SYNOPSIS
        Returns the NuGet v2 API address of a repository, if lookups can query it directly.

    .DESCRIPTION
        Lookups query a NuGet v2 feed (such as the PowerShell Gallery) over HTTP, as that's many
        times faster than the package managers' own commands. Returns $null for anything else (NuGet v3
        feeds, file shares, repositories that need credentials, or ones that can't be listed), which
        are looked up with the package manager instead. Cached per repository after the first call.
    #>
    param([Parameter(Mandatory)][string]$Name)

    if (-not $script:MMRepositoryApi.ContainsKey($Name)) {
        $url = $null
        try {
            switch (Get-MMBackend) {
                'PSResourceGet' {
                    $repo = Microsoft.PowerShell.PSResourceGet\Get-PSResourceRepository -Name $Name -ErrorAction Stop | Select-Object -First 1
                    if ($repo -and [string]$repo.ApiVersion -eq 'V2' -and -not $repo.CredentialInfo) { $url = [string]$repo.Uri }
                }
                'PowerShellGet' {
                    # PowerShellGet only works with v2 feeds and file shares.
                    $repo = PowerShellGet\Get-PSRepository -Name $Name -ErrorAction Stop | Select-Object -First 1
                    if ($repo) { $url = [string]$repo.SourceLocation }
                }
            }
        }
        catch { Write-Verbose "Could not read repository '$Name': $_" }
        if ($url -notmatch '^https?://') { $url = $null }
        if ($url) { $url = $url.TrimEnd('/') }
        $script:MMRepositoryApi[$Name] = $url
    }
    $script:MMRepositoryApi[$Name]
}
