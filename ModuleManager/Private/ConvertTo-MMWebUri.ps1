function ConvertTo-MMWebUri {
    <#
    .SYNOPSIS
        Returns a web address (http or https) in its escaped form, or $null for anything else.

    .DESCRIPTION
        Addresses come from module metadata, which anyone publishing a module can set, so only
        absolute http and https addresses are shown as links or opened: never a file path, a
        program or another scheme. The escaped form has no spaces or control characters, so it is
        also safe to put in a terminal hyperlink sequence.
    #>
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Uri)
    if ([string]::IsNullOrWhiteSpace($Uri)) { return $null }
    $parsed = $null
    if (-not [uri]::TryCreate($Uri.Trim(), [UriKind]::Absolute, [ref]$parsed)) { return $null }
    if ($parsed.Scheme -notin 'http', 'https' -or -not $parsed.Host) { return $null }
    $text = $parsed.AbsoluteUri
    if ($text -match '[\x00-\x20\x7f]') { return $null }
    $text
}
