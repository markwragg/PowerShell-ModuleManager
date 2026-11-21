function Format-MMVersionRange {
    <#
    .SYNOPSIS
        Formats a NuGet-style version range for display, such as '>= 1.0', '1.2.0' or '>= 1.0, < 2.0'.

    .DESCRIPTION
        Returns '' for a range that matches any version, and the version alone for an exact one.
        Versions are shown as written in the range (ConvertFrom-MMVersionRange pads them to four parts).
    #>
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Range)
    $text = ''
    if ($Range) { $text = $Range.Trim() }
    if ($text -eq '' -or $text -eq '*') { return '' }
    if ($text[0] -notin '[', '(') { return ">= $text" }
    $minInclusive = $text[0] -eq '['
    $maxInclusive = $text[-1] -eq ']'
    $inner = $text.Substring(1, [Math]::Max(0, $text.Length - 2))
    if ($inner.IndexOf(',') -lt 0) { return $inner.Trim() }
    $parts = $inner.Split(',', 2)
    $min = $parts[0].Trim(); $max = $parts[1].Trim()
    $result = @()
    if ($min) { if ($minInclusive) { $result += ">= $min" } else { $result += "> $min" } }
    if ($max) { if ($maxInclusive) { $result += "<= $max" } else { $result += "< $max" } }
    $result -join ', '
}
