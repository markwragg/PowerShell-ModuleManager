function Start-MMRemoteCommand {
    <#
    .SYNOPSIS
        Starts a script block in ModuleManager's scope on the remote computer, without waiting for it.

    .DESCRIPTION
        Returns @{ PowerShell; Handle; Output }: read Output as it arrives, and progress from
        PowerShell.Streams.Progress. With -Merge, every stream (errors, warnings, verbose,
        Write-Host) comes back in Output, in order. The remote runspace runs one command at a
        time, so callers wait for one to finish before starting another.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Starts a command the caller has already confirmed; changes no state itself.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Runs on the remote computer, where each command is a separate pipeline: the module loaded by Initialize-MMRemote is kept in a global variable for the commands that follow.')]
    param(
        [Parameter(Mandatory)][hashtable]$Remote,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [switch]$Merge
    )
    $ps = [powershell]::Create()
    $ps.Runspace = $Remote.Runspace
    [void]$ps.AddScript({
            param($Text, $Arguments, $Merge)
            if ($Merge) { & $global:MMRemoteModule ([scriptblock]::Create($Text)) @Arguments *>&1 }
            else { & $global:MMRemoteModule ([scriptblock]::Create($Text)) @Arguments }
        }.ToString()).AddArgument($ScriptBlock.ToString()).AddArgument($ArgumentList).AddArgument([bool]$Merge)
    $output = [System.Management.Automation.PSDataCollection[psobject]]::new()
    @{
        PowerShell = $ps
        Output     = $output
        Handle     = $ps.BeginInvoke([System.Management.Automation.PSDataCollection[psobject]]$null, $output)
    }
}
