function Initialize-MMRemote {
    <#
    .SYNOPSIS
        Loads ModuleManager into a remote runspace, ready for Invoke-MMRemote and Start-MMRemoteCommand.

    .DESCRIPTION
        The module is sent as source code and loaded as a dynamic module, so it doesn't need to be
        installed on the remote computer, and the version matches the one running locally.

        Returns the remote target the terminal UI works with: @{ Runspace; Name }.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Runs on the remote computer, where each command is a separate pipeline: the module loaded by Initialize-MMRemote is kept in a global variable for the commands that follow.')]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.Runspace]$Runspace,
        [Parameter(Mandatory)][string]$Name
    )
    try {
        if ($Runspace.RunspaceStateInfo.State -ne 'Opened') { $Runspace.Open() }
        $ps = [powershell]::Create()
        $ps.Runspace = $Runspace
        [void]$ps.AddScript({
                param($Source)
                $global:MMRemoteModule = New-Module -Name ModuleManager -ScriptBlock ([scriptblock]::Create($Source))
                # Without a console, progress is only sent back if asked for.
                $global:ProgressPreference = 'Continue'
            }.ToString()).AddArgument((Get-MMModuleSource))
        try { $null = $ps.Invoke() }
        finally { $ps.Dispose() }
    }
    catch {
        $Runspace.Dispose()
        $e = $_.Exception
        while ($e.InnerException -and $e -is [System.Management.Automation.MethodInvocationException]) { $e = $e.InnerException }
        throw "Could not start ModuleManager on $Name`: $($e.Message)"
    }
    @{ Runspace = $Runspace; Name = $Name }
}
