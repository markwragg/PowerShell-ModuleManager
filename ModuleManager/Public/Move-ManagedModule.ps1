function Move-ManagedModule {
    <#
    .SYNOPSIS
        Moves modules, or specific versions of modules, between the CurrentUser and AllUsers scopes.

    .DESCRIPTION
        Moves installed module versions to the module folder of another scope. Each version
        keeps its folder layout, and the location in its install record (PSGetModuleInfo.xml) is
        updated, so PowerShellGet and PSResourceGet still recognise it.

        On Windows, a version stays with its edition's modules: one in a WindowsPowerShell\Modules
        folder moves to the other WindowsPowerShell\Modules folder (Documents or Program Files),
        and one in a PowerShell\Modules folder to the other PowerShell\Modules folder. This keeps
        it where the edition it was installed for looks. For example, from PowerShell 7, a module
        in Program Files\WindowsPowerShell\Modules (which both editions use) moved to CurrentUser
        goes to Documents\WindowsPowerShell\Modules. PowerShell 7 doesn't look there by default
        (only when it's started from Windows PowerShell), so a warning says when the session
        can't see where a version went. Other versions move to the first PSModulePath entry for
        the scope.

        Each version is copied, so it takes the permissions of the destination folder, and the
        original is removed only once the copy is complete. If the copy fails, the original is
        left as it was.

        Safety checks:
          - Modules that ship with PowerShell or Windows are never moved.
          - Versions already installed for the destination scope are skipped.
          - Versions that already exist at the destination are not overwritten.
          - Loaded modules are skipped unless -Force is used, which unloads them first.
          - Moving to or from AllUsers requires an elevated session.
          - Moving to CurrentUser a version that a module installed for all users depends on
            warns that other users will no longer have it.

    .PARAMETER Name
        The module name(s) to move. Wildcards are supported. All versions are moved unless
        -Version is given.

    .PARAMETER Version
        Only move these versions (for example '1.2.0' or '2.0.0-beta1'). Wildcards are supported.

    .PARAMETER Scope
        Only move versions installed in these scopes.

    .PARAMETER ModuleBase
        The folder of a specific installed version. Bound automatically when you pipe output
        from Get-ManagedModuleLocation or Get-ManagedModule -AllVersions.

    .PARAMETER Destination
        The scope to move to: CurrentUser or AllUsers.

    .PARAMETER Force
        Move modules even if they are loaded, unloading them from the session first.

    .PARAMETER PassThru
        Output the moved versions, at their new locations.

    .EXAMPLE
        Move-ManagedModule Pester -Destination AllUsers

        Moves every version of Pester installed for the current user to the all users module folder.

    .EXAMPLE
        Get-ManagedModuleLocation -Scope AllUsers | Move-ManagedModule -Destination CurrentUser -WhatIf

        Shows which all-users module versions would be moved to the current user's module folder,
        without moving anything.

    .EXAMPLE
        Move-ManagedModule Az.* -Version 14.* -Destination AllUsers -PassThru

        Moves the Az 14.x versions to the all users module folder and lists where they are now.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByModuleBase')]
    [OutputType('ModuleManager.InstalledVersion')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is called by Move-MMInstallation, using the $PSCmdlet this cmdlet passes to it.')]
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

        [Parameter(Mandatory)]
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Destination,

        [switch]$Force,

        [switch]$PassThru
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

        # Other users can't see the current user's modules, so a version moved there is lost to any
        # module installed for all users that needs it.
        if ($Destination -eq 'CurrentUser') {
            $leaving = @($targets | Where-Object Scope -NE 'CurrentUser')
            $shared = @($all | Where-Object Scope -NE 'CurrentUser')
            foreach ($k in (Get-MMRequiredInstallation -Removing $leaving -AllInstallation $shared)) {
                $i = $k.Installation
                Write-Warning "$($i.Name) $($i.Version) is required by: $(Format-MMRequiredBy $k.RequiredBy). Other users won't have it once it's moved to CurrentUser."
            }
        }

        $moved = [System.Collections.Generic.List[string]]::new()
        $offPath = [ordered]@{}
        foreach ($t in $targets) {
            $root = Get-MMDestinationRoot -Installation $t -Scope $Destination
            if (-not $root) {
                Write-Error -Message "There is no $Destination module folder in PSModulePath to move $($t.Name) $($t.Version) to." `
                    -Category ObjectNotFound -TargetObject $t -ErrorId 'ModuleManager.NoDestination'
                continue
            }
            $new = Move-MMInstallation -Installation $t -DestinationRoot $root -Cmdlet $PSCmdlet -Force:$Force
            if (-not $new) { continue }
            $moved.Add((Get-MMPathKey $new))
            if (-not $root.OnPath) {
                if (-not $offPath.Contains($root.Path)) { $offPath[$root.Path] = [System.Collections.Generic.List[string]]::new() }
                $offPath[$root.Path].Add("$($t.Name) $($t.Version)")
            }
        }

        # Kept with its edition's modules (see Get-MMDestinationRoot), in a folder this session doesn't look in.
        foreach ($path in $offPath.Keys) {
            $edition = if ($path -match '[\\/]WindowsPowerShell[\\/]Modules$') { 'Windows PowerShell' } else { 'PowerShell 7' }
            Write-Warning "Moved $($offPath[$path] -join ', ') to $path, with the other $edition modules. $edition finds modules there, but this session doesn't: it isn't in PSModulePath."
        }

        if ($PassThru -and $moved.Count) {
            $names = @($targets | ForEach-Object { $_.Name } | Select-Object -Unique)
            Get-MMInstalledVersion -Name $names -IncludeSystem | Where-Object { $moved -contains (Get-MMPathKey $_.ModuleBase) }
        }
    }
}
