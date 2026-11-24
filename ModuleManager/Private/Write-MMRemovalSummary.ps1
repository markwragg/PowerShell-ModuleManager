function Write-MMRemovalSummary {
    <#
    .SYNOPSIS
        Says how many module versions were removed and how much disk space that freed.

    .DESCRIPTION
        Reads the tally Remove-MMInstallation keeps (see its -Tally parameter). Writes "Removed 3
        versions, freeing 41.2 MB.", or with -WhatIf, "What if: Removing 3 versions would free
        41.2 MB.", and nothing if nothing was (or would be) removed.

        The message goes to the information stream and is shown, as Write-Host would be, unless
        the calling cmdlet was given -InformationAction, which then decides. So it can be hidden
        (with -InformationAction SilentlyContinue, or 6>$null) without hiding warnings. The
        terminal UI shows it in its output pane.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Tally,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $messages = @()
    foreach ($kind in @(
            @{ Count = $Tally.Removed; Bytes = $Tally.Bytes; Format = 'Removed {0}, freeing {1}.' }
            @{ Count = $Tally.WhatIf; Bytes = $Tally.WhatIfBytes; Format = 'What if: Removing {0} would free {1}.' }
        )) {
        if (-not $kind.Count) { continue }
        $versions = "$($kind.Count) versions"
        if ($kind.Count -eq 1) { $versions = '1 version' }
        $messages += $kind.Format -f $versions, (Format-MMSize $kind.Bytes)
    }
    if (-not $messages) { return }

    $action = 'Continue'
    if ($Cmdlet.MyInvocation.BoundParameters.ContainsKey('InformationAction')) {
        $action = $Cmdlet.MyInvocation.BoundParameters['InformationAction']
    }
    foreach ($m in $messages) { Write-Information -MessageData $m -InformationAction $action }
}
