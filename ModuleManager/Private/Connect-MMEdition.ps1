function Connect-MMEdition {
    <#
    .SYNOPSIS
        Connects the terminal UI to the other PowerShell edition on this computer (Windows PowerShell
        5.1 or PowerShell 7), so its modules can be managed from here.

    .DESCRIPTION
        The editions install modules into different folders (Documents\WindowsPowerShell\Modules and
        Program Files\WindowsPowerShell\Modules, or Documents\PowerShell\Modules and Program
        Files\PowerShell\Modules), and each uses its own package manager defaults. So the other
        edition's modules are managed from a hidden process of that edition, reached through the
        named pipe every PowerShell process opens for Enter-PSHostProcess. It works in both
        directions, as the current user, without WinRM.

        The process is started with the PSModulePath a new process would get, not this session's:
        PowerShell 7 adds its own folders to PSModulePath, and Windows PowerShell would otherwise see
        PowerShell 7's modules as its own. It waits on its standard input, so it exits when that's
        closed (Disconnect-MMRemote), or when this process ends.

        Returns the remote target the terminal UI works with (see Initialize-MMRemote), plus the
        Process, which Disconnect-MMRemote stops.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('Desktop', 'Core')][string]$Edition
    )
    if (-not $script:MMIsWindows) { throw 'Windows PowerShell is only available on Windows, so there is no other edition to manage here.' }
    if ($Edition -eq $PSVersionTable.PSEdition) {
        throw "This is already $(if ($Edition -eq 'Desktop') { 'Windows PowerShell' } else { 'PowerShell 7' }): run modman without -Edition to manage its modules."
    }

    if ($Edition -eq 'Desktop') {
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $exe)) { throw "Windows PowerShell wasn't found at $exe." }
    }
    else {
        $exe = @(Get-Command -Name pwsh -CommandType Application -ErrorAction SilentlyContinue)[0].Source
        if (-not $exe) {
            $exe = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
            if (-not (Test-Path -LiteralPath $exe)) { throw 'PowerShell 7 (pwsh) was not found. Install it, or add it to PATH.' }
        }
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($exe, '-NoLogo -NoProfile -NonInteractive -Command "$null = [Console]::In.ReadToEnd()"')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    # What a process started from Explorer gets: the user's value if they've set one, otherwise the
    # machine's. Each edition then adds its own default folders.
    $modulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'User')
    if (-not $modulePath) { $modulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') }
    if ($modulePath) { $startInfo.EnvironmentVariables['PSModulePath'] = $modulePath }
    else { [void]$startInfo.EnvironmentVariables.Remove('PSModulePath') }

    try { $process = [System.Diagnostics.Process]::Start($startInfo) }
    catch { throw "Could not start $exe`: $($_.Exception.Message)" }

    $runspace = $null
    try {
        # The pipe opens a moment after the process starts.
        $deadline = [datetime]::UtcNow.AddSeconds(30)
        while ($true) {
            if ($process.HasExited) { throw "it exited with code $($process.ExitCode)" }
            try {
                $info = [System.Management.Automation.Runspaces.NamedPipeConnectionInfo]::new($process.Id)
                $info.OpenTimeout = 2000
                $runspace = [runspacefactory]::CreateRunspace($info)
                $runspace.Open()
                break
            }
            catch {
                if ($runspace) { $runspace.Dispose(); $runspace = $null }
                if ([datetime]::UtcNow -ge $deadline) { throw $_.Exception.Message }
                Start-Sleep -Milliseconds 100
            }
        }

        $ps = [powershell]::Create()
        $ps.Runspace = $runspace
        try { $version = @($ps.AddScript('$PSVersionTable.PSVersion.ToString()').Invoke())[0] }
        finally { $ps.Dispose() }
        $name = if ($Edition -eq 'Desktop') { "Windows PowerShell $version" } else { "PowerShell $version" }
    }
    catch {
        if ($runspace) { $runspace.Dispose() }
        Stop-MMEditionProcess $process
        throw "Could not connect to $exe`: $($_.Exception.Message)"
    }

    try { $remote = Initialize-MMRemote -Runspace $runspace -Name $name }
    catch { Stop-MMEditionProcess $process; throw }
    $remote.Process = $process
    $remote
}
