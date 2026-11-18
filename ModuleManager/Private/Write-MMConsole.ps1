function Write-MMConsole {
    <#
    .SYNOPSIS
        Writes text (with ANSI escape sequences) straight to the console, for the terminal UI.

    .DESCRIPTION
        A wrapper around [Console]::Write, so tests can drive the terminal UI without a console.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The terminal UI draws directly to the console with ANSI escape sequences.')]
    param([string]$Text)
    [Console]::Write($Text)
}
