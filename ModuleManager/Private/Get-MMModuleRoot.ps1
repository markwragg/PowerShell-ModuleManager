function Get-MMModuleRoot {
    <#
    .SYNOPSIS
        Returns the PSModulePath entries in search order, de-duplicated, with their scope.
    #>
    [CmdletBinding()]
    param()
    $seen = @{}
    $order = 0
    foreach ($entry in ($env:PSModulePath -split [IO.Path]::PathSeparator)) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $full = $null
        try { $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($entry.Trim())).TrimEnd('\', '/') }
        catch { continue }
        $key = Get-MMPathKey $full
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [pscustomobject]@{
            PSTypeName = 'ModuleManager.ModuleRoot'
            Order      = $order++
            Path       = $full
            Scope      = Get-MMScope $full
            Exists     = [IO.Directory]::Exists($full)
        }
    }
}
