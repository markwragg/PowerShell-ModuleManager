function Start-MMTuiElevatedAction {
    <#
    .SYNOPSIS
        Starts a terminal UI action as administrator, in an elevated PowerShell process (see Invoke-MMTuiAction).

    .DESCRIPTION
        Windows can't elevate a running process, so the action runs in a new, hidden PowerShell
        process of this edition started with Start-Process -Verb RunAs, which shows the Windows
        administrator prompt (UAC). The UI session stays as it is.

        The request (the action, its data and options, this session's loaded modules and
        PSModulePath) is written to a new folder in the temp folder. The elevated process runs the
        action there (Invoke-MMElevatedAction) and writes its output and progress back in batches.
        An elevated process's output can't be redirected to an unelevated one, and Windows doesn't
        let an unelevated process connect to an elevated one's PowerShell pipe.

        The waiting is done by a relay action in a background runspace here (Wait-MMElevatedAction),
        started with Start-MMTuiLocalAction, so the relayed lines and progress reach the output
        pane, and stopping works, exactly as for any other action. Sets PowerShell, Output and
        Handle on $Task.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Starts an action the user already confirmed.')]
    param([hashtable]$Task, [scriptblock]$Action, [object]$Data, [hashtable]$Options)

    $module = $ExecutionContext.SessionState.Module
    $modulePath = Join-Path $module.ModuleBase "$($module.Name).psd1"
    if (-not (Test-Path -LiteralPath $modulePath)) { $modulePath = $module.Path }

    $directory = Join-Path ([IO.Path]::GetTempPath()) "ModuleManager-$([guid]::NewGuid().ToString('N'))"
    $null = New-Item -ItemType Directory -Path $directory -Force

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $request = @{
        ModulePath   = $modulePath
        Action       = $Action.ToString()
        Data         = $Data
        Options      = $Options
        Loaded       = @(foreach ($m in (Get-MMLoadedModule)) {
                [pscustomobject]@{ Name = $m.Name; Version = $m.Version; ModuleBase = $m.ModuleBase; PrivateData = $m.PrivateData }
            })
        Gallery      = $script:MMGalleryCache.Clone()
        PSModulePath = $env:PSModulePath
        UserSid      = $identity.User.Value
        UserName     = $identity.Name
    }
    Export-Clixml -InputObject $request -LiteralPath (Join-Path $directory 'request.xml') -Depth 6

    $exe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $command = (
        "`$ProgressPreference = 'SilentlyContinue'",
        "`$d ='$($directory -replace "'", "''")'",
        "`$r = Import-Clixml -LiteralPath (Join-Path `$d 'request.xml')",
        "`$m = Import-Module -Name `$r.ModulePath -Force -PassThru -ErrorAction Stop",
        "& `$m { param(`$Directory) Invoke-MMElevatedAction -Directory `$Directory } `$d") -join '; '
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

    $relay = @{
        Directory    = $directory
        FilePath     = Join-Path $PSHOME $exe
        ArgumentList = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded"
    }
    Start-MMTuiLocalAction -Task $Task -Data $relay -Options $Options -Action {
        param($Data)
        Wait-MMElevatedAction -Directory $Data.Directory -FilePath $Data.FilePath -ArgumentList $Data.ArgumentList
    }
}
