function ConvertTo-MMTuiLogEntry {
    <#
    .SYNOPSIS
        Converts one output record from a terminal UI operation into a line for the output pane.

    .DESCRIPTION
        Turns one record from an operation's merged output (*>&1) into an output pane entry:
        @{ Text; Style }. Write-Host colours come through as ANSI codes (PowerShell 7) or as
        HostInformationMessage colours (Windows PowerShell); either way they're mapped to UI styles.
    #>
    param([AllowNull()][object]$Record)
    $style = $null
    $text = ''
    if ($Record -is [System.Management.Automation.ErrorRecord]) {
        $text = "ERROR: $($Record.Exception.Message)"
        $style = 'Red'
    }
    elseif ($Record -is [System.Management.Automation.WarningRecord]) { $text = "WARNING: $($Record.Message)"; $style = 'Yellow' }
    elseif ($Record -is [System.Management.Automation.VerboseRecord]) { $text = $Record.Message; $style = 'Dim' }
    elseif ($Record -is [System.Management.Automation.DebugRecord]) { $text = "DEBUG: $($Record.Message)"; $style = 'Dim' }
    elseif ($Record -is [System.Management.Automation.InformationRecord]) {
        $data = $Record.MessageData
        if ($data -is [System.Management.Automation.HostInformationMessage]) {
            $text = [string]$data.Message
            if ($null -ne $data.ForegroundColor) { $style = ConvertTo-MMTuiStyle -Colour ([string]$data.ForegroundColor) }
        }
        else { $text = [string]$data }
    }
    elseif ($null -ne $Record) { $text = ($Record | Out-String).TrimEnd() }

    $match = $script:MMAnsiColour.Match($text)
    if (-not $style -and $match.Success) { $style = ConvertTo-MMTuiStyle -Ansi ([int]$match.Groups[1].Value) }
    @{ Text = $script:MMAnsiSequence.Replace($text, ''); Style = $style }
}
