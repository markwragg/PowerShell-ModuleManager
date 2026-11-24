function Add-MMTuiListLines {
    <#
    .SYNOPSIS
        Draws the module list: the column headers and one row per visible module.

    .DESCRIPTION
        In the Multiple versions view, a wide enough list also has a Frees column: how much removing
        the module's old versions would free (for a collapsed family, its members' too), as
        Update-MMTuiReclaim works it out. It shows ... until the sizes are known, and nothing when
        none of the old versions would be removed (they're loaded, or other modules need them).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The noun describes a set of lines/rows (or metadata, which has no singular form).')]
    param([hashtable]$State, $Lines, [int]$Width, [int]$ListHeight)

    $wide = $Width -ge 100
    $cols = [ordered]@{ Sel = 4; Name = 0; Installed = 16; Latest = 16; Count = 0; Frees = 0; Scope = 0; Status = 17 }
    if ($wide) { $cols.Count = 5; $cols.Scope = 13 }
    $showFrees = $wide -and $State.Views[$State.View] -eq 'Multiple versions'
    if ($showFrees) { $cols.Frees = 11 }   # sizes such as "1023.9 MB", and two spaces
    $fixed = 0; foreach ($k in $cols.Keys) { $fixed += $cols[$k] }
    $cols.Name = [Math]::Max(12, $Width - $fixed - 1)

    $header = @(
        , @((Format-MMCell '' $cols.Sel), $null)
        , @(((Format-MMCell 'Name' $cols.Name) + ' '), 'Header')
        , @((Format-MMCell 'Installed' $cols.Installed), 'Header')
        , @((Format-MMCell 'Latest' $cols.Latest), 'Header')
    )
    if ($wide) {
        $header += , @(((Format-MMCell '#' ($cols.Count - 1) -Right) + ' '), 'Header')
        if ($showFrees) { $header += , @(((Format-MMCell 'Frees' ($cols.Frees - 2) -Right) + '  '), 'Header') }
        $header += , @((Format-MMCell 'Scope' $cols.Scope), 'Header')
    }
    $header += , @((Format-MMCell 'Status' $cols.Status), 'Header')

    # For the mouse (see Invoke-MMTuiMouse): the headers of the columns the list can be sorted by,
    # the rows, and the [ ] box.
    $layout = $State.Layout
    $sortBy = @{ Name = 'Name'; Count = 'Versions'; Scope = 'Scope'; Status = 'Status' }
    $layout.SortColumns = [System.Collections.Generic.List[object]]::new()
    $x = 0
    foreach ($col in $cols.Keys) {
        $colWidth = $cols[$col]
        if ($col -eq 'Name') { $colWidth++ }
        if ($colWidth -and $sortBy.ContainsKey($col)) { $layout.SortColumns.Add(@{ Start = $x; End = $x + $colWidth; Sort = $sortBy[$col] }) }
        $x += $colWidth
    }
    $layout.HeaderY = $Lines.Count
    $layout.ListTop = $Lines.Count + 1
    $layout.ListRows = $ListHeight
    $layout.CheckWidth = $cols.Sel
    $Lines.Add((Format-MMTuiLine $header $Width))

    # Keep the cursor in view
    if ($State.Cursor -lt $State.Top) { $State.Top = $State.Cursor }
    if ($State.Cursor -ge $State.Top + $ListHeight) { $State.Top = $State.Cursor - $ListHeight + 1 }
    $State.Top = [Math]::Max(0, [Math]::Min($State.Top, [Math]::Max(0, $State.Visible.Count - $ListHeight)))

    for ($i = 0; $i -lt $ListHeight; $i++) {
        $index = $State.Top + $i
        if ($index -ge $State.Visible.Count) {
            if ($i -eq 0 -and $State.Visible.Count -eq 0) {
                # The first scan, before there's anything to list (see Show-ModuleManager).
                $empty = '  No modules match the current view/filter.'
                if ($State.Scanning) {
                    $empty = '  Scanning installed modules'
                    if ($State.Remote) { $empty += " on $($State.Remote.Name)" }
                    $empty += '... (this can take a few seconds when there are many)'
                }
                $Lines.Add((Format-MMTuiLine @(, @($empty, 'Dim')) $Width))
            }
            else { $Lines.Add((' ' * $Width)) }
            continue
        }
        $row = $State.Visible[$index]
        $info = $row.Info
        $isCursor = ($index -eq $State.Cursor) -and $State.Mode -ne 'filter'
        $mark = '[ ]'; $markStyle = 'Dim'
        if ($row.Selected) { $mark = '[x]'; $markStyle = 'Selected' }
        elseif ($State.DSelected.Count) {
            # Some versions of this module (or, for a collapsed family, of its members) are selected.
            foreach ($member in (Get-MMTuiFamily $State $row)) {
                foreach ($inst in @($member.Info.Installations)) {
                    if ($State.DSelected.ContainsKey($inst.ModuleBase)) { $mark = '[-]'; $markStyle = 'Selected'; break }
                }
                if ($mark -eq '[-]') { break }
            }
        }
        $nameText = $row.Name
        if ($info.IsLoaded) { $nameText = "$nameText *" }
        $statusInfo = $script:MMStatusDisplay[$row.Status]
        if ($State.Group) {
            $glyph = $script:MMGlyph
            if ($row.Indent) {
                $branch = $glyph.Branch
                if ($row.Last) { $branch = $glyph.LastBranch }
                $nameText = "  $branch $nameText"
            }
            elseif ($row.Children.Count) {
                if (-not $row.Open) {
                    $nameText = "$($glyph.Collapsed) $nameText (+$($row.Children.Count))"
                    # A collapsed family shows how many of its modules have updates.
                    $familyUpdates = 0
                    foreach ($member in @($row) + @($row.Children)) { if ($member.Status -eq 'UpdateAvailable') { $familyUpdates++ } }
                    if ($familyUpdates -gt 1 -or ($familyUpdates -eq 1 -and $row.Status -ne 'UpdateAvailable')) {
                        $statusInfo = @("$familyUpdates updates", 'Yellow')
                    }
                }
                else { $nameText = "$($glyph.Expanded) $nameText" }
            }
            else { $nameText = "  $nameText" }
        }
        $latestStyle = $null
        if ($row.Status -eq 'UpdateAvailable') { $latestStyle = 'Yellow' }
        $nameStyle = $null
        if ($row.Selected) { $nameStyle = 'Bold' }

        # The cells, padded here rather than with Format-MMCell, as calling a function for each of
        # them every frame is slow; only text too long for its column goes through it, to be cut.
        $frees = ''; $freesStyle = $null
        if ($showFrees -and $null -ne $State.Reclaim) {
            # The old versions of this module (or its collapsed family) that removing old versions would remove.
            $bytes = 0L; $known = $true; $any = $false
            foreach ($member in (Get-MMTuiFamily $State $row)) {
                foreach ($inst in @($member.Info.Installations)) {
                    if (-not $State.Reclaim.ContainsKey($inst.ModuleBase)) { continue }
                    $any = $true
                    if (-not $State.Sizes.ContainsKey($inst.ModuleBase)) { $known = $false; break }
                    $bytes += [long]$State.Sizes[$inst.ModuleBase]
                }
                if (-not $known) { break }
            }
            if (-not $known) { $frees = '...'; $freesStyle = 'Dim' }
            elseif ($any) { $frees = Format-MMSize $bytes }
        }
        elseif ($showFrees) { $frees = '...'; $freesStyle = 'Dim' }
        $cells = [string[]]@(" $mark", $nameText, $info.Version, $row.Latest, $info.VersionCount, $frees, $info.Scope, $statusInfo[0])
        $cellWidths = $cols.Sel, $cols.Name, $cols.Installed, $cols.Latest, ($cols.Count - 1), ($cols.Frees - 2), $cols.Scope, $cols.Status
        for ($c = 0; $c -lt $cells.Count; $c++) {
            $cw = $cellWidths[$c]
            if ($cw -le 0) { $cells[$c] = '' }
            elseif ($cells[$c].Length -gt $cw) { $cells[$c] = Format-MMCell $cells[$c] $cw }
            elseif ($c -eq 4 -or $c -eq 5) { $cells[$c] = $cells[$c].PadLeft($cw) }   # the version count and size are right-aligned
            else { $cells[$c] = $cells[$c].PadRight($cw) }
        }
        $segs = @(
            , @($cells[0], $markStyle)
            , @(($cells[1] + ' '), $nameStyle)
            , @($cells[2], $null)
            , @($cells[3], $latestStyle)
        )
        if ($wide) {
            $countStyle = $null
            if ($info.VersionCount -gt 1) { $countStyle = 'Magenta' }
            $segs += , @(($cells[4] + ' '), $countStyle)
            if ($showFrees) { $segs += , @(($cells[5] + '  '), $freesStyle) }
            $segs += , @($cells[6], $null)
        }
        $segs += , @($cells[7], $statusInfo[1])
        $base = ''
        if ($isCursor) { $base = 'Cursor' }
        $Lines.Add((Format-MMTuiLine $segs $Width $base))
    }
}
