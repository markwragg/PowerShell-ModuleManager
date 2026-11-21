function Get-MMFolderSize {
    <#
    .SYNOPSIS
        Returns the total size of a folder and everything under it, in bytes, or $null if it can't be read.
    #>
    param([string]$Path)
    $total = 0L
    try {
        $dir = [IO.DirectoryInfo]::new($Path)
        if (-not $dir.Exists) { return $null }
        foreach ($f in $dir.EnumerateFiles('*', [IO.SearchOption]::AllDirectories)) { $total += $f.Length }
    }
    catch {
        Write-Verbose "Could not size $Path : $($_.Exception.Message)"
        return $null
    }
    $total
}
