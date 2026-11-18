function Get-MMCacheKey {
    <#
    .SYNOPSIS
        Builds the repository lookup cache key for a module name, repository and prerelease setting.
    #>
    param([string]$Name, [string]$Repository, [bool]$Prerelease)
    "$Repository|$Name|$Prerelease".ToLowerInvariant()
}
