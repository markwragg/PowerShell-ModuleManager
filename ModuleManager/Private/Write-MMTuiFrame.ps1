function Write-MMTuiFrame {
    <#
    .SYNOPSIS
        Draws the terminal UI screen to the console.
    #>
    param([hashtable]$State)
    $E = [char]27
    $size = Get-MMConsoleSize
    $w = $size.Width
    $h = $size.Height
    $clear = ''
    if ($w -ne $State.Width -or $h -ne $State.Height) { $clear = "$E[2J" }
    $frame = Get-MMTuiFrame -State $State -Width $w -Height $h
    Write-MMConsole "$E[?25l$clear$E[H$frame"
}
