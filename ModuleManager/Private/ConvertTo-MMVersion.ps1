function ConvertTo-MMVersion {
    <#
    .SYNOPSIS
        Normalises anything version-like into a four-part [version].

    .DESCRIPTION
        Normalises anything version-like into a 4-part [version] (missing parts become 0)
        so that 1.0, 1.0.0 and 1.0.0.0 compare as equal. Prerelease/build suffixes are dropped.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param([Parameter(Position = 0)][AllowNull()][object]$Version)

    if ($null -eq $Version) { return [version]::new(0, 0, 0, 0) }

    if ($Version -isnot [version]) {
        $text = ([string]$Version).Split('-')[0].Split('+')[0].Trim()
        if ($text -notmatch '\.') { $text = "$text.0" }
        $parsed = $null
        if (-not [version]::TryParse($text, [ref]$parsed)) { return [version]::new(0, 0, 0, 0) }
        $Version = $parsed
    }

    [version]::new(
        [Math]::Max($Version.Major, 0),
        [Math]::Max($Version.Minor, 0),
        [Math]::Max($Version.Build, 0),
        [Math]::Max($Version.Revision, 0))
}
