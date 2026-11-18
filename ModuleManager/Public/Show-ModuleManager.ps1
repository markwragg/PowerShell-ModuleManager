function Show-ModuleManager {
    <#
    .SYNOPSIS
        Opens an interactive terminal UI for browsing, updating and uninstalling modules.

    .DESCRIPTION
        Shows every installed module with its installed version, the latest version in its
        repository, how many versions are installed and where. The update check runs in the
        background, so you can use the list straight away.

        Keys (module list):
          Up/Down, PgUp/PgDn, Home/End   Move
          Space                          Select / deselect module (a collapsed family: all of it)
          A                              Select every module with an update (press again to clear)
          Right                          Expand a module family, or show versions and paths
          Left                           Collapse the module family
          Enter                          Show installed versions and paths
          U                              Update selected modules (or the current one)
          X or Delete                    Uninstall selected modules (all versions)
          O                              Remove old versions, keeping the newest
          L                              Show or hide the output pane
          [ and ]                        Scroll the output pane back and forward
          /                              Filter by name or description
          V                              Cycle view: All, Updates, Multiple versions, Loaded
          S                              Cycle sort: Name, Status, Versions, Scope
          G                              Turn grouping of module families on or off
          R                              Rescan and re-check repositories
          Esc                            Close the output pane, then clear selection, then filter
          Q                              Quit (Ctrl+C while an operation is running stops it)

        Keys (details view):
          Space                          Select / deselect a version
          X or Delete                    Uninstall selected versions (or the current one)
          O                              Remove all but the newest version
          U                              Update this module
          Esc, Left or Backspace         Back to the list

        Modules marked with * are loaded in the current session.

        Updates, uninstalls and removing old versions run in the background, with their progress
        and output in a pane at the bottom of the screen, so the list stays on screen and you can
        keep browsing. Only one operation runs at a time. When it finishes the list is rescanned
        and the output stays in the pane until you close it (Esc or L). Nothing can answer a
        prompt while an operation runs, so you're asked beforehand: for example, updating from
        an untrusted repository says so in the confirmation.

        Module families: a module that depends on two or more installed modules named after it
        (Az and the Az.* modules, or Microsoft.Graph and Microsoft.Graph.*) is shown as one
        collapsed row, with the number of family members and how many have updates. U, X, O
        and Space on a collapsed family act on the whole family; expand it to act on one member.
        A view or filter shows the matching members under their family.

    .PARAMETER Name
        Only show modules matching these names. Wildcards are supported.

    .PARAMETER Scope
        Only show modules in these scopes.

    .PARAMETER IncludeSystem
        Include modules that ship with PowerShell or Windows.

    .PARAMETER IncludePrerelease
        Consider prerelease versions when checking for updates.

    .PARAMETER Repository
        Check this repository instead of the one each module was installed from.

    .PARAMETER NoUpdateCheck
        Don't check repositories when the UI opens. Press R to check later.

    .PARAMETER ThrottleLimit
        The maximum number of concurrent repository queries.

    .EXAMPLE
        Show-ModuleManager

        Opens the terminal UI listing all installed modules, and checks for updates in the background.

    .EXAMPLE
        modman -Name Az.*

        Opens the terminal UI (via its alias) showing only the Az modules.
    #>
    [CmdletBinding()]
    [Alias('modman')]
    param(
        [Parameter(Position = 0)]
        [SupportsWildcards()]
        [string[]]$Name = '*',

        [ValidateSet('CurrentUser', 'AllUsers', 'System', 'Other')]
        [string[]]$Scope,

        [switch]$IncludeSystem,

        [switch]$IncludePrerelease,

        [string]$Repository,

        [switch]$NoUpdateCheck,

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 16
    )

    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        throw 'Show-ModuleManager needs an interactive console. Use Get-ModuleInventory or Get-ModuleUpdate instead.'
    }

    $state = New-MMTuiState -Options @{
        Name              = $Name
        Scope             = $Scope
        IncludeSystem     = [bool]$IncludeSystem
        IncludePrerelease = [bool]$IncludePrerelease
        Repository        = $Repository
        ThrottleLimit     = $ThrottleLimit
    }

    $originalEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        Enter-MMTuiScreen
        Update-MMTuiRows $state
        if ($NoUpdateCheck) { Set-MMTuiMessage $state 'Update check skipped. Press R to check repositories.' }
        else { Start-MMTuiLookup $state }
        Update-MMTuiVisible $state

        $dirty = $true
        $lastSpin = [datetime]::MinValue
        while (-not $state.Quit) {
            if ($state.Job -and (Receive-MMTuiLookup $state)) { Update-MMTuiVisible $state; $dirty = $true }
            if ($state.Task -and (Receive-MMTuiTask $state)) { $dirty = $true }
            if ($state.Job -or $state.Task) {
                if (([datetime]::UtcNow - $lastSpin).TotalMilliseconds -ge 150) {
                    $state.Spinner++; $lastSpin = [datetime]::UtcNow; $dirty = $true
                }
            }
            if ([Console]::WindowWidth - 1 -ne $state.Width -or [Console]::WindowHeight -ne $state.Height) { $dirty = $true }
            if ($dirty) { Write-MMTuiFrame $state; $dirty = $false }

            if (-not [Console]::KeyAvailable) { Start-Sleep -Milliseconds 30; continue }
            $key = [Console]::ReadKey($true)
            Invoke-MMTuiKey -State $state -Key $key
            Update-MMTuiVisible $state
            $dirty = $true
        }
    }
    finally {
        Stop-MMTuiTask $state
        Stop-MMGalleryLookup $state.Job
        Exit-MMTuiScreen
        [Console]::OutputEncoding = $originalEncoding
    }
}
