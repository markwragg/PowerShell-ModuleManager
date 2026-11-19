function Connect-MMRemote {
    <#
    .SYNOPSIS
        Connects the terminal UI to a remote computer, by name or through an existing PSSession.

    .DESCRIPTION
        The terminal UI uses its own remote runspace, made from the connection details of the
        session: a PSSession sends its host messages (Write-Host, warnings, progress) to the console
        of the session that created it, which would draw over the UI. Its own runspace has no host,
        so all output comes back as data for the output pane. The PSSession passed in is left as it
        is; with -ComputerName, a PSSession is opened only to work out the connection details.
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName,
        [pscredential]$Credential,
        [string]$ConfigurationName,
        [System.Management.Automation.Runspaces.PSSession]$Session
    )
    $temporary = $null
    if ($ComputerName) {
        $params = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
        if ($Credential) { $params.Credential = $Credential }
        if ($ConfigurationName) { $params.ConfigurationName = $ConfigurationName }
        try { $temporary = New-PSSession @params }
        catch { throw "Could not connect to $ComputerName`: $($_.Exception.Message)" }
        $info = $temporary.Runspace.ConnectionInfo
        $name = $ComputerName
    }
    else {
        $info = $Session.Runspace.ConnectionInfo
        $name = $Session.ComputerName
    }
    try {
        $runspace = [runspacefactory]::CreateRunspace($info)
        $runspace.Open()
    }
    catch { throw "Could not connect to $name`: $($_.Exception.Message)" }
    finally { if ($temporary) { Remove-PSSession -Session $temporary } }
    $remote = Initialize-MMRemote -Runspace $runspace -Name $name
    $remote.ConnectionInfo = $info   # to reconnect with (see Repair-MMRemote)
    $remote
}
