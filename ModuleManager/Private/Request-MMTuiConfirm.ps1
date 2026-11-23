function Request-MMTuiConfirm {
    <#
    .SYNOPSIS
        Asks a y/N question in the terminal UI and runs an action if the answer is yes.

    .DESCRIPTION
        Shows a y/N prompt (or, with -Choices 'yf', a y/f/N prompt). On any of the choices,
        $Action is invoked with ($State, $Data, $Choice). Anything else cancels. Action
        scriptblocks are plain (not closures) so they keep access to the module's private functions.
    #>
    param([hashtable]$State, [string]$Prompt, [scriptblock]$Action, [object]$Data, [string]$Choices = 'y')
    # Show-ModuleManager -WhatIf: answering yes only shows what would change.
    if ($State.Options -and $State.Options['WhatIf']) { $Prompt = "WhatIf (nothing will change): $Prompt" }
    $State.Confirm = @{ Prompt = $Prompt; Action = $Action; Data = $Data; Choices = $Choices; ReturnMode = $State.Mode }
    $State.Mode = 'confirm'
}
