function Exit-MMTuiScreen {
    <#
    .SYNOPSIS
        Restores the normal console screen and cursor after the terminal UI.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The terminal UI draws directly to the console (ANSI escape sequences), and shows action results to the user between screens.')]
    param()

    $E = [char]27
    try { [Console]::TreatControlCAsInput = $false } catch { Write-Debug $_ }
    [Console]::Write("$E[0m$E[?25h$E[?1049l")
}
