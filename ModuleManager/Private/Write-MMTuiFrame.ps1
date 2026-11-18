function Write-MMTuiFrame {
    <#
    .SYNOPSIS
        Draws the terminal UI screen to the console.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The terminal UI draws directly to the console (ANSI escape sequences), and shows action results to the user between screens.')]
    param([hashtable]$State)
    $E = [char]27
    $w = [Math]::Max(40, [Console]::WindowWidth) - 1
    $h = [Math]::Max(8, [Console]::WindowHeight)
    $clear = ''
    if ($w -ne $State.Width -or $h -ne $State.Height) { $clear = "$E[2J" }
    $frame = Get-MMTuiFrame -State $State -Width $w -Height $h
    [Console]::Write("$E[?25l$clear$E[H$frame")
}
