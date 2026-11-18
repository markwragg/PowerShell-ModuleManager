function Compare-MMVersion {
    <#
    .SYNOPSIS
        Compares two versions, with optional prerelease labels, using SemVer precedence.

    .DESCRIPTION
        Compares two versions with optional prerelease labels using SemVer precedence rules.
        Returns -1 if A < B, 0 if equal, 1 if A > B.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Position = 0)][AllowNull()][object]$VersionA,
        [Parameter(Position = 1)][AllowNull()][AllowEmptyString()][string]$PrereleaseA,
        [Parameter(Position = 2)][AllowNull()][object]$VersionB,
        [Parameter(Position = 3)][AllowNull()][AllowEmptyString()][string]$PrereleaseB
    )

    $c = (ConvertTo-MMVersion $VersionA).CompareTo((ConvertTo-MMVersion $VersionB))
    if ($c -ne 0) { return [Math]::Sign($c) }

    $aStable = [string]::IsNullOrEmpty($PrereleaseA)
    $bStable = [string]::IsNullOrEmpty($PrereleaseB)
    if ($aStable -and $bStable) { return 0 }
    if ($aStable) { return 1 }   # 1.0.0 > 1.0.0-beta
    if ($bStable) { return -1 }

    $aParts = $PrereleaseA.Split('.')
    $bParts = $PrereleaseB.Split('.')
    $count = [Math]::Min($aParts.Count, $bParts.Count)
    for ($i = 0; $i -lt $count; $i++) {
        $aNum = 0L; $bNum = 0L
        $aIsNum = [long]::TryParse($aParts[$i], [ref]$aNum)
        $bIsNum = [long]::TryParse($bParts[$i], [ref]$bNum)
        if ($aIsNum -and $bIsNum) {
            if ($aNum -ne $bNum) { return [Math]::Sign($aNum - $bNum) }
            continue
        }
        if ($aIsNum) { return -1 }  # numeric identifiers sort before alphanumeric ones
        if ($bIsNum) { return 1 }
        $s = [string]::Compare($aParts[$i], $bParts[$i], [StringComparison]::OrdinalIgnoreCase)
        if ($s -ne 0) { return [Math]::Sign($s) }
    }
    [Math]::Sign($aParts.Count - $bParts.Count)
}
