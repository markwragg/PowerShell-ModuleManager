function Open-MMWebPage {
    <#
    .SYNOPSIS
        Opens a web address (http or https only) in the default browser.

    .DESCRIPTION
        Throws if the address isn't an http or https one, or the browser can't be started. Outside
        Windows, the opener's output is discarded, so it can't write over the terminal UI.
    #>
    param([Parameter(Mandatory)][string]$Uri)
    $safe = ConvertTo-MMWebUri $Uri
    if (-not $safe) { throw "'$Uri' is not a web address." }
    if ($script:MMIsWindows) { Start-Process -FilePath $safe -ErrorAction Stop; return }
    $opener = 'xdg-open'
    if ((Test-Path -Path 'variable:IsMacOS') -and $IsMacOS) { $opener = 'open' }
    $info = [Diagnostics.ProcessStartInfo]::new($opener, $safe)
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    # Read the output so the opener can't block on a full pipe; nothing waits for it to finish.
    $null = $process.StandardOutput.ReadToEndAsync()
    $null = $process.StandardError.ReadToEndAsync()
}
