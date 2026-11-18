function Read-MMInstallMetadata {
    <#
    .SYNOPSIS
        Reads the PSGetModuleInfo.xml that PowerShellGet or PSResourceGet leaves in a module folder.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The noun describes a set of lines/rows (or metadata, which has no singular form).')]
    param([string]$ModuleBase)

    $meta = @{ IsManaged = $false; Repository = $null; InstalledDate = $null; Dependencies = $null }
    $xmlPath = [IO.Path]::Combine($ModuleBase, 'PSGetModuleInfo.xml')
    if (-not [IO.File]::Exists($xmlPath)) { return $meta }
    $meta.IsManaged = $true
    try {
        $text = [IO.File]::ReadAllText($xmlPath)
        $repo = Get-MMXmlValue $text '<S N="Repository">' '</S>'
        if ($repo) { $meta.Repository = [Net.WebUtility]::HtmlDecode($repo) }
        # Either <DT N="InstalledDate">...</DT> or <Obj N="InstalledDate" ...><DT>...</DT> (PowerShellGet)
        $date = $null
        $at = $text.IndexOf('N="InstalledDate"', [StringComparison]::Ordinal)
        if ($at -ge 0) { $date = Get-MMXmlValue $text.Substring($at, [Math]::Min(400, $text.Length - $at)) '>' '<' }
        if ($null -ne $date -and [string]::IsNullOrWhiteSpace($date)) {
            $dt = $text.IndexOf('<DT>', $at, [StringComparison]::Ordinal)
            if ($dt -ge 0 -and $dt - $at -lt 200) { $date = Get-MMXmlValue $text.Substring($dt) '<DT>' '</DT>' }
        }
        if ($date) {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($date, [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
                $meta.InstalledDate = $parsed
            }
        }
        $meta.Dependencies = Read-MMXmlDependency -Text $text
    }
    catch { Write-Debug "Could not read $xmlPath : $_" }
    $meta
}
