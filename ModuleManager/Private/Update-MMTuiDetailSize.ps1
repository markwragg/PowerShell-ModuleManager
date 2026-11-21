function Update-MMTuiDetailSize {
    <#
    .SYNOPSIS
        Works out the size of each version of the module in the details view, if it isn't known yet.

    .DESCRIPTION
        Sizes are kept in $State.Sizes by folder, so each is only worked out once until the modules
        are rescanned. It takes a few milliseconds per folder, so it's done straight away rather than
        in the background. On another computer, it runs there, which waits while that computer's
        runspace is busy with the repository check or an operation; the sizes are blank until then.
        Returns $true if any sizes were added.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    [OutputType([bool])]
    param([hashtable]$State)
    if (-not $State.Detail) { return $false }
    $paths = @(foreach ($i in @($State.Detail.Info.Installations)) {
            if ($i.ModuleBase -and -not $State.Sizes.ContainsKey($i.ModuleBase)) { $i.ModuleBase }
        })
    if (-not $paths) { return $false }

    if ($State.Remote) {
        # The remote runspace runs one command at a time.
        if ($State.Job -or $State.Task) { return $false }
        try {
            $sizes = @(Invoke-MMRemote -Remote $State.Remote -ArgumentList (, $paths) -ScriptBlock {
                    param($Paths)
                    foreach ($p in $Paths) { [pscustomobject]@{ Path = $p; Bytes = (Get-MMFolderSize $p) } }
                })
            foreach ($s in $sizes) { $State.Sizes[[string]$s.Path] = $s.Bytes }
        }
        catch { Write-Verbose "Could not size versions on $($State.Remote.Name): $_" }
        # Don't ask again for ones that didn't come back.
        foreach ($p in $paths) { if (-not $State.Sizes.ContainsKey($p)) { $State.Sizes[$p] = $null } }
        return $true
    }
    foreach ($p in $paths) { $State.Sizes[$p] = Get-MMFolderSize $p }
    $true
}
