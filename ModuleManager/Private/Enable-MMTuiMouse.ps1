function Enable-MMTuiMouse {
    <#
    .SYNOPSIS
        Turns on mouse input for the terminal UI, and returns how mouse events arrive (for
        Read-MMTuiInput): Windows, VT, or $null if the mouse can't be used.

    .DESCRIPTION
        On Windows, the console sends mouse events to programs that ask for them, as input records
        that [Console]::ReadKey discards, so a small helper (compiled here the first time) turns on
        the console's mouse input and reads them. Terminals such as Windows Terminal pass the mouse
        to the console when it's asked for. It also turns off Quick Edit, which would otherwise take
        the mouse to select text; Disable-MMTuiMouse puts it back.

        Elsewhere, the terminal is asked to report button presses and the wheel as escape sequences
        (xterm's mode 1000, in SGR format: mode 1006).
    #>
    param()

    if (-not $script:MMIsWindows) {
        $E = [char]27
        Write-MMConsole "$E[?1000h$E[?1006h"
        return 'VT'
    }

    try {
        if (-not ('ModuleManager.ConsoleMouse' -as [type])) { Add-Type -TypeDefinition $script:MMConsoleMouseSource -ErrorAction Stop }
        if (('ModuleManager.ConsoleMouse' -as [type])::Enable()) { return 'Windows' }
    }
    catch { Write-Debug "Mouse input not available: $_" }
    $null
}
