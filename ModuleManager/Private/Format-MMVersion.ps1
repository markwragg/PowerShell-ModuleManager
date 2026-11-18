function Format-MMVersion {
    <#
    .SYNOPSIS
        Formats a version and optional prerelease label as display text, such as 1.2.0-beta1.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([object]$Version, [string]$Prerelease)
    if ($null -eq $Version) { return $null }
    $text = [string]$Version
    if ($Prerelease) { $text = "$text-$Prerelease" }
    $text
}
