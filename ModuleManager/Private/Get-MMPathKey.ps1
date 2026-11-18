function Get-MMPathKey {
    <#
    .SYNOPSIS
        Normalises a path for comparison (case-insensitive on Windows, no trailing separator).
    #>
    param([string]$Path)
    if (-not $Path) { return '' }
    $p = $Path.TrimEnd('\', '/')
    if ($script:MMIsWindows) { $p = $p.Replace('/', '\').ToLowerInvariant() }
    $p
}
