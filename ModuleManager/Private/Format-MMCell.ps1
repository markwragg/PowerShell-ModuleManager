function Format-MMCell {
    <#
    .SYNOPSIS
        Pads or truncates text to an exact width for a terminal UI column.
    #>
    param([AllowNull()][object]$Text, [int]$Width, [switch]$Right)
    if ($Width -le 0) { return '' }
    $s = [string]$Text
    if ($s.Length -gt $Width) {
        if ($Width -gt 1) { $s = $s.Substring(0, $Width - 1) + [char]0x2026 } else { $s = $s.Substring(0, $Width) }
    }
    if ($Right) { $s.PadLeft($Width) } else { $s.PadRight($Width) }
}
