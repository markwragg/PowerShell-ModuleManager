function Update-MMTuiReclaimable {
    <#
    .SYNOPSIS
        Works out how much space removing each module's old versions would free, for the Multiple versions view.

    .DESCRIPTION
        The old versions counted are the ones removing old versions (O) would remove, as worked out
        by Get-MMOldVersion: not the newest, not versions loaded in the session, and not old versions
        that other installed modules depend on. They're kept in $State.Reclaim.ByName (folders by
        lower-case module name) until the modules are rescanned, and their sizes in $State.Sizes,
        which the details view shares (see Set-MMTuiReclaimResult).

        Only done in the Multiple versions view. Checking dependencies takes a second or two with
        many modules installed, and sizing the folders reads every file, so locally it's done in a
        background runspace, and the column shows ... until it's finished; this collects it. On
        another computer, it's done there in one call, which waits until that computer's runspace
        isn't busy with the repository check or an operation. Returns $true when the results are in.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI, not system state.')]
    [OutputType([bool])]
    param([hashtable]$State)

    if ($State.Reclaim -and $State.Reclaim.Done) { return $false }
    $running = $State.Reclaim -and $State.Reclaim.PowerShell
    if (-not $running -and $State.Views[$State.View] -ne 'Multiple versions') { return $false }

    if ($State.Remote) {
        # The remote runspace runs one command at a time.
        if ($State.Job -or $State.Task) { return $false }
        $found = @()
        try {
            $found = @(Invoke-MMRemote -Remote $State.Remote -ScriptBlock {
                    $old = Get-MMOldVersion -Installation @(Get-MMInstalledVersion -IncludeSystem)
                    foreach ($i in $old.Removable) { [pscustomobject]@{ Name = $i.Name; Path = $i.ModuleBase; Bytes = (Get-MMFolderSize $i.ModuleBase) } }
                })
        }
        catch { Write-Verbose "Could not work out the reclaimable space on $($State.Remote.Name): $_" }
        Set-MMTuiReclaimResult $State $found
        return $true
    }

    if (-not $State.Reclaim) {
        # Dependencies are checked against every installed module. When the UI lists them all, its
        # rows have them, so there's no need to scan again.
        $o = $State.Options
        $installs = $null
        if ((@($o.Name) -join '') -eq '*' -and -not $o.Scope) { $installs = @(foreach ($r in $State.Rows) { @($r.Info.Installations) }) }

        $iss = [initialsessionstate]::CreateDefault2()
        if (Test-MMIsWindows) {
            try { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch { Write-Debug $_ }
        }
        $ps = [powershell]::Create($iss)
        [void]$ps.AddScript({
                param($ModulePath, $Installs)
                $module = Import-Module $ModulePath -PassThru -DisableNameChecking
                & $module {
                    param($Installs)
                    if ($null -eq $Installs) { $Installs = @(Get-MMInstalledVersion -IncludeSystem) }
                    $old = Get-MMOldVersion -Installation $Installs
                    foreach ($i in $old.Removable) { [pscustomobject]@{ Name = $i.Name; Path = $i.ModuleBase; Bytes = (Get-MMFolderSize $i.ModuleBase) } }
                } $Installs
            }).AddArgument($MyInvocation.MyCommand.Module.Path).AddArgument($installs)
        $State.Reclaim = @{ ByName = @{}; Done = $false; PowerShell = $ps; Handle = $ps.BeginInvoke() }
        return $false
    }

    if (-not $State.Reclaim.Handle.IsCompleted) { return $false }
    $ps = $State.Reclaim.PowerShell
    $found = @()
    try { $found = @($ps.EndInvoke($State.Reclaim.Handle)) }
    catch { Write-Verbose "Could not work out the reclaimable space: $_" }
    finally { $ps.Dispose() }
    Set-MMTuiReclaimResult $State $found
    $true
}
