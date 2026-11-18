function Add-MMTuiDetailLines {
    <#
    .SYNOPSIS
        Draws the details view: the installed versions of one module, with their scope, repository, install
        date and path.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The noun describes a set of lines/rows (or metadata, which has no singular form).')]
    param([hashtable]$State, $Lines, [int]$Width, [int]$ListHeight)

    $row = $State.Detail
    $info = $row.Info
    $installs = @($info.Installations)

    $latestText = ''
    if ($row.Latest) { $latestText = "  |  latest in $($row.Result.Repository): $($row.Latest)" }
    $Lines.Add((Format-MMTuiLine @(
                , @(" $($info.Name) ", 'Bold')
                , @("$($installs.Count) version(s) installed$latestText", $null)
            ) $Width))

    $descLines = 0
    if ($info.Description) {
        $Lines.Add((Format-MMTuiLine @(, @(" $($info.Description)", 'Dim')) $Width))
        $descLines = 1
    }
    $Lines.Add((' ' * $Width))

    $cols = @{ Sel = 4; Version = 18; Scope = 12; Repo = 12; Date = 11; Loaded = 7 }
    $cols.Path = [Math]::Max(10, $Width - 4 - 18 - 12 - 12 - 11 - 7)
    $Lines.Add((Format-MMTuiLine @(
                , @((Format-MMCell '' $cols.Sel), $null)
                , @((Format-MMCell 'Version' $cols.Version), 'Header')
                , @((Format-MMCell 'Scope' $cols.Scope), 'Header')
                , @((Format-MMCell 'Repository' $cols.Repo), 'Header')
                , @((Format-MMCell 'Installed' $cols.Date), 'Header')
                , @((Format-MMCell 'Loaded' $cols.Loaded), 'Header')
                , @((Format-MMCell 'Path' $cols.Path), 'Header')
            ) $Width))

    $avail = $ListHeight - 2 - $descLines
    if ($State.DCursor -lt $State.DTop) { $State.DTop = $State.DCursor }
    if ($State.DCursor -ge $State.DTop + $avail) { $State.DTop = $State.DCursor - $avail + 1 }

    for ($i = 0; $i -lt $avail; $i++) {
        $index = $State.DTop + $i
        if ($index -ge $installs.Count) { $Lines.Add((' ' * $Width)); continue }
        $inst = $installs[$index]
        $selected = $State.DSelected.ContainsKey($inst.ModuleBase)
        $mark = '[ ]'; $markStyle = 'Dim'
        if ($selected) { $mark = '[x]'; $markStyle = 'Selected' }
        $date = ''
        if ($inst.InstalledDate) { $date = $inst.InstalledDate.ToString('yyyy-MM-dd') }
        $repo = $inst.Repository
        if (-not $repo) { $repo = '(manual)' }
        $loaded = ''
        if ($inst.IsLoaded) { $loaded = 'yes' }
        $versionStyle = $null
        if ($index -eq 0) { $versionStyle = 'Green' }
        $base = ''
        if ($index -eq $State.DCursor -and $State.Mode -eq 'details') { $base = 'Cursor' }
        $Lines.Add((Format-MMTuiLine @(
                    , @((Format-MMCell " $mark" $cols.Sel), $markStyle)
                    , @((Format-MMCell $inst.Version $cols.Version), $versionStyle)
                    , @((Format-MMCell $inst.Scope $cols.Scope), $null)
                    , @((Format-MMCell $repo $cols.Repo), $null)
                    , @((Format-MMCell $date $cols.Date), $null)
                    , @((Format-MMCell $loaded $cols.Loaded), 'Yellow')
                    , @((Format-MMCell $inst.ModuleBase $cols.Path), 'Dim')
                ) $Width $base))
    }
}
