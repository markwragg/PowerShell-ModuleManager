function Test-MMTuiReclaimShown {
    <#
    .SYNOPSIS
        Whether the module list has its Reclaim column: in the Multiple versions view, on a screen at least 100 wide.

    .DESCRIPTION
        Only then can the list be sorted by it (S skips it otherwise, and Update-MMTuiVisible goes
        back to sorting by name). -Width defaults to the width of the last frame drawn; before the
        first one, when it isn't known yet, only the view counts.
    #>
    [OutputType([bool])]
    param([hashtable]$State, [int]$Width = $State.Width)
    ($State.Views[$State.View] -eq 'Multiple versions') -and ($Width -eq 0 -or $Width -ge 100)
}
