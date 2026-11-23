function Request-MMTuiNuGetProvider {
    <#
    .SYNOPSIS
        Offers to install the NuGet provider when update checks failed because PowerShellGet needs it.

    .DESCRIPTION
        PowerShellGet 1.x (as shipped with Windows PowerShell) needs the NuGet package provider, and
        asks to install it, which can't be answered where modman runs its checks. So modman asks
        instead, once per session: the provider is installed for the current user (no elevation
        needed) on the computer being managed, and the update check runs again.

        It isn't offered while another action is running or a filter or prompt is open; the status
        line still says what's wrong.
    #>
    param([hashtable]$State, [object[]]$Failed)
    if ($State.NuGetOffered -or $State.Task -or $State.Mode -notin 'list', 'details') { return }
    $needs = @($Failed | Where-Object {
            $_.Result -and $_.Result.PSObject.Properties['Error'] -and [string]$_.Result.Error -like '*needs the NuGet package provider*'
        })
    if (-not $needs) { return }
    $State.NuGetOffered = $true

    $where = ''
    if ($State.Remote) { $where = " on $($State.Remote.Name)" }
    $prompt = "PowerShellGet$where needs the NuGet provider to check $($needs.Count) module(s) for updates. Install it for the current user now?"
    Request-MMTuiConfirm $State $prompt -Data @{} -Action {
        param($State)
        Invoke-MMTuiAction $State 'Installing the NuGet provider' -Data @{} -Action {
            if ($script:MMTuiWhatIf) { Write-MMTuiOutput '  What if: Install package provider - NuGet (CurrentUser)' 'Yellow'; return }
            $provider = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -ErrorAction Stop
            Write-MMTuiOutput "  Installed  NuGet provider $($provider.Version)" 'Green'
            Write-MMTuiOutput '  Checking for updates again...'
        } -OnComplete {
            param($State)
            Start-MMTuiLookup $State -Refresh
        }
    }
}
