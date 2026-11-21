function Format-MMTuiLine {
    <#
    .SYNOPSIS
        Builds one terminal UI line from styled text segments, at exactly the given width.

    .DESCRIPTION
        Builds one screen line from (text, styleName) segments, truncated/padded to exactly
        $Width visible characters. $Base is a style applied to the whole line.

        A segment can have a web address as a third item: where the terminal supports it
        ($script:MMTuiHyperlink, see Test-MMTuiHyperlink), its text is a hyperlink to that address
        (OSC 8), which takes no room on screen. The address must come from ConvertTo-MMWebUri.
    #>
    param([object[]]$Segments, [int]$Width, [string]$Base = '')
    $st = $script:MMStyle
    $baseCode = ''
    if ($Base) { $baseCode = $st[$Base] }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append($st.Reset).Append($baseCode)
    $used = 0
    $esc = [char]27
    foreach ($seg in $Segments) {
        if ($null -eq $seg) { continue }
        $text = [string]$seg[0]
        $style = $null
        if ($seg.Count -gt 1 -and $seg[1]) { $style = $st[[string]$seg[1]] }
        $link = $null
        if ($seg.Count -gt 2 -and $seg[2] -and $script:MMTuiHyperlink) { $link = [string]$seg[2] }
        $remain = $Width - $used
        if ($remain -le 0) { break }
        if ($text.Length -gt $remain) { $text = Format-MMCell $text $remain }
        if ($link) { [void]$sb.Append("$esc]8;;$link$esc\") }
        if ($style) { [void]$sb.Append($style).Append($text).Append($st.Reset).Append($baseCode) }
        else { [void]$sb.Append($text) }
        if ($link) { [void]$sb.Append("$esc]8;;$esc\") }
        $used += $text.Length
    }
    if ($used -lt $Width) { [void]$sb.Append(' ' * ($Width - $used)) }
    [void]$sb.Append($st.Reset)
    $sb.ToString()
}
