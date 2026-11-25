function Split-MMInstallationSet {
    <#
    .SYNOPSIS
        Splits the installed versions of one name into modules by GUID (see Group-MMInstallation).
        Returns @{ Items; Guids; Main } per module.
    #>
    param([object[]]$Installation)

    $normal = {
        param($Text)
        $g = [guid]::Empty
        if ([guid]::TryParse([string]$Text, [ref]$g)) { $g.ToString() }
    }
    $sets = [System.Collections.Generic.List[object]]::new()
    $unknown = [System.Collections.Generic.List[object]]::new()
    $setOf = @{}

    $managed = @($Installation | Where-Object { $_.Repository })
    if ($managed) {
        $set = @{ Items = [System.Collections.Generic.List[object]]::new(); Guids = [System.Collections.Generic.List[string]]::new(); Main = $true }
        foreach ($i in $managed) {
            $set.Items.Add($i)
            $g = & $normal $i.Guid
            if ($g -and -not $set.Guids.Contains($g)) { $set.Guids.Add($g) }
        }
        $sets.Add($set)
    }
    foreach ($i in $Installation) {
        if ($i.Repository) { continue }
        $g = & $normal $(if ($i.PSObject.Properties['Guid']) { $i.Guid })
        if (-not $g) { $unknown.Add($i); continue }
        $set = $null
        foreach ($s in $sets) { if ($s.Guids.Contains($g)) { $set = $s; break } }
        if (-not $set) {
            $set = @{ Items = [System.Collections.Generic.List[object]]::new(); Guids = [System.Collections.Generic.List[string]]::new(); Main = $false }
            $set.Guids.Add($g)
            $sets.Add($set)
        }
        $set.Items.Add($i)
        $setOf[$i.ModuleBase] = $set
    }

    if (-not $sets.Count) {
        $sets.Add(@{ Items = $unknown; Guids = [System.Collections.Generic.List[string]]::new(); Main = $true })
        return $sets.ToArray()
    }
    # With nothing installed from a repository, the main module is the one with the newest version.
    $main = @($sets | Where-Object { $_.Main })[0]
    if (-not $main) {
        foreach ($i in @(Get-MMSortedInstallation @($Installation | Where-Object { $setOf.ContainsKey($_.ModuleBase) }))) { $main = $setOf[$i.ModuleBase]; break }
        $main.Main = $true
    }
    foreach ($i in $unknown) { $main.Items.Add($i) }
    $sets.ToArray()
}
