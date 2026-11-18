function Exit-MMTuiScreen {
    <#
    .SYNOPSIS
        Restores the normal console screen and cursor after the terminal UI.
    #>
    param()

    $E = [char]27
    try { [Console]::TreatControlCAsInput = $false } catch { Write-Debug $_ }
    Write-MMConsole ("$E[0m$E[?25h$E[?1049l")
}
