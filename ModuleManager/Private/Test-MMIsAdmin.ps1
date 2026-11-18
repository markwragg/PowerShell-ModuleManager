function Test-MMIsAdmin {
    <#
    .SYNOPSIS
        Returns $true if the session is elevated (administrator on Windows, root elsewhere).
    #>
    if ($script:MMIsWindows) {
        $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    try { return ((& id -u) -eq '0') } catch { return $false }
}
