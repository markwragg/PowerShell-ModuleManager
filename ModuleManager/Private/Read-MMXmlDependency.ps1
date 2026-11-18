function Read-MMXmlDependency {
    <#
    .SYNOPSIS
        Reads the dependencies, with their version ranges, from PSGetModuleInfo.xml text.

    .DESCRIPTION
        Reads the Dependencies list from the text of a PSGetModuleInfo.xml file. Returns $null if
        the file has no Dependencies entry (so the caller can fall back to the manifest), or an
        array (possibly empty) of dependency objects. The array is returned as a single object so
        that an empty list survives: assign the result rather than wrapping the call in @().

        Handles both formats:
          PSResourceGet  <S N="Name">Az.Accounts</S> <Obj N="VersionRange">...<ToString>[5.4.0, )</ToString>
          PowerShellGet  <DCT> Name / MinimumVersion / MaximumVersion / RequiredVersion entries </DCT>
    #>
    [CmdletBinding()]
    param([string]$Text)

    $start = $Text.IndexOf('N="Dependencies"', [StringComparison]::Ordinal)
    if ($start -lt 0) { return $null }
    $open = $Text.LastIndexOf('<', $start)
    if ($open -lt 0 -or $Text.IndexOf('<Obj', $open, [StringComparison]::Ordinal) -ne $open) { return , @() }

    # Find the matching </Obj> so we only look inside the Dependencies object.
    $depth = 0
    $end = $Text.Length
    $m = $script:MMRegex.XmlObjTag.Match($Text, $open)
    while ($m.Success) {
        if ($m.Value.StartsWith('</')) { $depth-- }
        elseif (-not $m.Groups[1].Value) { $depth++ }
        elseif ($depth -eq 0) { return , @() }   # <Obj N="Dependencies" ... />
        if ($depth -eq 0) { $end = $m.Index + $m.Length; break }
        $m = $m.NextMatch()
    }
    $section = $Text.Substring($open, $end - $open)

    $deps = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $script:MMRegex.XmlRangeDep.Matches($section)) {
        $deps.Add((New-MMDependency -Name ([Net.WebUtility]::HtmlDecode($d.Groups[1].Value)) `
                    -VersionRange ([Net.WebUtility]::HtmlDecode($d.Groups[2].Value))))
    }
    if ($deps.Count -eq 0) {
        foreach ($dict in $script:MMRegex.XmlDictionary.Matches($section)) {
            $values = @{}
            foreach ($e in $script:MMRegex.XmlDictEntry.Matches($dict.Groups[1].Value)) {
                $values[$e.Groups[1].Value] = [Net.WebUtility]::HtmlDecode($e.Groups[2].Value)
            }
            if (-not $values['Name']) { continue }
            $deps.Add((New-MMDependency -Name $values['Name'] -MinimumVersion $values['MinimumVersion'] `
                        -MaximumVersion $values['MaximumVersion'] -RequiredVersion $values['RequiredVersion']))
        }
    }
    , $deps.ToArray()
}
