function Get-MMTuiTarget {
    <#
    .SYNOPSIS
        Returns the rows a terminal UI action applies to: the selection, or else the row under the cursor.

    .DESCRIPTION
        Selected rows, or the row under the cursor if nothing is selected (the whole family if
        it's a collapsed family).
    #>
    param([hashtable]$State)
    $sel = @($State.Rows | Where-Object Selected)
    if ($sel) { return $sel }
    if ($State.Visible.Count) { return @(Get-MMTuiFamily $State $State.Visible[$State.Cursor]) }
    @()
}
