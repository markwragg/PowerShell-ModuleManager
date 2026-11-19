function Invoke-MMRemote {
    <#
    .SYNOPSIS
        Runs a script block in ModuleManager's scope on the remote computer and returns its output.

    .DESCRIPTION
        The script block can use the module's private functions. Its output is serialized on the
        remote side to a depth that keeps nested data intact (remoting's default would flatten
        an installation's dependencies to text), and deserialized here.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Runs on the remote computer, where each command is a separate pipeline: the module loaded by Initialize-MMRemote is kept in a global variable for the commands that follow.')]
    param(
        [Parameter(Mandatory)][hashtable]$Remote,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @()
    )
    $ps = [powershell]::Create()
    $ps.Runspace = $Remote.Runspace
    [void]$ps.AddScript({
            param($Text, $Arguments)
            $result = @(& $global:MMRemoteModule ([scriptblock]::Create($Text)) @Arguments)
            [System.Management.Automation.PSSerializer]::Serialize($result, 10)
        }.ToString()).AddArgument($ScriptBlock.ToString()).AddArgument($ArgumentList)
    try { $output = $ps.Invoke() }
    catch {
        $e = $_.Exception
        while ($e.InnerException -and $e -is [System.Management.Automation.MethodInvocationException]) { $e = $e.InnerException }
        throw $e.Message
    }
    finally { $ps.Dispose() }
    foreach ($text in $output) {
        foreach ($item in [System.Management.Automation.PSSerializer]::Deserialize([string]$text)) { $item }
    }
}
