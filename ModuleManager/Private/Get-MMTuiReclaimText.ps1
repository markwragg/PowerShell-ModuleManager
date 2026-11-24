function Get-MMTuiReclaimText {
    <#
    .SYNOPSIS
        The Reclaimable cell for a row: the space removing its old versions would free (with its family's, when collapsed).

    .DESCRIPTION
        '...' while it's still being worked out, and blank when there's nothing to remove.
    #>
    [OutputType([string])]
    param([hashtable]$State, [object]$Row)
    $bytes = Get-MMTuiReclaimSize $State $Row
    if ($null -eq $bytes) { return '...' }
    if ($bytes -lt 0) { return '' }
    Format-MMSize $bytes
}
