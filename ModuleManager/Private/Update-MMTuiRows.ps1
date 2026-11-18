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
    foreach ($r in $State.Rows) { if ($r.Selected) { $selected[$r.Name] = $true } }

    $modules = @(Group-MMInstallation -Installation @(Get-MMInstalledVersion -Name $o.Name -Scope $o.Scope -IncludeSystem:$o.IncludeSystem))
    $State.Rows = @(foreach ($m in $modules) {
            [pscustomobject]@{
                Name     = $m.Name
                Info     = $m
                Result   = $null
                Status   = 'Unknown'
                Latest   = ''
                Selected = $selected.ContainsKey($m.Name)
                Parent   = $null
                Children = @()
                Indent   = 0
                Last     = $false
                Open     = $false
            }
        })
    Set-MMTuiFamily -Rows $State.Rows
    Update-MMTuiStatus $State
}
