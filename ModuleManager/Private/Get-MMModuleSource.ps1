function Get-MMModuleSource {
    <#
    .SYNOPSIS
        Returns this module's source code as one script, so it can be sent to a remote session.

    .DESCRIPTION
        The built module is a single .psm1; the source tree is one file per function (plus
        _Initialize.ps1), which are joined. Either way the result defines every function and the
        module's settings when run as a dynamic module (see Initialize-MMRemote).
    #>
    $module = $ExecutionContext.SessionState.Module
    $private = Join-Path $module.ModuleBase 'Private'
    if (Test-Path -LiteralPath $private) {
        $files = @(Get-ChildItem -Path (Join-Path $module.ModuleBase 'Public'), $private -Filter '*.ps1' | Sort-Object FullName)
        return (@(foreach ($f in $files) { [IO.File]::ReadAllText($f.FullName) }) -join "`n")
    }
    [IO.File]::ReadAllText($module.Path)
}
