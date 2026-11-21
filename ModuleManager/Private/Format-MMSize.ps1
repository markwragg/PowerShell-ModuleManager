function Format-MMSize {
    <#
    .SYNOPSIS
        Formats a size in bytes as short text, such as 812 KB, 14.1 MB or 1.25 GB.
    #>
    [OutputType([string])]
    param([AllowNull()][object]$Bytes)
    if ($null -eq $Bytes) { return '' }
    $b = [double]$Bytes
    $culture = [Globalization.CultureInfo]::InvariantCulture
    if ($b -ge 1GB) { return ($b / 1GB).ToString('0.00', $culture) + ' GB' }
    if ($b -ge 1MB) { return ($b / 1MB).ToString('0.0', $culture) + ' MB' }
    if ($b -ge 1KB) { return ($b / 1KB).ToString('0', $culture) + ' KB' }
    "$([long]$b) B"
}
