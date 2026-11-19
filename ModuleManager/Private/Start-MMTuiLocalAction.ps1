function Start-MMTuiLocalAction {
    <#
    .SYNOPSIS
        Starts a terminal UI action in a background runspace on this computer (see Invoke-MMTuiAction).

    .DESCRIPTION
        The runspace imports a fresh copy of this module and runs the action there, with no host:
        Write-Host goes to the information stream, and progress to Streams.Progress, instead of
        drawing over the UI. Sets PowerShell, Output and Handle on $Task.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Starts an action the user already confirmed.')]
    param([hashtable]$Task, [scriptblock]$Action, [object]$Data, [hashtable]$Options)

    $module = $ExecutionContext.SessionState.Module
    $modulePath = Join-Path $module.ModuleBase "$($module.Name).psd1"
    if (-not (Test-Path -LiteralPath $modulePath)) { $modulePath = $module.Path }

    # The background runspace can't see this session's modules, so pass what's loaded here.
    $loaded = @(foreach ($m in (Get-Module -All)) {
            [pscustomobject]@{ Name = $m.Name; Version = $m.Version; ModuleBase = $m.ModuleBase; PrivateData = $m.PrivateData }
        })

    $iss = [initialsessionstate]::CreateDefault2()
    if (Test-MMIsWindows) {
        try { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch { Write-Debug $_ }
    }
    # Some PowerShell 7 versions add the default module folders to PSModulePath when a runspace
    # opens. The variable is shared by the whole process, so put back the path this session uses,
    # both here and in the runspace before it does anything.
    $modulePathVariable = $env:PSModulePath
    $runspace = [runspacefactory]::CreateRunspace($iss)
    $runspace.Open()
    $env:PSModulePath = $modulePathVariable
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddScript({
            param($ModulePath, $ActionText, $Data, $Options, $Loaded, $Gallery, $PSModulePathValue)
            $env:PSModulePath = $PSModulePathValue
            $module = Import-Module -Name $ModulePath -Force -PassThru -ErrorAction Stop
            & $module {
                param($Loaded, $Gallery)
                $script:MMLoadedModule = $Loaded
                foreach ($k in $Gallery.Keys) { $script:MMGalleryCache[$k] = $Gallery[$k] }
            } $Loaded $Gallery
            & $module ([scriptblock]::Create($ActionText)) $Data $Options *>&1
        }.ToString()).
        AddArgument($modulePath).AddArgument($Action.ToString()).AddArgument($Data).AddArgument($Options).
        AddArgument($loaded).AddArgument($script:MMGalleryCache.Clone()).AddArgument($modulePathVariable)

    $output = [System.Management.Automation.PSDataCollection[psobject]]::new()
    $Task.PowerShell = $ps
    $Task.Output = $output
    $Task.Handle = $ps.BeginInvoke([System.Management.Automation.PSDataCollection[psobject]]$null, $output)
}
