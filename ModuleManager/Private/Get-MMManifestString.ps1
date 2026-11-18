function Get-MMManifestString {
    <#
    .SYNOPSIS
        Reads a string value (such as Description or Author) from manifest text.
    #>
    param([string]$Text, [string]$Key)
    $win = Find-MMManifestKey $Text $Key
    if (-not $win) { return $null }
    $m = $script:MMRegex.StringValue.Match($win)
    if (-not $m.Success) { return $null }
    if ($m.Groups[1].Success) { return $m.Groups[1].Value.Replace("''", "'") }
    $m.Groups[2].Value
}
