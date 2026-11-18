function Uninstall-ManagedModule {
    <#
    .SYNOPSIS
        Uninstalls modules, or specific versions of modules.

    .DESCRIPTION
        Removes installed module versions from disk, whether they were installed by
        PowerShellGet, PSResourceGet or copied in by hand.

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

    .PARAMETER Name
        The module name(s) to uninstall. Wildcards are supported. All versions are removed
        unless -Version is given.

    .PARAMETER Version
        Only remove these versions (for example '1.2.0' or '2.0.0-beta1'). Wildcards are supported.

    .PARAMETER Scope
        Only remove versions installed in these scopes.

    .PARAMETER ModuleBase
        The folder of a specific installed version. Bound automatically when you pipe output
        from Get-ModuleLocation or Get-ModuleInventory -AllVersions.

    .PARAMETER Force
        Remove modules even if they are loaded, or required by other installed modules.

    .EXAMPLE
        Uninstall-ManagedModule OldModule

        Removes every installed version of OldModule.

    .EXAMPLE
        Uninstall-ManagedModule Pester -Version 4.*

        Removes only the Pester 4.x versions, keeping any others.

    .EXAMPLE
        Get-ModuleLocation Az.* -Scope AllUsers | Uninstall-ManagedModule -WhatIf

        Shows which all-users Az module versions would be removed, without removing anything.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ByModuleBase')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called by Remove-MMInstallation, using the $PSCmdlet this cmdlet passes to it.')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName, ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ByName')]
        [SupportsWildcards()]
        [string[]]$Version,

        [Parameter(ParameterSetName = 'ByName')]
        [ValidateSet('CurrentUser', 'AllUsers', 'Other')]
        [string[]]$Scope,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'ByModuleBase')]
        [string[]]$ModuleBase,

        [switch]$Force
    )

    begin {
        $all = @(Get-MMInstalledVersion -IncludeSystem)
        $targets = [System.Collections.Generic.List[object]]::new()
        $seen = @{}
    }
    process {
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
            $null = Remove-MMInstallation -Installation $t -Cmdlet $PSCmdlet -Force:$Force
        }
    }
}
