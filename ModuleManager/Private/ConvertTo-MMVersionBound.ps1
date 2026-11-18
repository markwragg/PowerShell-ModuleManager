function ConvertTo-MMVersionBound {
    <#
    .SYNOPSIS
        Splits a version such as 1.2.3-beta1 into a version and prerelease label for range checks.

    .DESCRIPTION
        Empty text gives $null.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if (-not $Text -or -not $Text.Trim()) { return $null }
    $parts = $Text.Trim().Split('+')[0].Split('-', 2)
    $pre = $null
    if ($parts.Count -gt 1 -and $parts[1]) { $pre = $parts[1] }
    @{ Version = ConvertTo-MMVersion $parts[0]; Prerelease = $pre; Text = $Text.Trim() }
}
