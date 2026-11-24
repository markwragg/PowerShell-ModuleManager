function Remove-MMOldVersion {
    <#
    .SYNOPSIS
        Removes all but the newest -Keep versions of the named modules (Uninstall-ManagedModule -OldVersions).

    .DESCRIPTION
        Versions that ship with PowerShell or Windows are never removed. Loaded versions, and old
        versions that other installed modules depend on, are skipped with a warning unless -Force
        is used. All scopes are counted when working out which versions are newest, but only
        versions in -Scope are removed. Outputs the installations that were removed.
    #>
    [CmdletBinding()]
    [OutputType('ModuleManager.InstalledVersion')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'ShouldProcess is called by Remove-MMInstallation, using the calling cmdlet passed in -Cmdlet.')]
    param(
        [string[]]$Name,
        [int]$Keep = 1,
        [string[]]$Scope,
        [switch]$Force,
        [hashtable]$Tally,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $all = @(Get-MMInstalledVersion -IncludeSystem)
    $modules = @(Group-MMInstallation -Installation @($all | Where-Object { Test-MMNameMatch $_.Name $Name }))

    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($m in $modules) {
        if ($m.VersionCount -le $Keep) { continue }
        foreach ($i in @($m.Installations | Select-Object -Skip $Keep)) {
            if ($Scope -and $Scope -notcontains $i.Scope) { continue }
            if ($i.Scope -eq 'System') {
                Write-Verbose "Skipping $($i.Name) $($i.Version): ships with PowerShell or Windows."
                continue
            }
            if ($i.IsLoaded -and -not $Force) {
                Write-Warning "Skipping $($i.Name) $($i.Version): it is loaded in this session. Use -Force to remove it anyway."
                continue
            }
            $candidates.Add($i)
        }
    }
    if (-not $candidates.Count) { return }

    # Keep old versions that other installed modules still depend on, such as the exact
    # Az.* versions each older Az rollup pins. One summary warning; details with -Verbose.
    $required = @{}
    if (-not $Force) {
        $kept = @(Get-MMRequiredInstallation -Removing $candidates.ToArray() -AllInstallation $all)
        $dependents = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $kept) {
            $required[(Get-MMPathKey $k.Installation.ModuleBase)] = $true
            Write-Verbose "Keeping $($k.Installation.Name) $($k.Installation.Version): required by $($k.RequiredBy -join '; ')."
            foreach ($r in $k.RequiredBy) {
                $who = ($r -split ' needs ')[0]
                if (-not $dependents.Contains($who)) { $dependents.Add($who) }
            }
        }
        if ($kept.Count) {
            $what = "$($kept[0].Installation.Name) $($kept[0].Installation.Version)"
            if ($kept.Count -gt 1) { $what = "$($kept.Count) old versions" }
            Write-Warning ("Keeping $what because other installed modules depend on them: $(Format-MMRequiredBy $dependents.ToArray() -Limit 4). " +
                'Remove those first, use -Verbose for details, or use -Force to remove them anyway.')
        }
    }

    foreach ($i in $candidates) {
        if ($required.ContainsKey((Get-MMPathKey $i.ModuleBase))) { continue }
        if (Remove-MMInstallation -Installation $i -Cmdlet $Cmdlet -Force:$Force -Tally $Tally) { $i }
    }
}
