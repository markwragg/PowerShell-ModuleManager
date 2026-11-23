function Remove-MMSessionModule {
    <#
    .SYNOPSIS
        Unloads the modules loaded in this session from the given version folders.

    .DESCRIPTION
        The terminal UI uninstalls in a background runspace, where these modules aren't loaded,
        so it unloads them here first (when the user chooses to). Returns a message for each
        module that couldn't be unloaded.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string[]]$ModuleBase)
    $keys = @{}
    foreach ($b in $ModuleBase) { $keys[(Get-MMPathKey $b)] = $true }
    foreach ($m in @(Get-Module -All)) {
        if (-not $m.ModuleBase -or -not $keys.ContainsKey((Get-MMPathKey $m.ModuleBase))) { continue }
        # In the terminal UI's WhatIf mode, say so in the operation's output instead.
        if ($script:MMTuiWhatIf) { "What if: Remove module from session - $($m.Name) $($m.Version)"; continue }
        if (-not $PSCmdlet.ShouldProcess("$($m.Name) $($m.Version)", 'Remove module from session')) { continue }
        try { Remove-Module -ModuleInfo $m -Force -ErrorAction Stop }
        catch { "Could not unload $($m.Name) $($m.Version): $($_.Exception.Message)" }
    }
}
