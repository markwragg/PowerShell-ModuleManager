function Enter-MMTuiScreen {
    <#
    .SYNOPSIS
        Switches the console to the alternate screen buffer for the terminal UI and hides the cursor.
    #>
    param()

    $E = [char]27
    Write-MMConsole ("$E[?1049h$E[?25l$E[2J$E[H")
    try { [Console]::TreatControlCAsInput = $true } catch { Write-Debug $_ }
}
