function Set-MMTuiMessage {
    <#
    .SYNOPSIS
        Sets the message shown on the terminal UI status line.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    param([hashtable]$State, [string]$Text, [string]$Style = 'Dim')
    $State.Message = $Text
    $State.MessageStyle = $Style
}
