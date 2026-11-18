function Format-MMTuiLine {
    <#
    .SYNOPSIS
        Builds one terminal UI line from styled text segments, at exactly the given width.

    .DESCRIPTION
        Builds one screen line from (text, styleName) segments, truncated/padded to exactly
        $Width visible characters. $Base is a style applied to the whole line.
    #>
    param([object[]]$Segments, [int]$Width, [string]$Base = '')
    $st = $script:MMStyle
    $baseCode = ''
    if ($Base) { $baseCode = $st[$Base] }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append($st.Reset).Append($baseCode)
    $used = 0
    foreach ($seg in $Segments) {
        if ($null -eq $seg) { continue }
        $text = [string]$seg[0]
        $style = $null
        if ($seg.Count -gt 1 -and $seg[1]) { $style = $st[[string]$seg[1]] }
        $remain = $Width - $used
        if ($remain -le 0) { break }
        if ($text.Length -gt $remain) { $text = Format-MMCell $text $remain }
        if ($style) { [void]$sb.Append($style).Append($text).Append($st.Reset).Append($baseCode) }
        else { [void]$sb.Append($text) }
        $used += $text.Length
    }
    if ($used -lt $Width) { [void]$sb.Append(' ' * ($Width - $used)) }
    [void]$sb.Append($st.Reset)
    $sb.ToString()
}
