function Enter-MMTuiScreen {
    <#
    .SYNOPSIS
        Switches the console to the alternate screen buffer for the terminal UI and hides the cursor.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The terminal UI draws directly to the console (ANSI escape sequences), and shows action results to the user between screens.')]
    param()

    $E = [char]27
    [Console]::Write("$E[?1049h$E[?25l$E[2J$E[H")
    try { [Console]::TreatControlCAsInput = $true } catch { Write-Debug $_ }
}
