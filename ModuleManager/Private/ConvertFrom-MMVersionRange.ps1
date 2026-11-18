function ConvertFrom-MMVersionRange {
    <#
    .SYNOPSIS
        Parses a NuGet-style version range into its lower and upper bounds.

    .DESCRIPTION
        Parses a NuGet-style version range into its bounds:
          '1.0'         1.0 or later (NuGet treats a bare version as a minimum)
          '[1.0]'       exactly 1.0
          '[1.0, )'     1.0 or later
          '[1.0, 2.0)'  1.0 or later, below 2.0
          '(, 2.0]'     up to and including 2.0
        An empty range, or '*', matches any version. Results are cached because the same
        ranges are checked many times when working out what a removal would break.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Range)

    $text = ''
    if ($Range) { $text = $Range.Trim() }
    $cached = $script:MMRangeCache[$text]
    if ($cached) { return $cached }

    $result = @{ Any = $false; Min = $null; MinInclusive = $true; Max = $null; MaxInclusive = $true }
    if ($text -eq '' -or $text -eq '*') { $result.Any = $true }
    elseif ($text[0] -in '[', '(') {
        $result.MinInclusive = $text[0] -eq '['
        $result.MaxInclusive = $text[-1] -eq ']'
        $inner = $text.Substring(1, $text.Length - 2)
        if ($inner.IndexOf(',') -lt 0) {
            $result.Min = ConvertTo-MMVersionBound $inner
            $result.Max = $result.Min
        }
        else {
            $parts = $inner.Split(',', 2)
            $result.Min = ConvertTo-MMVersionBound $parts[0]
            $result.Max = ConvertTo-MMVersionBound $parts[1]
        }
        if (-not $result.Min -and -not $result.Max) { $result.Any = $true }
    }
    else { $result.Min = ConvertTo-MMVersionBound $text }

    $script:MMRangeCache[$text] = $result
    $result
}
