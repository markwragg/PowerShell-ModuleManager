function ConvertTo-MMTuiLogEntry {
    <#
    .SYNOPSIS
        Converts one output record from a terminal UI operation into a line for the output pane.

    .DESCRIPTION
        Turns one record from an operation's merged output (*>&1) into an output pane entry:
        @{ Text; Style }. Write-Host colours come through as ANSI codes (PowerShell 7) or as
        HostInformationMessage colours (Windows PowerShell); either way they're mapped to UI styles.

        Records from a remote computer arrive deserialized (property bags named, for example,
        Deserialized.System.Management.Automation.WarningRecord), so records are recognised by
        type name as well as by type.
    #>
    param([AllowNull()][object]$Record)
    $style = $null
    $text = ''
    $kind = $null
    if ($null -ne $Record) {
        foreach ($t in 'ErrorRecord', 'WarningRecord', 'VerboseRecord', 'DebugRecord', 'InformationRecord') {
            $full = "System.Management.Automation.$t"
            if ($Record.PSObject.TypeNames -contains $full -or $Record.PSObject.TypeNames -contains "Deserialized.$full") { $kind = $t; break }
        }
    }
    switch ($kind) {
        'ErrorRecord' {
            $message = [string]$Record
            if ($Record -is [System.Management.Automation.ErrorRecord]) { $message = $Record.Exception.Message }
            $text = "ERROR: $message"
            $style = 'Red'
        }
        # These turn into their message as text, whether live or deserialized (where the message is
        # in an InformationalRecord_Message property).
        'WarningRecord' { $text = "WARNING: $Record"; $style = 'Yellow' }
        'VerboseRecord' { $text = [string]$Record; $style = 'Dim' }
        'DebugRecord' { $text = "DEBUG: $Record"; $style = 'Dim' }
        'InformationRecord' {
            $data = $Record.MessageData
            if ($null -ne $data -and $data.PSObject.Properties['Text'] -and $data.PSObject.Properties['Style'] -and
                ($data.PSObject.TypeNames -contains 'ModuleManager.TuiOutput' -or $data.PSObject.TypeNames -contains 'Deserialized.ModuleManager.TuiOutput')) {
                # A line from an action (see Write-MMTuiOutput).
                $text = [string]$data.Text
                if ($data.Style) { $style = [string]$data.Style }
            }
            elseif ($null -ne $data -and $data.PSObject.Properties['Message'] -and $data.PSObject.Properties['ForegroundColor']) {
                # A Write-Host message (a HostInformationMessage, or a deserialized one).
                $text = [string]$data.Message
                if ($null -ne $data.ForegroundColor) { $style = ConvertTo-MMTuiStyle -Colour ([string]$data.ForegroundColor) }
            }
            else { $text = [string]$data }
        }
        default { if ($null -ne $Record) { $text = ($Record | Out-String).TrimEnd() } }
    }

    $match = $script:MMAnsiColour.Match($text)
    if (-not $style -and $match.Success) { $style = ConvertTo-MMTuiStyle -Ansi ([int]$match.Groups[1].Value) }
    @{ Text = $script:MMAnsiSequence.Replace($text, ''); Style = $style }
}
