function Find-MMManifestKey {
    <#
    .SYNOPSIS
        Finds a top-level key in manifest text and returns the text from that point.

    .DESCRIPTION
        Returns a window of text starting at the first uncommented "<Key> =" assignment.
        Uses ordinal IndexOf (fast) rather than running regexes over whole manifests, some
        of which are several hundred KB.
    #>
    param([string]$Text, [string]$Key, [int]$Window = 4000)
    $idx = 0
    while ($true) {
        $idx = $Text.IndexOf($Key, $idx, [StringComparison]::OrdinalIgnoreCase)
        if ($idx -lt 0) { return $null }
        $before = ' '
        if ($idx -gt 0) { $before = $Text[$idx - 1] }
        if (-not ([char]::IsLetterOrDigit($before) -or $before -eq '_')) {
            $lineStart = 0
            if ($idx -gt 0) { $lineStart = $Text.LastIndexOf("`n", $idx - 1) + 1 }
            $prefix = $Text.Substring($lineStart, $idx - $lineStart)
            if ($prefix.IndexOf('#') -lt 0) {
                $win = $Text.Substring($idx, [Math]::Min($Window, $Text.Length - $idx))
                $m = $script:MMRegex.Assignment.Match($win)
                if ($m.Success -and $m.Groups[1].Value.Length -eq $Key.Length) { return $win }
            }
        }
        $idx += $Key.Length
    }
}
