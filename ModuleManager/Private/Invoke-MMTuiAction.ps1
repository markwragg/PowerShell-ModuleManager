function Invoke-MMTuiAction {
    <#
    .SYNOPSIS
        Starts a terminal UI operation in the background, with its output in the output pane.

    .DESCRIPTION
        Starts an action in a background runspace and opens the output pane at the bottom of the
        screen, so the UI stays up (and usable) while it runs. Receive-MMTuiTask collects its
        output and progress, and when it finishes calls $OnComplete with ($State, $Data) and
        rescans.

        $Action is called as ($Data, $Options) in a fresh copy of this module, so it can use the
        module's private functions. It's passed as text, so it must not rely on variables from
        where it was written. Nothing can answer a prompt there (a prompt fails with an error), so
        actions pass -Confirm:$false, and updates ask about untrusted repositories beforehand.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI; the action itself was confirmed by the user.')]
    param([hashtable]$State, [string]$Title, [scriptblock]$Action, [object]$Data, [scriptblock]$OnComplete)

    if (Test-MMTuiBusy $State) { return }

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
    # No host: Write-Host goes to the information stream, and progress to Streams.Progress,
    # instead of drawing over the UI.
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
        AddArgument($modulePath).AddArgument($Action.ToString()).AddArgument($Data).AddArgument($State.Options).
        AddArgument($loaded).AddArgument($script:MMGalleryCache.Clone()).AddArgument($modulePathVariable)

    $output = [System.Management.Automation.PSDataCollection[psobject]]::new()
    $State.Log.Clear()
    $State.Log.Add(@{ Text = "$Title"; Style = 'Cyan' })
    $State.Task = @{
        Title      = $Title
        PowerShell = $ps
        Output     = $output
        Handle     = $ps.BeginInvoke([System.Management.Automation.PSDataCollection[psobject]]$null, $output)
        Data       = $Data
        OnComplete = $OnComplete
        Started    = [datetime]::UtcNow
        Errors     = 0
    }
    $State.Progress = $null
    $State.LogOpen = $true
    $State.LogScroll = 0
    Set-MMTuiMessage $State "$Title..." 'Cyan'
}
