function Get-MMSortedInstallation {
    <#
    .SYNOPSIS
        Sorts installed versions newest first (or oldest first with -Ascending).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][AllowEmptyCollection()][object[]]$InputObject,
        [switch]$Ascending
    )
    if (-not $InputObject) { return }
    if (@($InputObject).Count -eq 1) { return $InputObject }
    # Keys: normalised version, then stable-before-prerelease, then prerelease label with
    # numeric runs zero-padded so that 'preview10' sorts after 'preview9' (SemVer-like).
    $InputObject | Sort-Object -Descending:(-not $Ascending) -Property @(
        @{ Expression = { ConvertTo-MMVersion $_.ModuleVersion } }
        @{ Expression = { [string]::IsNullOrEmpty($_.Prerelease) } }
        @{ Expression = { $script:MMDigitRun.Replace([string]$_.Prerelease, { param($m) $m.Value.PadLeft(10, '0') }) } }
    )
}
