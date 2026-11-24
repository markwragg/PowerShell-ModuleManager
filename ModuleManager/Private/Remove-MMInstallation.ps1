function Remove-MMInstallation {
    <#
    .SYNOPSIS
        Removes one installed module version folder, after safety checks.

    .DESCRIPTION
        Removes a single installed module version folder after safety checks.
        ShouldProcess is evaluated against the calling public cmdlet so -WhatIf/-Confirm work.
        Returns $true if the version was removed.

        The version's size is measured first and shown in the confirmation prompt (and -WhatIf
        line), and added to the installation object as SizeMB. With -Tally, the number and total
        size of the versions removed (Removed, Bytes), or that -WhatIf says would be (WhatIf,
        WhatIfBytes), are added to that hashtable, so the caller can say how much space was freed.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Confirmation is delegated: the calling cmdlet''s $PSCmdlet is passed in and its ShouldProcess is used.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Confirmation is delegated: the calling cmdlet''s $PSCmdlet is passed in and its ShouldProcess is used.')]
    param(
        [Parameter(Mandatory)][object]$Installation,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Cmdlet,
        [switch]$Force,
        [hashtable]$Tally
    )

    $i = $Installation
    $label = "$($i.Name) $($i.Version)"

    if ($i.Scope -eq 'System') {
        $Cmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [InvalidOperationException]::new("$label ships with PowerShell or Windows ($($i.ModuleBase)) and cannot be uninstalled."),
                'ModuleManager.SystemModule', 'PermissionDenied', $i))
        return $false
    }
    if ($i.Scope -eq 'AllUsers' -and -not $script:MMTuiWhatIf -and -not (Test-MMIsAdmin)) {
        $Cmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [UnauthorizedAccessException]::new("$label is installed for all users ($($i.ModuleBase)). Run PowerShell as administrator to remove it."),
                'ModuleManager.RequiresElevation', 'PermissionDenied', $i))
        return $false
    }
    if ($i.IsLoaded -and -not $Force) {
        $Cmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [InvalidOperationException]::new("$label is loaded in the current session. Run 'Remove-Module $($i.Name)' first, or use -Force."),
                'ModuleManager.ModuleInUse', 'ResourceBusy', $i))
        return $false
    }

    $bytes = Get-MMFolderSize $i.ModuleBase
    $sizeText = ''
    if ($null -ne $bytes) {
        $sizeText = ", $(Format-MMSize $bytes)"
        $i | Add-Member -NotePropertyName SizeMB -NotePropertyValue ([Math]::Round($bytes / 1MB, 1)) -Force
    }
    else { $bytes = 0L }

    if (-not (Test-MMShouldProcess $Cmdlet "$label$sizeText ($($i.ModuleBase))" 'Uninstall module version')) {
        # $WhatIfPreference is the calling cmdlet's, as this runs in its scope.
        if ($Tally -and ($script:MMTuiWhatIf -or $WhatIfPreference)) {
            $Tally['WhatIf'] = [int]$Tally['WhatIf'] + 1
            $Tally['WhatIfBytes'] = [long]$Tally['WhatIfBytes'] + $bytes
        }
        return $false
    }

    if ($i.IsLoaded) {
        $key = Get-MMPathKey $i.ModuleBase
        Get-Module -Name $i.Name -All | Where-Object { (Get-MMPathKey $_.ModuleBase) -eq $key } |
            Remove-Module -Force -ErrorAction SilentlyContinue
    }

    try {
        Remove-Item -LiteralPath $i.ModuleBase -Recurse -Force -ErrorAction Stop
    }
    catch {
        $Cmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                [System.IO.IOException]::new("Failed to remove $label from $($i.ModuleBase): $($_.Exception.Message)", $_.Exception),
                'ModuleManager.RemoveFailed', 'WriteError', $i))
        return $false
    }

    # Tidy up the parent <Name> folder if this was the last version in it.
    $parent = Split-Path -Path $i.ModuleBase -Parent
    if ((Get-MMPathKey $parent) -ne (Get-MMPathKey $i.ModuleRoot) -and [IO.Directory]::Exists($parent)) {
        $isEmpty = -not [IO.Directory]::EnumerateFileSystemEntries($parent).GetEnumerator().MoveNext()
        if ($isEmpty) { Remove-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue }
    }

    if ($Tally) {
        $Tally['Removed'] = [int]$Tally['Removed'] + 1
        $Tally['Bytes'] = [long]$Tally['Bytes'] + $bytes
    }
    Write-Verbose "Removed $label$sizeText from $($i.ModuleBase)"
    $true
}
