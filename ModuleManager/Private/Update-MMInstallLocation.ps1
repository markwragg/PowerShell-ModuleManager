function Update-MMInstallLocation {
    <#
    .SYNOPSIS
        Updates the install location in a moved module's PSGetModuleInfo.xml.

    .DESCRIPTION
        PSResourceGet records the module folder root as InstalledLocation, and PowerShellGet the
        version folder. Rewrites whichever it is to the new location, keeping the file's encoding.
        Modules without an install record are left alone.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Part of a move the calling cmdlet already confirmed.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'NewRoot', Justification = 'Used in the regex replacement scriptblock, which the rule does not look inside.')]
    param(
        [Parameter(Mandatory)][string]$ModuleBase,
        [Parameter(Mandatory)][string]$OldModuleBase,
        [Parameter(Mandatory)][string]$OldRoot,
        [Parameter(Mandatory)][string]$NewRoot
    )

    $xmlPath = [IO.Path]::Combine($ModuleBase, 'PSGetModuleInfo.xml')
    if (-not [IO.File]::Exists($xmlPath)) { return }
    try {
        $reader = [IO.StreamReader]::new($xmlPath, $true)
        try {
            $text = $reader.ReadToEnd()
            $encoding = $reader.CurrentEncoding
        }
        finally { $reader.Dispose() }

        $oldBaseKey = Get-MMPathKey $OldModuleBase
        $oldRootKey = Get-MMPathKey $OldRoot
        $state = @{ Changed = $false }
        $updated = [regex]::Replace($text, '(<S N="InstalledLocation">)([^<]*)(</S>)', {
                param($m)
                $old = [Net.WebUtility]::HtmlDecode($m.Groups[2].Value)
                $key = Get-MMPathKey $old
                $new = $null
                if ($key -eq $oldBaseKey) { $new = $ModuleBase }
                elseif ($key -eq $oldRootKey) { $new = $NewRoot }
                elseif (Test-MMPathUnder $old $OldRoot) { $new = Join-Path $NewRoot $old.Substring($OldRoot.Length).TrimStart('\', '/') }
                if (-not $new) { return $m.Value }
                $state.Changed = $true
                $m.Groups[1].Value + [Net.WebUtility]::HtmlEncode($new) + $m.Groups[3].Value
            })
        if ($state.Changed) { [IO.File]::WriteAllText($xmlPath, $updated, $encoding) }
    }
    catch { Write-Warning "Could not update the install location in $xmlPath`: $($_.Exception.Message)" }
}
