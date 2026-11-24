function Set-MMTuiReclaimResult {
    <#
    .SYNOPSIS
        Keeps the old versions that removing old versions would remove, and their sizes, for the Reclaim column.

    .DESCRIPTION
        -Found is what Update-MMTuiReclaimable worked out: one object per folder, with Name, Path
        and Bytes. Folders are kept by lower-case module name in $State.Reclaim.ByName, and their
        sizes in $State.Sizes.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI, not system state.')]
    param([hashtable]$State, [object[]]$Found)
    $byName = @{}
    foreach ($f in @($Found)) {
        if ($null -eq $f) { continue }
        $key = ([string]$f.Name).ToLowerInvariant()
        if (-not $byName.ContainsKey($key)) { $byName[$key] = [System.Collections.Generic.List[string]]::new() }
        $byName[$key].Add([string]$f.Path)
        $State.Sizes[[string]$f.Path] = $f.Bytes
    }
    $State.Reclaim = @{ ByName = $byName; Done = $true; PowerShell = $null; Handle = $null }
}
