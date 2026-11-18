function Test-MMInteractiveConsole {
    <#
    .SYNOPSIS
        Returns $true if the console can run the terminal UI (neither input nor output is redirected).
    #>
    -not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)
}
