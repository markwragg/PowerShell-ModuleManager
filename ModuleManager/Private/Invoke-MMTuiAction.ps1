function Invoke-MMTuiAction {
    <#
    .SYNOPSIS
        Starts a terminal UI operation in the background, with its output in the output pane.

    .DESCRIPTION
        Starts an action in a background runspace and opens the output pane at the bottom of the
        screen, so the UI stays up (and usable) while it runs. Receive-MMTuiTask collects its
        output and progress, and when it finishes calls $OnComplete with ($State, $Data) and
        rescans.

        $Action is called as ($Data, $Options) in a fresh copy of this module, so it can use the
        module's private functions. It's passed as text, so it must not rely on variables from
        where it was written. Nothing can answer a prompt there (a prompt fails with an error), so
        actions pass -Confirm:$false, and updates ask about untrusted repositories beforehand.

        With -Elevated (on this computer), the action runs as administrator, in an elevated
        PowerShell process that Windows asks permission for (see Start-MMTuiElevatedAction).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI; the action itself was confirmed by the user.')]
    param([hashtable]$State, [string]$Title, [scriptblock]$Action, [object]$Data, [scriptblock]$OnComplete, [switch]$Elevated)

    if (Test-MMTuiBusy $State) { return }

    # With Show-ModuleManager -Verbose, the action runs with verbose messages on, and they reach the
    # output pane with the rest of its output, wherever it runs. With -WhatIf, it runs in WhatIf
    # mode (see Test-MMShouldProcess), which is reset afterwards, as a remote computer keeps its
    # copy of the module between operations. The action is passed as text, so it's wrapped as text.
    if ($State.Options -and ($State.Options['Verbose'] -or $State.Options['WhatIf'])) {
        $setup = ''
        if ($State.Options['Verbose']) { $setup += "`$VerbosePreference = 'Continue'`n" }
        if ($State.Options['WhatIf']) { $setup += "`$script:MMTuiWhatIf = `$true`n" }
        $Action = [scriptblock]::Create("param(`$Data, `$Options)`n$setup" +
            "try { & {`n$Action`n} `$Data `$Options }`nfinally { `$script:MMTuiWhatIf = `$false }")
    }

    $State.Log.Clear()
    $State.Log.Add(@{ Text = "$Title"; Style = 'Cyan' })
    $task = @{
        Title        = $Title
        Data         = $Data
        OnComplete   = $OnComplete
        Started      = [datetime]::UtcNow
        Errors       = 0
        OwnsRunspace = $true
    }

    if ($State.Remote) {
        # Remotely, the action runs in ModuleManager's runspace on that computer (see
        # Connect-MMRemote), which has no console, so its output comes back as data.
        $command = Start-MMRemoteCommand -Remote $State.Remote -ScriptBlock $Action -ArgumentList @($Data, $State.Options) -Merge
        $task.PowerShell = $command.PowerShell
        $task.Output = $command.Output
        $task.Handle = $command.Handle
        $task.OwnsRunspace = $false
    }
    elseif ($Elevated) { Start-MMTuiElevatedAction -Task $task -Action $Action -Data $Data -Options $State.Options }
    else { Start-MMTuiLocalAction -Task $task -Action $Action -Data $Data -Options $State.Options }

    $State.Task = $task
    $State.Progress = $null
    $State.LogOpen = $true
    $State.LogScroll = 0
    Set-MMTuiMessage $State "$Title..." 'Cyan'
}
