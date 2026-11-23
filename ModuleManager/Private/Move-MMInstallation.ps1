function Move-MMInstallation {
    <#
    .SYNOPSIS
        Moves one installed module version folder to another module folder, after safety checks.

    .DESCRIPTION
        Moves a single installed module version to the same place under another PSModulePath
        entry (for example from the CurrentUser module folder to the AllUsers one).
        ShouldProcess is evaluated against the calling public cmdlet so -WhatIf/-Confirm work.

        The source folder is first renamed to a staging name beside it, which fails cleanly if
        anything in it is in use. It's then copied (so it takes the destination's permissions,
        which a rename wouldn't), the install record's location is updated, and the staging folder
        is removed. If the copy fails, the source is put back as it was.

        Returns the new module folder, or $null if the version wasn't moved.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Confirmation is delegated: the calling cmdlet''s $PSCmdlet is passed in and its ShouldProcess is used.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Confirmation is delegated: the calling cmdlet''s $PSCmdlet is passed in and its ShouldProcess is used.')]
    param(
        [Parameter(Mandatory)][object]$Installation,
        [Parameter(Mandatory)][object]$DestinationRoot,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Cmdlet,
        [switch]$Force
    )

    $i = $Installation
    $label = "$($i.Name) $($i.Version)"
    $toScope = $DestinationRoot.Scope

    $fail = {
        param([Exception]$Exception, [string]$Id, [string]$Category)
        $Cmdlet.WriteError([System.Management.Automation.ErrorRecord]::new($Exception, "ModuleManager.$Id", $Category, $i))
    }

    if ($i.Scope -eq 'System') {
        & $fail ([InvalidOperationException]::new("$label ships with PowerShell or Windows ($($i.ModuleBase)) and cannot be moved.")) 'SystemModule' 'PermissionDenied'
        return
    }
    if ($i.Scope -eq $toScope) {
        Write-Verbose "$label is already installed for $toScope ($($i.ModuleBase))."
        return
    }
    if (($i.Scope -eq 'AllUsers' -or $toScope -eq 'AllUsers') -and -not $script:MMTuiWhatIf -and -not (Test-MMIsAdmin)) {
        & $fail ([UnauthorizedAccessException]::new("Moving $label $(if ($i.Scope -eq 'AllUsers') { 'from' } else { 'to' }) the all users module folder needs an elevated session. Run PowerShell as administrator.")) 'RequiresElevation' 'PermissionDenied'
        return
    }
    if ($i.IsLoaded -and -not $Force) {
        & $fail ([InvalidOperationException]::new("$label is loaded in the current session. Run 'Remove-Module $($i.Name)' first, or use -Force.")) 'ModuleInUse' 'ResourceBusy'
        return
    }

    # The same layout under the new root: <root>\<Name>\<Version>, or <root>\<Name>.
    $relative = $i.ModuleBase.Substring($i.ModuleRoot.Length).TrimStart('\', '/')
    $destination = Join-Path $DestinationRoot.Path $relative
    if ([IO.Directory]::Exists($destination)) {
        & $fail ([System.IO.IOException]::new("$label is already installed for $toScope ($destination). Uninstall one of the copies instead.")) 'AlreadyInstalled' 'ResourceExists'
        return
    }

    if (-not (Test-MMShouldProcess $Cmdlet "$label ($($i.ModuleBase))" "Move module version to $toScope ($destination)")) { return }

    if ($i.IsLoaded) {
        $key = Get-MMPathKey $i.ModuleBase
        Get-Module -Name $i.Name -All | Where-Object { (Get-MMPathKey $_.ModuleBase) -eq $key } |
            Remove-Module -Force -ErrorAction SilentlyContinue
    }

    $source = $i.ModuleBase
    $staging = "$source.mmmove-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    try { Rename-MMFolder -Path $source -Destination $staging }
    catch {
        & $fail ([System.IO.IOException]::new("Failed to move $label from $source (is it in use?): $($_.Exception.Message)", $_.Exception)) 'MoveFailed' 'WriteError'
        return
    }

    $parent = Split-Path -Path $destination -Parent
    $newParent = -not [IO.Directory]::Exists($parent)
    try {
        if ($newParent) { $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop }
        Copy-Item -LiteralPath $staging -Destination $destination -Recurse -Force -ErrorAction Stop
    }
    catch {
        $reason = $_.Exception.Message
        if ([IO.Directory]::Exists($destination)) { Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue }
        if ($newParent -and [IO.Directory]::Exists($parent)) { Remove-Item -LiteralPath $parent -Recurse -Force -ErrorAction SilentlyContinue }
        try { Rename-MMFolder -Path $staging -Destination $source }
        catch { $reason += " The module is still in $staging; rename it back to $source." }
        & $fail ([System.IO.IOException]::new("Failed to copy $label to $destination`: $reason")) 'MoveFailed' 'WriteError'
        return
    }

    Update-MMInstallLocation -ModuleBase $destination -OldModuleBase $source -OldRoot $i.ModuleRoot -NewRoot $DestinationRoot.Path

    try { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction Stop }
    catch { Write-Warning "Moved $label to $destination, but could not remove the old copy at $staging`: $($_.Exception.Message)" }

    # Tidy up the old parent <Name> folder if this was the last version in it.
    $oldParent = Split-Path -Path $source -Parent
    if ((Get-MMPathKey $oldParent) -ne (Get-MMPathKey $i.ModuleRoot) -and [IO.Directory]::Exists($oldParent)) {
        $isEmpty = -not [IO.Directory]::EnumerateFileSystemEntries($oldParent).GetEnumerator().MoveNext()
        if ($isEmpty) { Remove-Item -LiteralPath $oldParent -Force -ErrorAction SilentlyContinue }
    }

    Write-Verbose "Moved $label from $source to $destination"
    $destination
}
