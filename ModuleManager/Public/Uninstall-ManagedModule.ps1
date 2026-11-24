function Uninstall-ManagedModule {
    <#
    .SYNOPSIS
        Uninstalls modules, specific versions of modules, or the old versions of modules.

    .DESCRIPTION
        Removes installed module versions from disk, whether they were installed by
        PowerShellGet, PSResourceGet or copied in by hand.

        With -OldVersions, removes all but the newest -Keep versions of each module instead.
        Updating a module installs the new version alongside the old one, so versions build up
        over time. Loaded versions, and old versions that another installed module depends on,
        are skipped with a warning (unless -Force is used) rather than as errors. For example,
        each Az rollup version pins exact versions of the Az.* modules, so those are kept while
        that Az version is installed.

        Safety checks:
          - Modules that ship with PowerShell or Windows are never removed.
          - Loaded modules are skipped unless -Force is used.
          - Removing a version that another installed module depends on is blocked unless
            -Force is used. Dependencies are read from the package manager's install record
            (PSGetModuleInfo.xml), or the manifest for modules copied in by hand, and are
            checked against the version range each module needs. For example, the Az rollup
            module pins exact versions of each Az.* module.
          - AllUsers installs require an elevated session.

        Prompts for confirmation for each version by default. Use -Confirm:$false to skip
        prompts, or -WhatIf to preview.

        Each version's size is shown in its confirmation prompt (and -WhatIf line). When it's done,
        it says how many versions it removed and how much disk space that freed, or with -WhatIf,
        how much it would free. This is an information message, so -InformationAction
        SilentlyContinue (or 6>$null) hides it without hiding warnings.

    .PARAMETER Name
        The module name(s) to uninstall. Wildcards are supported. All versions are removed
        unless -Version or -OldVersions is given. With -OldVersions it defaults to all modules,
        and accepts names from the pipeline.

    .PARAMETER Version
        Only remove these versions (for example '1.2.0' or '2.0.0-beta1'). Wildcards are supported.

    .PARAMETER OldVersions
        Remove the old versions of each module, keeping the newest (or the newest -Keep).

    .PARAMETER Keep
        With -OldVersions, how many of the newest versions to keep. Defaults to 1.

    .PARAMETER Scope
        Only remove versions installed in these scopes. With -OldVersions, all scopes are still
        counted when working out which versions are newest.

    .PARAMETER ModuleBase
        The folder of a specific installed version. Bound automatically when you pipe output
        from Get-ManagedModuleLocation or Get-ManagedModule -AllVersions.

    .PARAMETER Force
        Remove modules even if they are loaded, or required by other installed modules.

    .PARAMETER PassThru
        Output an object for each version that was removed, with its size in MB (SizeMB).

    .EXAMPLE
        Uninstall-ManagedModule OldModule

        Removes every installed version of OldModule.

    .EXAMPLE
        Uninstall-ManagedModule Pester -Version 4.*

        Removes only the Pester 4.x versions, keeping any others.

    .EXAMPLE
        Get-ManagedModuleLocation Az.* -Scope AllUsers | Uninstall-ManagedModule -WhatIf

        Shows which all-users Az module versions would be removed, without removing anything.

    .EXAMPLE
        Uninstall-ManagedModule -OldVersions -WhatIf

        Previews which old versions of every module would be removed.

    .EXAMPLE
        Uninstall-ManagedModule Pester -OldVersions -Keep 2 -Confirm:$false

        Keeps the two newest versions of Pester and removes the rest, without prompting.

    .EXAMPLE
        Uninstall-ManagedModule -OldVersions -Confirm:$false -PassThru | Measure-Object SizeMB -Sum

        Removes the old versions of every module, and totals the space freed from the versions output.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByModuleBase')]
    [OutputType('ModuleManager.InstalledVersion')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called by Remove-MMInstallation, using the $PSCmdlet this cmdlet passes to it.')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName, ParameterSetName = 'ByName')]
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'OldVersions')]
        [SupportsWildcards()]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string[]]$Version,

        [Parameter(Mandatory, ParameterSetName = 'OldVersions')]
        [switch]$OldVersions,

        [Parameter(ParameterSetName = 'OldVersions')]
        [ValidateRange(1, 1000)]
        [int]$Keep = 1,

        [Parameter(ParameterSetName = 'ByName')]
        [Parameter(ParameterSetName = 'OldVersions')]
        [ValidateSet('CurrentUser', 'AllUsers', 'Other')]
        [string[]]$Scope,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'ByModuleBase')]
        [string[]]$ModuleBase,

        [switch]$Force,

        [switch]$PassThru
    )

    begin {
        $names = [System.Collections.Generic.List[string]]::new()
        if (-not $OldVersions) { $all = @(Get-MMInstalledVersion -IncludeSystem) }
        $targets = [System.Collections.Generic.List[object]]::new()
        $seen = @{}
        $tally = @{ Removed = 0; Bytes = 0L; WhatIf = 0; WhatIfBytes = 0L }
    }
    process {
        # The old versions are worked out once every name is in.
        if ($OldVersions) { foreach ($n in $Name) { $names.Add($n) }; return }

        $matched = @()
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $matched = @($all | Where-Object {
                    (Test-MMNameMatch $_.Name $Name) -and
                    (-not $Version -or (Test-MMNameMatch $_.Version $Version)) -and
                    (-not $Scope -or $Scope -contains $_.Scope)
                })
            if (-not $matched) {
                Write-Error -Message "No installed module matches '$($Name -join ', ')'$(if ($Version) { " version '$($Version -join ', ')'" })." `
                    -Category ObjectNotFound -TargetObject $Name -ErrorId 'ModuleManager.NotFound'
            }
        }
        else {
            foreach ($path in $ModuleBase) {
                $key = Get-MMPathKey $path
                $hit = @($all | Where-Object { (Get-MMPathKey $_.ModuleBase) -eq $key })
                if (-not $hit) {
                    Write-Error -Message "No installed module version found at '$path'." -Category ObjectNotFound `
                        -TargetObject $path -ErrorId 'ModuleManager.NotFound'
                }
                $matched += $hit
            }
        }
        foreach ($m in $matched) {
            $key = Get-MMPathKey $m.ModuleBase
            if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $targets.Add($m) }
        }
    }
    end {
        if ($OldVersions) {
            if ($names.Count -eq 0) { $names.Add('*') }
            $removed = Remove-MMOldVersion -Name $names.ToArray() -Keep $Keep -Scope $Scope -Force:$Force -Tally $tally -Cmdlet $PSCmdlet
            if ($PassThru) { $removed }
            Write-MMRemovalSummary -Tally $tally -Cmdlet $PSCmdlet
            return
        }
        if (-not $targets.Count) { return }

        # Block removing versions that modules staying installed depend on (checked against the
        # version ranges they need, so removing an exact version that something pins is blocked too).
        $blocked = @{}
        if (-not $Force) {
            foreach ($k in (Get-MMRequiredInstallation -Removing $targets.ToArray() -AllInstallation $all)) {
                $i = $k.Installation
                $blocked[(Get-MMPathKey $i.ModuleBase)] = $true
                Write-Error -Message "Not removing $($i.Name) $($i.Version) because it is required by: $(Format-MMRequiredBy $k.RequiredBy). Use -Force to remove it anyway." `
                    -Category ResourceBusy -TargetObject $i -ErrorId 'ModuleManager.HasDependents'
            }
        }

        foreach ($t in $targets) {
            if ($blocked.ContainsKey((Get-MMPathKey $t.ModuleBase))) { continue }
            if ((Remove-MMInstallation -Installation $t -Cmdlet $PSCmdlet -Force:$Force -Tally $tally) -and $PassThru) { $t }
        }
        Write-MMRemovalSummary -Tally $tally -Cmdlet $PSCmdlet
    }
}
