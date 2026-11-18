function Read-MMTuiKey {
    <#
    .SYNOPSIS
        Returns the next key press without echoing it, or $null if no key is waiting.
    #>
    if (-not [Console]::KeyAvailable) { return $null }
    [Console]::ReadKey($true)
}
