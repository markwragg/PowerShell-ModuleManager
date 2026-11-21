function Test-MMTuiHyperlink {
    <#
    .SYNOPSIS
        Returns $true if the terminal is known to support hyperlinks (OSC 8).

    .DESCRIPTION
        Terminals that don't support them may print the sequence as text, and there's no way to ask,
        so only terminals known to support them are used: Windows Terminal, the VS Code terminal,
        iTerm2, WezTerm, Ghostty, kitty, Konsole and VTE-based terminals (such as GNOME Terminal).
        Elsewhere the address is still shown, and can be clicked in the terminal UI to open it.
    #>
    [OutputType([bool])]
    param()
    if ($env:WT_SESSION -or $env:KITTY_WINDOW_ID -or $env:KONSOLE_VERSION) { return $true }
    if ($env:TERM_PROGRAM -in 'vscode', 'iTerm.app', 'WezTerm', 'ghostty') { return $true }
    $vte = 0
    if ([int]::TryParse([string]$env:VTE_VERSION, [ref]$vte) -and $vte -ge 5000) { return $true }
    $false
}
