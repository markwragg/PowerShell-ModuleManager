function Uninstall-OldModuleVersion {
    <#
    .SYNOPSIS
        Removes older versions of modules, keeping only the newest.

    .DESCRIPTION
        Updating a module installs the new version alongside the old one, so versions
        build up over time. This removes all but the newest -Keep versions of each module.

        Versions that ship with PowerShell or Windows are never removed. Versions loaded in
        the current session, and old versions that another installed module depends on, are
        kept unless -Force is used. For example, each Az rollup version pins exact versions of
        the Az.* modules, so those are kept while that Az version is installed. Prompts for
        confirmation by default.

    .PARAMETER Name
        One or more module names. Wildcards are supported. Defaults to all modules.

    .PARAMETER Keep
        How many of the newest versions to keep. Defaults to 1.

    .PARAMETER Scope
        Only remove versions installed in these scopes. All scopes are still counted when
        working out which versions are newest.

    .PARAMETER Force
        Remove versions even if they are loaded in the current session, or other installed
        modules depend on them.

    .PARAMETER PassThru
        Output an object for each version that was removed.

    .EXAMPLE
        Uninstall-OldModuleVersion -WhatIf

        Previews which old versions would be removed.

    .EXAMPLE
        Uninstall-OldModuleVersion Pester -Keep 2 -Confirm:$false

        Keeps the two newest versions of Pester and removes the rest, without prompting.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('ModuleManager.InstalledVersion')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called by Remove-MMInstallation, using the $PSCmdlet this cmdlet passes to it.')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [SupportsWildcards()]
        [string[]]$Name = '*',

        [ValidateRange(1, 1000)]
        [int]$Keep = 1,

        [ValidateSet('CurrentUser', 'AllUsers', 'Other')]
        [string[]]$Scope,

        [switch]$Force,

        [switch]$PassThru
    )

    begin { $names = [System.Collections.Generic.List[string]]::new() }
    process { foreach ($n in $Name) { $names.Add($n) } }
    end {
        if ($names.Count -eq 0) { $names.Add('*') }
        $all = @(Get-MMInstalledVersion -IncludeSystem)
        $modules = @(Group-MMInstallation -Installation @($all | Where-Object { Test-MMNameMatch $_.Name $names }))

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
            $removed = Remove-MMInstallation -Installation $i -Cmdlet $PSCmdlet -Force:$Force
            if ($removed -and $PassThru) { $i }
        }
    }
}
