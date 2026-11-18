function ConvertTo-MMTuiStyle {
    <#
    .SYNOPSIS
        Maps a console colour name, or an ANSI foreground colour code, to a terminal UI style name.
    #>
    param([string]$Colour, [int]$Ansi = -1)
    if ($Ansi -ge 0) {
        $Colour = switch ($Ansi % 10) {
            1 { 'Red' } 2 { 'Green' } 3 { 'Yellow' } 5 { 'Magenta' } 6 { 'Cyan' }
            default { if ($Ansi -eq 90) { 'Gray' } }
        }
    }
    switch -Regex ($Colour) {
        'Red$' { 'Red' }
        'Green$' { 'Green' }
        'Yellow$' { 'Yellow' }
        'Cyan$' { 'Cyan' }
        'Magenta$' { 'Magenta' }
        'Gray$' { 'Dim' }
        default { $null }
    }
}
