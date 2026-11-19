function Write-MMTuiOutput {
    <#
    .SYNOPSIS
        Writes a line for the terminal UI's output pane, with its style, from inside an action.

    .DESCRIPTION
        Actions run in a background or remote runspace without a console. Write-Host colours only
        sometimes survive that (they're turned into ANSI codes, or not, depending on the host), so
        actions send their result lines as information records that carry the style, which
        ConvertTo-MMTuiLogEntry reads.
    #>
    param([string]$Text, [string]$Style)
    $line = [pscustomobject]@{ PSTypeName = 'ModuleManager.TuiOutput'; Text = $Text; Style = $Style }
    Write-Information -MessageData $line -Tags 'ModuleManager' -InformationAction Continue
}
