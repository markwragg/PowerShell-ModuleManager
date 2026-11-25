function Read-MMManifest {
    <#
    .SYNOPSIS
        Reads the fields ModuleManager needs from a module manifest, without loading it.

    .DESCRIPTION
        Lightweight manifest reader. Avoids Import-PowerShellDataFile so that scanning
        hundreds of modules stays fast; only reads the fields we display.
        Without -Full only Prerelease (needed to order versions) and GUID (needed to tell
        modules of the same name apart) are read.
    #>
    param([string]$Path, [switch]$Full)

    $result = @{ ModuleVersion = $null; Prerelease = $null; Description = $null; Author = $null; ProjectUri = $null; Guid = $null; RequiredModules = @(); Dependencies = @() }
    $text = $null
    try { $text = [IO.File]::ReadAllText($Path) } catch { return $result }

    $pre = $null
    # Cheap pre-check: most manifests have no Prerelease key at all.
    if ($text.IndexOf('Prerelease', [StringComparison]::OrdinalIgnoreCase) -ge 0) { $pre = Get-MMManifestString $text 'Prerelease' }
    if ($pre) { $pre = $pre.Trim().TrimStart('-') }
    if ($pre) { $result.Prerelease = $pre }

    # The module's identity, to tell apart different modules of the same name (see
    # Group-MMInstallation). Only taken from the start of a line: a GUID inside a one-line
    # RequiredModules entry is the dependency's. Left out when unsure, as a missing GUID is
    # treated as a match.
    $guidWin = Find-MMManifestKey $text 'GUID' -Window 200
    if ($guidWin) {
        $at = $text.IndexOf($guidWin, [StringComparison]::Ordinal)
        $lineStart = $text.LastIndexOf("`n", [Math]::Max(0, $at - 1)) + 1
        if ($at -ge 0 -and [string]::IsNullOrWhiteSpace($text.Substring($lineStart, $at - $lineStart))) {
            $result.Guid = Get-MMManifestString $guidWin 'GUID'
        }
    }
    if (-not $Full) { return $result }

    $result.ModuleVersion = Get-MMManifestString $text 'ModuleVersion'
    $desc = Get-MMManifestString $text 'Description'
    if ($desc) { $result.Description = ($desc -replace '\s+', ' ').Trim() }
    $result.Author = Get-MMManifestString $text 'Author'
    # In PrivateData.PSData; only read when the manifest mentions it.
    if ($text.IndexOf('ProjectUri', [StringComparison]::OrdinalIgnoreCase) -ge 0) { $result.ProjectUri = Get-MMManifestString $text 'ProjectUri' }

    $required = [System.Collections.Generic.List[string]]::new()
    $deps = [System.Collections.Generic.List[object]]::new()
    # RequiredModules is the documented place for dependencies. Some publishers (notably Az) leave it
    # empty and list them in ModuleList instead; there, only entries with a version are treated as
    # dependencies, because plain strings are usually paths to the module's own nested modules.
    foreach ($key in 'RequiredModules', 'ModuleList') {
        $win = Find-MMManifestKey $text $key -Window 20000
        if (-not $win) { continue }
        $block = $script:MMRegex.RequiredBlock.Match($win)
        if ($block.Success) {
            $body = $block.Groups[1].Value
            foreach ($hash in $script:MMRegex.HashLiteral.Matches($body)) {
                $values = @{}
                foreach ($e in $script:MMRegex.HashEntry.Matches($hash.Value)) { $values[$e.Groups[1].Value] = $e.Groups[2].Value }
                if (-not $values['ModuleName']) { continue }
                $hasVersion = $values['ModuleVersion'] -or $values['RequiredVersion'] -or $values['MaximumVersion']
                if ($key -eq 'ModuleList' -and -not $hasVersion) { continue }
                if ($key -eq 'RequiredModules') { $required.Add($values['ModuleName']) }
                $deps.Add((New-MMDependency -Name $values['ModuleName'] -MinimumVersion $values['ModuleVersion'] `
                            -MaximumVersion $values['MaximumVersion'] -RequiredVersion $values['RequiredVersion']))
            }
            if ($key -eq 'RequiredModules') {
                $body = $script:MMRegex.HashLiteral.Replace($body, '')
                foreach ($m in $script:MMRegex.QuotedString.Matches($body)) {
                    $required.Add($m.Groups[1].Value)
                    $deps.Add((New-MMDependency -Name $m.Groups[1].Value))
                }
            }
        }
        elseif ($key -eq 'RequiredModules') {
            $single = $script:MMRegex.StringValue.Match($win)
            if ($single.Success) {
                $n = $single.Groups[1].Value + $single.Groups[2].Value
                $required.Add($n)
                $deps.Add((New-MMDependency -Name $n))
            }
        }
    }
    $unique = [System.Collections.Generic.List[string]]::new()
    foreach ($r in $required) { if ($r -and -not $unique.Contains($r)) { $unique.Add($r) } }
    $result.RequiredModules = $unique.ToArray()
    $result.Dependencies = $deps.ToArray()
    $result
}
