function Get-MMCachedResult {
    <#
    .SYNOPSIS
        Returns the cached repository lookup result for a request, if it hasn't expired.
    #>
    param([object]$Request)
    $key = Get-MMCacheKey $Request.Name $Request.Repository $Request.Prerelease
    $hit = $script:MMGalleryCache[$key]
    if ($hit -and ([datetime]::UtcNow - $hit.CachedAt) -lt $script:MMCacheLifetime) { return $hit }
    $null
}
