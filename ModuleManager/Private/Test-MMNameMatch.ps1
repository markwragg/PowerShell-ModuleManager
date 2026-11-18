function Test-MMNameMatch {
    <#
    .SYNOPSIS
        Returns $true if a name matches any of the given wildcard patterns (or no patterns are given).
    #>
    param([string]$Name, [string[]]$Pattern)
    if (-not $Pattern) { return $true }
    foreach ($p in $Pattern) {
        if ($Name -like $p) { return $true }
    }
    $false
}
