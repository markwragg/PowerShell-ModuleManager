function Test-MMVersionInRange {
    <#
    .SYNOPSIS
        Returns $true if a version (with optional prerelease label) is inside a NuGet-style range.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Position = 0)][AllowNull()][object]$Version,
        [Parameter(Position = 1)][AllowNull()][AllowEmptyString()][string]$Prerelease,
        [Parameter(Position = 2)][AllowNull()][AllowEmptyString()][string]$Range
    )
    $r = ConvertFrom-MMVersionRange $Range
    if ($r.Any) { return $true }
    if ($r.Min) {
        $c = Compare-MMVersion $Version $Prerelease $r.Min.Version $r.Min.Prerelease
        if ($c -lt 0 -or ($c -eq 0 -and -not $r.MinInclusive)) { return $false }
    }
    if ($r.Max) {
        $c = Compare-MMVersion $Version $Prerelease $r.Max.Version $r.Max.Prerelease
        if ($c -gt 0 -or ($c -eq 0 -and -not $r.MaxInclusive)) { return $false }
    }
    $true
}
