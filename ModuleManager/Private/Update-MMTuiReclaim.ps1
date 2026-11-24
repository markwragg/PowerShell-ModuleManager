function Update-MMTuiReclaim {
    <#
    .SYNOPSIS
        Works out, a little at a time, how much removing old versions would free, for the Multiple versions view.

    .DESCRIPTION
        The Frees column (see Add-MMTuiListLines) shows the size of the old versions removing old
        versions (O) would remove: those Uninstall-ManagedModule -OldVersions removes, worked out for
        every module at once, as when A selects every module with old versions and O removes them.
        So it leaves out versions loaded in the session and old versions that modules staying
        installed depend on.

        Which versions those are ($State.Reclaim, by folder) is worked out once per scan. Their sizes
        go into $State.Sizes, shared with the details view, so each folder is only read once. Folders
        are sized for the rows in view first, then the rest, for up to -BudgetMs each time this is
        called, so the UI keeps responding while there are many to read; on another computer, a batch
        at a time, when its runspace isn't busy. Does nothing outside the Multiple versions view, or
        once every size is known ($State.ReclaimDone, until the next scan).

        Returns $true if anything new is known, so the list should be drawn again.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    [OutputType([bool])]
    param([hashtable]$State, [int]$BudgetMs = 40, [int]$RemoteBatch = 50)

    if ($State.ReclaimDone -or $State.Mode -ne 'list' -or $State.Views[$State.View] -ne 'Multiple versions') { return $false }
    # The remote runspace runs one command at a time.
    $remoteBusy = $State.Remote -and ($State.Job -or $State.Task)
    $changed = $false

    if ($null -eq $State.Reclaim) {
        if ($remoteBusy) { return $false }
        $bases = @()
        try {
            if ($State.Remote) {
                $bases = @(Invoke-MMRemote -Remote $State.Remote -ScriptBlock {
                        (Get-MMOldVersion -Installation @(Get-MMInstalledVersion -IncludeSystem)).Removable | ForEach-Object { $_.ModuleBase }
                    })
            }
            else { $bases = @((Get-MMOldVersion -Installation @(Get-MMInstalledVersion -IncludeSystem)).Removable | ForEach-Object { $_.ModuleBase }) }
        }
        catch { Write-Verbose "Could not work out which old versions can be removed: $_" }
        $State.Reclaim = @{}
        foreach ($b in $bases) { $State.Reclaim[[string]$b] = $true }
        $changed = $true
    }

    $pending = [System.Collections.Generic.List[string]]::new()
    foreach ($b in $State.Reclaim.Keys) { if (-not $State.Sizes.ContainsKey($b)) { $pending.Add($b) } }
    if (-not $pending.Count) { $State.ReclaimDone = $true; return $changed }
    if ($remoteBusy) { return $changed }

    # The rows in view first (with the members of collapsed families), then the rest.
    $inView = @{}
    $end = [Math]::Min($State.Visible.Count, $State.Top + [Math]::Max(1, $State.ListHeight))
    for ($r = $State.Top; $r -lt $end; $r++) {
        foreach ($member in (Get-MMTuiFamily $State $State.Visible[$r])) {
            foreach ($i in @($member.Info.Installations)) { $inView[[string]$i.ModuleBase] = $true }
        }
    }
    $ordered = @($pending | Where-Object { $inView.ContainsKey($_) }) + @($pending | Where-Object { -not $inView.ContainsKey($_) })

    if ($State.Remote) {
        $batch = @($ordered | Select-Object -First $RemoteBatch)
        try {
            $sizes = @(Invoke-MMRemote -Remote $State.Remote -ArgumentList (, $batch) -ScriptBlock {
                    param($Paths)
                    foreach ($p in $Paths) { [pscustomobject]@{ Path = $p; Bytes = (Get-MMFolderSize $p) } }
                })
            foreach ($s in $sizes) { $State.Sizes[[string]$s.Path] = $s.Bytes }
        }
        catch { Write-Verbose "Could not size old versions on $($State.Remote.Name): $_" }
        # Don't ask again for ones that didn't come back.
        foreach ($p in $batch) { if (-not $State.Sizes.ContainsKey($p)) { $State.Sizes[$p] = $null } }
        return $true
    }

    $clock = [Diagnostics.Stopwatch]::StartNew()
    foreach ($p in $ordered) {
        $State.Sizes[$p] = Get-MMFolderSize $p
        if ($clock.ElapsedMilliseconds -ge $BudgetMs) { break }
    }
    $true
}
