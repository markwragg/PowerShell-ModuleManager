function Get-MMFolderSizeMB {
    <#
    .SYNOPSIS
        Returns the total size of a folder and everything under it, in MB.
    #>
    param([string]$Path)
    $total = 0L
    try {
        $dir = [IO.DirectoryInfo]::new($Path)
        foreach ($f in $dir.EnumerateFiles('*', [IO.SearchOption]::AllDirectories)) { $total += $f.Length }
    }
    catch { Write-Verbose "Could not size $Path : $($_.Exception.Message)" }
    [Math]::Round($total / 1MB, 1)
}
