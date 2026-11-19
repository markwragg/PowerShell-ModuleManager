function Rename-MMFolder {
    <#
    .SYNOPSIS
        Renames (moves) a folder on the same volume in one step, failing if anything in it is in use.

    .DESCRIPTION
        A thin wrapper over [IO.Directory]::Move, so callers can rely on the rename being atomic and
        tests can simulate it failing. Throws the underlying .NET exception, not the
        MethodInvocationException PowerShell wraps it in.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Part of a move the calling cmdlet already confirmed.')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Destination
    )
    try { [IO.Directory]::Move($Path, $Destination) }
    catch {
        $e = $_.Exception
        if ($e.InnerException) { $e = $e.InnerException }
        throw $e
    }
}
