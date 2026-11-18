function Test-MMPathUnder {
    <#
    .SYNOPSIS
        Returns $true if a path is the same as, or inside, a base folder.
    #>
    param([string]$Path, [string]$Base)
    if (-not $Path -or -not $Base) { return $false }
    $p = Get-MMPathKey $Path
    $b = Get-MMPathKey $Base
    if (-not $b) { return $false }
    $sep = [IO.Path]::DirectorySeparatorChar
    ($p -eq $b) -or $p.StartsWith("$b$sep")
}
