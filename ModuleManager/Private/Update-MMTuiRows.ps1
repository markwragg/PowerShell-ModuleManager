function Update-MMTuiRows {
    <#
    .SYNOPSIS
        Rescans installed modules and rebuilds the terminal UI rows, keeping the selection.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The noun describes a set of lines/rows (or metadata, which has no singular form).')]
    param([hashtable]$State)
    $o = $State.Options
    $selected = @{}
    foreach ($r in $State.Rows) { if ($r.Selected) { $selected[$r.Key] = $true } }

    if ($State.Remote) {
        $modules = @(Invoke-MMRemote -Remote $State.Remote -ArgumentList $o.Name, $o.Scope, $o.IncludeSystem -ScriptBlock {
                param($Name, $Scope, $IncludeSystem)
                Group-MMInstallation -Installation @(Get-MMInstalledVersion -Name $Name -Scope $Scope -IncludeSystem:$IncludeSystem)
            })
    }
    else { $modules = @(Group-MMInstallation -Installation @(Get-MMInstalledVersion -Name $o.Name -Scope $o.Scope -IncludeSystem:$o.IncludeSystem)) }
    $State.Rows = @(foreach ($m in $modules) {
            # Unique, unlike Name: different modules can share a name (see Group-MMInstallation).
            $key = $m.Name.ToLowerInvariant()
            if ($m.PSObject.Properties['Key'] -and $m.Key) { $key = $m.Key }
            [pscustomobject]@{
                Name     = $m.Name
                Key      = $key
                Info     = $m
                Result   = $null
                Status   = 'Unknown'
                Latest   = ''
                Selected = $selected.ContainsKey($key)
                Parent   = $null
                Children = @()
                Indent   = 0
                Last     = $false
                Open     = $false
            }
        })
    Set-MMTuiFamily -Rows $State.Rows
    # Sizes and dependencies are worked out again, for what's installed now.
    $State.Sizes = @{}
    Stop-MMTuiReclaimable $State
    $State.DepIndex = $null
    $State.DepInfo = @{}

    # Forget selected versions that are no longer installed.
    if ($State.DSelected.Count) {
        $installed = @{}
        foreach ($m in $modules) { foreach ($i in @($m.Installations)) { $installed[$i.ModuleBase] = $true } }
        foreach ($base in @($State.DSelected.Keys)) { if (-not $installed.ContainsKey($base)) { $State.DSelected.Remove($base) } }
    }
    Update-MMTuiStatus $State
}
