function Request-MMTuiConfirm {
    <#
    .SYNOPSIS
        Asks a y/N question in the terminal UI and runs an action if the answer is y.

    .DESCRIPTION
        Shows a y/N prompt. On 'y', $Action is invoked with ($State, $Data). Action scriptblocks
        are plain (not closures) so they keep access to the module's private functions.
    #>
    param([hashtable]$State, [string]$Prompt, [scriptblock]$Action, [object]$Data)
    $State.Confirm = @{ Prompt = $Prompt; Action = $Action; Data = $Data; ReturnMode = $State.Mode }
    $State.Mode = 'confirm'
}
