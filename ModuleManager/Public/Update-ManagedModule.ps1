function Update-ManagedModule {
    <#
    .SYNOPSIS
        Installs the latest version of one or more modules.

    .DESCRIPTION
        Checks each module against its repository (using cached results from
        Get-ModuleUpdate where available) and installs the newest version alongside
        the existing ones. Modules that are already up to date are skipped.

        By default the new version is installed into the same scope as the newest
        version you already have. Installing for AllUsers requires an elevated session.

        Uses Microsoft.PowerShell.PSResourceGet when available, otherwise PowerShellGet.

        Dependencies:
          - The package manager installs any dependencies the new version needs.
          - When several modules are updated together, modules are updated after the modules
            they depend on (for example Az.Accounts, then the Az.* modules, then Az).
          - A module that an earlier update in the same run already installed as a dependency
            is skipped. -Verbose and -PassThru show which module each one came with.
          - If a module loaded in this session is older than a new version needs (for example
            Az.Accounts), you're warned before anything is installed, because the new version
            can't be used until you start a new session.
          - -RemoveOldVersions runs once at the end, for every module that was updated
            (including dependencies), and keeps any old version another installed module still
            depends on.

    .PARAMETER Name
        One or more module names. Wildcards are supported. Accepts pipeline input from
        Get-ModuleInventory and Get-ModuleUpdate.

    .PARAMETER Scope
        Install the new version into this scope instead of the existing one.

    .PARAMETER Repository
        Install from this repository instead of the one the module came from.

    .PARAMETER IncludePrerelease
        Allow updating to a prerelease version.

    .PARAMETER RemoveOldVersions
        After updating, uninstall the older versions of the updated modules (and of any
        dependencies installed with them), except versions other installed modules depend on.

    .PARAMETER TrustRepository
        Don't prompt when installing from an untrusted repository.

    .PARAMETER PassThru
        Output the inventory entry of each updated module. Modules installed as a dependency of
        another update have an UpdatedAsDependencyOf property naming that module.

    .EXAMPLE
        Update-ManagedModule Pester

        Installs the latest version of Pester alongside the existing versions, in the same scope.

    .EXAMPLE
        Get-ModuleUpdate -Outdated | Update-ManagedModule -RemoveOldVersions

        Updates every module that has a newer version available, then removes the old versions.

    .EXAMPLE
        Update-ManagedModule * -WhatIf

        Shows what would be updated without installing anything.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('ModuleManager.ModuleInfo')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [SupportsWildcards()]
        [string[]]$Name,

        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope,

        [string]$Repository,

        [switch]$IncludePrerelease,

        [switch]$RemoveOldVersions,

        [switch]$TrustRepository,

        [switch]$PassThru
    )

    begin { $names = [System.Collections.Generic.List[string]]::new() }
    process { foreach ($n in $Name) { $names.Add($n) } }
    end {
        $updates = @(Get-ModuleUpdate -Name $names -Repository $Repository -IncludePrerelease:$IncludePrerelease)
        $pending = [System.Collections.Generic.List[object]]::new()
        foreach ($u in $updates) {
            switch ($u.Status) {
                'UpdateAvailable' { $pending.Add($u) }
                'NotInRepository' { Write-Verbose "$($u.Name) was not found in $($u.Repository); skipping." }
                'Unlisted' { Write-Verbose "$($u.Name) has been unlisted from $($u.Repository); skipping." }
                'Error' { Write-Warning "Could not check $($u.Name) in $($u.Repository): $($u.Error)" }
                default { Write-Verbose "$($u.Name) $($u.InstalledVersion) is $($u.Status); skipping." }
            }
        }
        if (-not $pending.Count) { return }

        # Dependencies first (e.g. Az.Accounts, then Az.*, then Az), so each install finds what it
        # needs already in place, and a dependency's own update is never undone by a later one.
        $pending = @(Get-MMUpdateOrder -Update $pending.ToArray())

        foreach ($c in (Get-MMLoadedDependencyConflict -Update $pending)) {
            Write-Warning ("$($c.Name) $($c.LoadedVersion) is loaded in this session, but $(Format-MMRequiredBy $c.RequiredBy.ToArray()). " +
                "The updates will install, but start a new session to use them.")
        }

        # Name -> what was installed and, for modules pulled in by another module's install, which one.
        $updated = [ordered]@{}
        $activity = 'Updating modules'
        $total = $pending.Count
        $done = 0
        $versions = $null

        try {
            foreach ($u in $pending) {
                $latest = $u.LatestVersion

                # An earlier install in this run may already have installed this as a dependency.
                if ($updated.Count) {
                    $bound = ConvertTo-MMVersionBound $latest
                    $now = @(Get-MMSortedInstallation @(Get-MMInstalledVersion -Name $u.Name))
                    if ($now.Count -and (Compare-MMVersion $now[0].ModuleVersion $now[0].Prerelease $bound.Version $bound.Prerelease) -ge 0) {
                        $by = 'an earlier update'
                        if ($updated.Contains($u.Name) -and $updated[$u.Name].DependencyOf) { $by = $updated[$u.Name].DependencyOf }
                        Write-Verbose "$($u.Name) $($now[0].Version) was already installed as a dependency of $by; skipping."
                        if (-not $updated.Contains($u.Name)) {
                            $updated[$u.Name] = [pscustomobject]@{ Name = $u.Name; Version = $now[0].Version; DependencyOf = $by }
                        }
                        $done++
                        continue
                    }
                }

                $targetScope = $Scope
                if (-not $targetScope) {
                    $newest = $u.Installations[0].Scope
                    if ($newest -in 'CurrentUser', 'AllUsers') { $targetScope = $newest } else { $targetScope = 'CurrentUser' }
                }
                if ($targetScope -eq 'AllUsers' -and -not (Test-MMIsAdmin)) {
                    Write-Error -Message "Updating $($u.Name) for all users requires an elevated session. Run as administrator or use -Scope CurrentUser." `
                        -Category PermissionDenied -TargetObject $u.Name -ErrorId 'ModuleManager.RequiresElevation'
                    continue
                }

                $isPre = $latest -match '-'
                $target = "$($u.Name) $($u.InstalledVersion) -> $latest ($targetScope, from $($u.Repository))"
                if (-not $PSCmdlet.ShouldProcess($target, 'Update module')) { continue }

                $percent = [int](100 * $done / [Math]::Max($total, 1))
                Write-Progress -Activity $activity -Status "$($done + 1) of $total`: $($u.Name) $($u.InstalledVersion) -> $latest" `
                    -PercentComplete $percent
                $done++

                if ($null -eq $versions) { $versions = Get-MMNewestVersionMap }
                try {
                    Invoke-MMInstall -Name $u.Name -Version $latest -Prerelease $isPre -Repository $u.Repository `
                        -Scope $targetScope -TrustRepository:$TrustRepository
                }
                catch {
                    Write-Error -Message "Failed to update $($u.Name): $($_.Exception.Message)" -Category InvalidResult `
                        -TargetObject $u.Name -ErrorId 'ModuleManager.UpdateFailed'
                    $versions = Get-MMNewestVersionMap
                    continue
                }
                $updated[$u.Name] = [pscustomobject]@{ Name = $u.Name; Version = $latest; DependencyOf = $null }
                Write-Verbose "Updated $target"

                # Anything else whose newest version changed was installed as a dependency of this module.
                $after = Get-MMNewestVersionMap
                foreach ($key in $after.Keys) {
                    $new = $after[$key]
                    if ($key -eq $u.Name.ToLowerInvariant() -or $updated.Contains($new.Name)) { continue }
                    if ($versions.ContainsKey($key) -and $versions[$key].Version -ge $new.Version) { continue }
                    $updated[$new.Name] = [pscustomobject]@{ Name = $new.Name; Version = [string]$new.Version; DependencyOf = $u.Name }
                    Write-Verbose "Installed $($new.Name) $($new.Version) as a dependency of $($u.Name)."
                }
                $versions = $after

                if ($u.IsLoaded) {
                    Write-Warning "$($u.Name) is loaded in this session. Start a new session (or Remove-Module and Import-Module) to use $latest."
                }
            }

            # Removing old versions once at the end, for everything updated, lets old versions that
            # depend on each other (an old Az rollup and the Az.* versions it pins) go together.
            if ($RemoveOldVersions -and $updated.Count) {
                Write-Progress -Activity $activity -Status 'Removing old versions' -PercentComplete 100
                Uninstall-OldModuleVersion -Name @($updated.Keys) -Keep 1 -Confirm:$false -WhatIf:$false
            }
        }
        finally { Write-Progress -Activity $activity -Completed }

        if ($PassThru -and $updated.Count) {
            foreach ($m in (Get-ModuleInventory -Name @($updated.Keys))) {
                $m | Add-Member -NotePropertyName UpdatedAsDependencyOf -NotePropertyValue $updated[$m.Name].DependencyOf -Force -PassThru
            }
        }
    }
}
