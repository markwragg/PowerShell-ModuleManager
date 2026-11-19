function Request-MMTuiMove {
    <#
    .SYNOPSIS
        Asks which scope to move module versions to (CurrentUser or AllUsers), then moves them.

    .DESCRIPTION
        Moves everything selected (modules and versions), or else the module under the cursor in
        the list or the version under the cursor in the details view. When every version is in
        one scope, the other is offered with y; when they're in both, a moves them to AllUsers
        and c to CurrentUser.

        Versions that ship with PowerShell or Windows, and loaded versions, are skipped and the
        output says why.
    #>
    param([hashtable]$State, [switch]$Detail)
    if (Test-MMTuiBusy $State) { return }

    $versions = @(Get-MMTuiSelectedVersion $State)
    if ($Detail) {
        $installs = $versions
        if (-not $installs) { $installs = @(@($State.Detail.Info.Installations)[$State.DCursor]) }
    }
    else {
        $rows = @($State.Rows | Where-Object Selected)
        if (-not $rows -and -not $versions) { $rows = @(Get-MMTuiTarget $State) }
        $seen = @{}
        $installs = @(foreach ($i in @(@($rows | ForEach-Object { $_.Info.Installations }) + $versions)) {
                if ($i -and -not $seen.ContainsKey($i.ModuleBase)) { $seen[$i.ModuleBase] = $true; $i }
            })
    }
    if (-not $installs) { return }
    $What = Format-MMTuiTarget $State $installs

    # Remotely, the remote session's own rights apply, and the move reports it if they're not enough.
    if (-not $State.Remote -and -not (Test-MMIsAdmin)) {
        Set-MMTuiMessage $State "Moving modules to or from AllUsers needs an elevated session: run PowerShell as administrator." 'Yellow'
        return
    }

    $movable = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    foreach ($i in $installs) {
        if ($i.Scope -eq 'System') { $skipped.Add("$($i.Name) $($i.Version): it ships with PowerShell or Windows.") }
        elseif ($i.IsLoaded) { $skipped.Add("$($i.Name) $($i.Version): it is loaded in this session. Move it from a new session.") }
        else { $movable.Add($i) }
    }
    if (-not $movable.Count) {
        Set-MMTuiMessage $State "Can't move $What`: $($skipped[0])" 'Yellow'
        return
    }

    $scopes = @($movable | ForEach-Object { $_.Scope } | Select-Object -Unique)
    if ($scopes.Count -eq 1 -and $scopes[0] -in 'CurrentUser', 'AllUsers') {
        $to = if ($scopes[0] -eq 'CurrentUser') { 'AllUsers' } else { 'CurrentUser' }
        $prompt = "Move $What to $to ?"
        $choices = 'y'
        $destination = @{ y = $to }
    }
    else {
        $prompt = "Move $What to: a AllUsers, c CurrentUser ?"
        $choices = 'ac'
        $destination = @{ a = 'AllUsers'; c = 'CurrentUser' }
    }
    if ($skipped.Count) { $prompt += " Skips $($skipped.Count) version(s) that can't be moved." }

    $data = @{
        What        = $What
        Bases       = @($movable | ForEach-Object { $_.ModuleBase })
        Skipped     = $skipped.ToArray()
        Destination = $destination
    }
    Request-MMTuiConfirm $State $prompt -Data $data -Choices $choices -Action {
        param($State, $Data, $Choice)
        $run = @{ Bases = $Data.Bases; Skipped = $Data.Skipped; Destination = $Data.Destination[$Choice] }
        Invoke-MMTuiAction $State "Moving $($Data.What) to $($run.Destination)" -Data $run -Action {
            param($Data)
            Move-ManagedModule -ModuleBase $Data.Bases -Destination $Data.Destination -Confirm:$false -Verbose
            foreach ($s in $Data.Skipped) { Write-MMTuiOutput "  Skipped  $s" 'Yellow' }
        } -OnComplete {
            param($State)
            $State.DSelected = @{}
            foreach ($r in $State.Rows) { $r.Selected = $false }
        }
    }
}
