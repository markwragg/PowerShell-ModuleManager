function Add-MMTuiDetailLines {
    <#
    .SYNOPSIS
        Draws the details view: the installed versions of one module, with their scope, repository, install
        date, size and path, and what the version under the cursor depends on and is required by.

    .DESCRIPTION
        Under the module's name and description are its web pages (project and gallery), if it has
        any; under the versions, a panel for the version under the cursor. The versions get the room
        they need, leaving the panel at least three lines when there's space; the panel gets the rest.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The noun describes a set of lines/rows (or metadata, which has no singular form).')]
    param([hashtable]$State, $Lines, [int]$Width, [int]$ListHeight)

    $row = $State.Detail
    $info = $row.Info
    $installs = @($info.Installations)

    # --- Name, versions and total size, and the latest version in the repository
    $sizeText = ''
    $sized = @($installs | Where-Object { $State.Sizes.ContainsKey($_.ModuleBase) -and $null -ne $State.Sizes[$_.ModuleBase] })
    if ($installs.Count -and $sized.Count -eq $installs.Count) {
        $total = 0L; foreach ($i in $installs) { $total += $State.Sizes[$i.ModuleBase] }
        $sizeText = ", $(Format-MMSize $total)"
    }
    $latestText = ''
    if ($row.Latest) { $latestText = "  |  latest in $($row.Result.Repository): $($row.Latest)" }
    $Lines.Add((Format-MMTuiLine @(
                , @(" $($info.Name) ", 'Bold')
                , @("$($installs.Count) version(s) installed$sizeText$latestText", $null)
            ) $Width))

    # The view is $ListHeight + 1 lines: this one, a blank line and the column headings, then the
    # versions. The description and web pages are left out when there wouldn't be room for a version.
    $headLines = 0
    $optional = $ListHeight - 3
    $links = Get-MMTuiDetailLink $State
    # The PowerShell Gallery's warning for an unlisted module, first, as it matters most.
    if ($row.Status -eq 'Unlisted' -and $optional -ge 1) {
        $Lines.Add((Format-MMTuiLine @(, @(" ! The owner has unlisted this package. This could mean that the module is deprecated or shouldn't be used anymore.", 'Yellow')) $Width))
        $headLines++
    }
    # Why a module of a name that's in the repository is Not in repo.
    $note = Get-MMDifferentModuleNote -Name $info.Name -Status $row.Status -Result $row.Result
    if ($note -and $optional - $headLines -ge 1) {
        $Lines.Add((Format-MMTuiLine @(, @(" $note", 'Yellow')) $Width))
        $headLines++
    }
    if ($info.Description -and $optional - $headLines -ge 1) {
        $Lines.Add((Format-MMTuiLine @(, @(" $($info.Description)", 'Dim')) $Width))
        $headLines++
    }

    # --- Web pages. Each can be clicked to open it (see Invoke-MMTuiMouse), or opened with P.
    if (($links.Project -or $links.Gallery) -and $optional - $headLines -ge 1) {
        $segments = [System.Collections.Generic.List[object]]::new()
        $x = 0
        foreach ($l in @(@('Project', $links.Project), @('Gallery', $links.Gallery))) {
            if (-not $l[1]) { continue }
            $label = "   $($l[0]): "
            if (-not $segments.Count) { $label = " $($l[0]): " }
            $segments.Add(@($label, 'Dim'))
            $x += $label.Length
            $segments.Add(@($l[1], 'Link', $l[1]))
            if ($x -lt $Width) { $State.Layout.Links.Add(@{ Y = $Lines.Count; Start = $x; End = [Math]::Min($Width, $x + $l[1].Length); Uri = $l[1] }) }
            $x += $l[1].Length
        }
        $Lines.Add((Format-MMTuiLine $segments.ToArray() $Width))
        $headLines++
    }
    $Lines.Add((' ' * $Width))

    # --- Versions
    $cols = @{ Sel = 5; Version = 18; Scope = 12; Repo = 12; Date = 11; Size = 10; Loaded = 7 }
    $cols.Path = [Math]::Max(10, $Width - 5 - 18 - 12 - 12 - 11 - 10 - 7)
    $Lines.Add((Format-MMTuiLine @(
                , @((Format-MMCell '' $cols.Sel), $null)
                , @((Format-MMCell 'Version' $cols.Version), 'Header')
                , @((Format-MMCell 'Scope' $cols.Scope), 'Header')
                , @((Format-MMCell 'Repository' $cols.Repo), 'Header')
                , @((Format-MMCell 'Installed' $cols.Date), 'Header')
                , @(((Format-MMCell 'Size' ($cols.Size - 2) -Right)), 'Header')
                , @('  ', $null)
                , @((Format-MMCell 'Loaded' $cols.Loaded), 'Header')
                , @((Format-MMCell 'Path' $cols.Path), 'Header')
            ) $Width))

    # --- The panel's content, for the version under the cursor: what it depends on, and what needs it
    $avail = $ListHeight - 2 - $headLines
    $current = $null
    if ($installs.Count) { $current = $installs[[Math]::Max(0, [Math]::Min($State.DCursor, $installs.Count - 1))] }
    $dependsLabel = ' Depends on:  '
    $requiredLabel = ' Required by: '
    $dependsLines = @(); $requiredLines = @(); $dependsItems = @(); $requiredItems = @()
    $wantDepends = 0; $wantRequired = 0
    # Installed versions the publisher has unlisted (see Start-MMGalleryLookup). When the whole
    # module is, the warning above says so, so the panel doesn't repeat it. Not when the
    # repository's module of that name is a different one (see Get-MMUpdateStatus).
    $unlisted = @()
    if ($row.Status -ne 'NotInRepository' -and $row.Result -and $row.Result.PSObject.Properties['UnlistedVersions']) { $unlisted = @($row.Result.UnlistedVersions) }
    $unlistedLine = $null
    if ($current -and $row.Status -ne 'Unlisted' -and $unlisted -contains [string]$current.Version) {
        $unlistedLine = Format-MMTuiLine @(@(' Unlisted:    ', 'Dim'), @("The owner has unlisted this version. This could mean that it's deprecated or shouldn't be used anymore.", 'Yellow')) $Width
    }
    $wantUnlisted = [int][bool]$unlistedLine
    if ($current -and $avail -ge 4) {
        $deps = Get-MMTuiDependencyInfo -State $State -Installation $current
        $dependsItems = @(foreach ($d in $deps.DependsOn) {
                $text = $d.Name
                if ($d.Range) { $text += " $($d.Range)" }
                if (-not $d.Installed) { , @(, @("$text (not found)", 'Yellow')) }
                elseif ($d.Range -eq $d.Installed) { , @(, @($text, $null)) }
                else { , @(@($text, $null), @(" ($($d.Installed))", 'Dim')) }
            })
        # Each module that needs this version, with its two newest versions that do.
        $requiredItems = @(foreach ($r in $deps.RequiredBy) {
                $versions = @($r.Versions)
                $segments = @(, @("$($r.Name) $(@($versions | Select-Object -First 2) -join ' / ')", $null))
                if ($versions.Count -gt 2) { $segments += , @(" +$($versions.Count - 2)", 'Dim') }
                , $segments
            })
        if (-not $deps.Known) {
            $dependsLines = @(Format-MMTuiLine @(@($dependsLabel, 'Dim'), @("not known: only the newest version's manifest is read", 'Dim')) $Width)
        }
        elseif (-not $dependsItems) { $dependsLines = @(Format-MMTuiLine @(@($dependsLabel, 'Dim'), @('nothing', 'Dim')) $Width) }
        if (-not $requiredItems) { $requiredLines = @(Format-MMTuiLine @(@($requiredLabel, 'Dim'), @('nothing installed', 'Dim')) $Width) }
        $wantDepends = $dependsLines.Count
        if (-not $wantDepends) { $wantDepends = @(Format-MMTuiWrappedList -Label $dependsLabel -Items $dependsItems -Width $Width -MaxLines $avail).Count }
        $wantRequired = $requiredLines.Count
        if (-not $wantRequired) { $wantRequired = @(Format-MMTuiWrappedList -Label $requiredLabel -Items $requiredItems -Width $Width -MaxLines $avail).Count }
    }

    # The versions get the room they need, but leave the panel (a divider, then the two lists) the
    # lines it needs, up to a third of the space (and at least three lines); it gets any room left.
    if ($current -and $avail -ge 4) {
        $panelMin = [Math]::Min(1 + $wantUnlisted + $wantDepends + $wantRequired, [Math]::Max(3 + $wantUnlisted, [Math]::Floor($avail / 3)))
        $tableRows = [Math]::Min($installs.Count, $avail - $panelMin)
    }
    else { $tableRows = [Math]::Max(0, $avail) }
    $panelRows = [Math]::Max(0, $avail - $tableRows)

    if ($State.DCursor -lt $State.DTop) { $State.DTop = $State.DCursor }
    if ($State.DCursor -ge $State.DTop + $tableRows) { $State.DTop = $State.DCursor - $tableRows + 1 }
    $State.DTop = [Math]::Max(0, [Math]::Min($State.DTop, $installs.Count - $tableRows))

    # For the mouse (see Invoke-MMTuiMouse): the rows and the [ ] box.
    $State.Layout.DetailTop = $Lines.Count
    $State.Layout.DetailRows = $tableRows
    $State.Layout.CheckWidth = $cols.Sel
    for ($r = 0; $r -lt $tableRows; $r++) {
        $index = $State.DTop + $r
        if ($index -ge $installs.Count) { $Lines.Add((' ' * $Width)); continue }
        $inst = $installs[$index]
        $selected = $State.DSelected.ContainsKey($inst.ModuleBase)
        $mark = '[ ]'; $markStyle = 'Dim'
        if ($selected) { $mark = '[x]'; $markStyle = 'Selected' }
        $date = ''
        if ($inst.InstalledDate) { $date = $inst.InstalledDate.ToString('yyyy-MM-dd') }
        $repo = $inst.Repository
        if (-not $repo) { $repo = '(manual)' }
        $size = ''
        if ($State.Sizes.ContainsKey($inst.ModuleBase)) {
            $size = '?'
            if ($null -ne $State.Sizes[$inst.ModuleBase]) { $size = Format-MMSize $State.Sizes[$inst.ModuleBase] }
        }
        $loaded = ''
        if ($inst.IsLoaded) { $loaded = 'yes' }
        $versionStyle = $null
        $versionText = $inst.Version
        if ($index -eq 0) { $versionStyle = 'Green' }
        if ($unlisted -contains [string]$inst.Version) { $versionText = "$versionText unlisted"; $versionStyle = 'Magenta' }
        $base = ''
        if ($index -eq $State.DCursor -and $State.Mode -eq 'details') { $base = 'Cursor' }
        $Lines.Add((Format-MMTuiLine @(
                    , @((Format-MMCell " $mark" $cols.Sel), $markStyle)
                    , @((Format-MMCell $versionText $cols.Version), $versionStyle)
                    , @((Format-MMCell $inst.Scope $cols.Scope), $null)
                    , @((Format-MMCell $repo $cols.Repo), $null)
                    , @((Format-MMCell $date $cols.Date), $null)
                    , @(((Format-MMCell $size ($cols.Size - 2) -Right) + '  '), $null)
                    , @((Format-MMCell $loaded $cols.Loaded), 'Yellow')
                    , @((Format-MMCell $inst.ModuleBase $cols.Path), 'Dim')
                ) $Width $base))
    }

    # --- The panel. If both lists don't fit, the dependencies get the larger share.
    $panel = [System.Collections.Generic.List[string]]::new()
    if ($panelRows -ge 2) {
        $line = [string][char]0x2500
        $title = " $($current.Version) "
        $panel.Add((Format-MMTuiLine @(@(" $line$line", 'Dim'), @($title, 'Bold'), @(($line * [Math]::Max(0, $Width - $title.Length - 3)), 'Dim')) $Width))
        $room = $panelRows - 1
        if ($unlistedLine) { $panel.Add($unlistedLine); $room-- }
        $maxRequired = 0
        if ($room -ge 2) { $maxRequired = [Math]::Min($wantRequired, [Math]::Max(1, [Math]::Floor($room / 2))) }
        $maxDepends = [Math]::Min($wantDepends, $room - $maxRequired)
        $maxRequired = [Math]::Min($wantRequired, $room - $maxDepends)
        if (-not $dependsLines.Count) { $dependsLines = @(Format-MMTuiWrappedList -Label $dependsLabel -Items $dependsItems -Width $Width -MaxLines $maxDepends) }
        if (-not $requiredLines.Count) { $requiredLines = @(Format-MMTuiWrappedList -Label $requiredLabel -Items $requiredItems -Width $Width -MaxLines $maxRequired) }
        foreach ($l in @($dependsLines | Select-Object -First $maxDepends) + @($requiredLines | Select-Object -First $maxRequired)) { $panel.Add($l) }
    }
    for ($r = 0; $r -lt $panelRows; $r++) {
        if ($r -lt $panel.Count) { $Lines.Add($panel[$r]) } else { $Lines.Add((' ' * $Width)) }
    }
}
