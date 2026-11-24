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
    $old = Get-MMOldVersion -Installation $all -Name $Name -Keep $Keep -Scope $Scope -Force:$Force

    foreach ($i in $old.System) { Write-Verbose "Skipping $($i.Name) $($i.Version): ships with PowerShell or Windows." }
    foreach ($i in $old.Loaded) {
        Write-Warning "Skipping $($i.Name) $($i.Version): it is loaded in this session. Use -Force to remove it anyway."
    }

    # One summary warning for the versions kept because other installed modules depend on them;
    # details with -Verbose.
    $kept = @($old.Required)
    if ($kept.Count) {
        $dependents = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $kept) {
            Write-Verbose "Keeping $($k.Installation.Name) $($k.Installation.Version): required by $($k.RequiredBy -join '; ')."
            foreach ($r in $k.RequiredBy) {
                $who = ($r -split ' needs ')[0]
                if (-not $dependents.Contains($who)) { $dependents.Add($who) }
            }
        }
        $what = "$($kept[0].Installation.Name) $($kept[0].Installation.Version)"
        if ($kept.Count -gt 1) { $what = "$($kept.Count) old versions" }
        Write-Warning ("Keeping $what because other installed modules depend on them: $(Format-MMRequiredBy $dependents.ToArray() -Limit 4). " +
            'Remove those first, use -Verbose for details, or use -Force to remove them anyway.')
    }

    foreach ($i in $old.Removable) {
        if (Remove-MMInstallation -Installation $i -Cmdlet $Cmdlet -Force:$Force -Tally $Tally) { $i }
    }
}
