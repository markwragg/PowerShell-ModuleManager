function Get-MMScope {
    <#
    .SYNOPSIS
        Classifies a module path as System, CurrentUser, AllUsers or Other.

    .DESCRIPTION
        Classifies a module path:
          System      - ships with PowerShell or the OS ($PSHOME, Windows directory)
          CurrentUser - under the user's profile
          AllUsers    - machine-wide install location (Program Files, /usr/local/share)
          Other       - anything else on PSModulePath
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    if (Test-MMPathUnder $Path $PSHOME) { return 'System' }
    if ($script:MMIsWindows -and (Test-MMPathUnder $Path $env:windir)) { return 'System' }

    $userBases = @($HOME, $env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA)
    try { $userBases += [Environment]::GetFolderPath('MyDocuments') } catch { Write-Debug $_ }
    foreach ($base in $userBases) {
        if (Test-MMPathUnder $Path $base) { return 'CurrentUser' }
    }

    $machineBases = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:ProgramData,
        '/usr/local/share/powershell', '/usr/share/powershell', '/opt/microsoft/powershell')
    foreach ($base in $machineBases) {
        if (Test-MMPathUnder $Path $base) { return 'AllUsers' }
    }
    'Other'
}
