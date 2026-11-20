function Disable-MMTuiMouse {
    <#
    .SYNOPSIS
        Turns off the mouse input Enable-MMTuiMouse turned on, restoring the console as it was.
    #>
    param([string]$Mode)

    switch ($Mode) {
        'Windows' { try { ('ModuleManager.ConsoleMouse' -as [type])::Disable() } catch { Write-Debug $_ } }
        'VT' {
            $E = [char]27
            Write-MMConsole "$E[?1006l$E[?1000l"
        }
    }
}
