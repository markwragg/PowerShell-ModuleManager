function Test-MMShouldProcess {
    <#
    .SYNOPSIS
        Asks the calling cmdlet's ShouldProcess, or, in the terminal UI's WhatIf mode, says what would happen.

    .DESCRIPTION
        Returns $Cmdlet.ShouldProcess($Target, $Action), so -WhatIf and -Confirm work as usual.

        When the terminal UI was started with -WhatIf ($script:MMTuiWhatIf, set in the operation's
        runspace by Invoke-MMTuiAction), returns $false after writing a "What if:" line to the
        output pane instead. The cmdlet's own -WhatIf can't be used there: operations run in a
        runspace without a host, where PowerShell discards "What if:" messages.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Confirmation is delegated: the calling cmdlet''s $PSCmdlet is passed in and its ShouldProcess is used.')]
    param([System.Management.Automation.PSCmdlet]$Cmdlet, [string]$Target, [string]$Action)
    if ($script:MMTuiWhatIf) {
        Write-MMTuiOutput "  What if: $Action - $Target" 'Yellow'
        return $false
    }
    $Cmdlet.ShouldProcess($Target, $Action)
}
