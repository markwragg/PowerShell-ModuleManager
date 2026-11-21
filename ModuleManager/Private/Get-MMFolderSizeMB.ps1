function Get-MMFolderSizeMB {
    <#
    .SYNOPSIS
        Returns the total size of a folder and everything under it, in MB.
    #>
    param([string]$Path)
    $bytes = Get-MMFolderSize $Path
    if ($null -eq $bytes) { $bytes = 0 }
    [Math]::Round($bytes / 1MB, 1)
}
