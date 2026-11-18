function Get-MMXmlValue {
    <#
    .SYNOPSIS
        Returns the text between an opening and a closing tag in XML text, without parsing the XML.
    #>
    param([string]$Text, [string]$Open, [string]$Close)
    $start = $Text.IndexOf($Open, [StringComparison]::Ordinal)
    if ($start -lt 0) { return $null }
    $start += $Open.Length
    $end = $Text.IndexOf($Close, $start, [StringComparison]::Ordinal)
    if ($end -lt 0) { return $null }
    $Text.Substring($start, $end - $start)
}
