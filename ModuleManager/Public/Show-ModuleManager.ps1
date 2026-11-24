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
          A                              Select every module in view with an update (press again to
                                         clear). In the Multiple versions view: every module with
                                         old versions, so V to that view, A, O removes them all
          Right                          Expand a module family, or show versions and paths
          Left                           Collapse the module family
          Enter                          Show installed versions and paths
          U                              Update selected modules (or the current one). Answer o
                                         to also remove their old versions
          X or Delete                   Uninstall everything selected: modules (all versions) and
                                         versions selected in the details view
          O                              Remove old versions, keeping the newest
          M                              Move selected modules (or the current one) to the other
                                         scope: CurrentUser or AllUsers
          L                            Show or hide the output pane
          [ and ]                        Scroll the output pane back and forward
          /                              Filter by name or description. Start the filter with n:
                                         to match only names, or d: only descriptions
          V                              Cycle view: All, Updates, Multiple versions, Loaded
          S                              Cycle sort: Name, Status, Versions, Scope (an expanded
                                         family's members are sorted under it)
          C                              Cycle scope: All, AllUsers, CurrentUser, System, Other
                                         (skipping scopes with no modules). Shows the modules
                                         with a version in that scope
          G                              Turn grouping of module families on or off
          R                              Rescan and re-check repositories
          Esc                            Close the output pane, then clear selection, then filter
          Q                              Quit (Ctrl+C while an operation is running stops it)

        Keys (details view):
          Space                          Select / deselect a version (selections are kept when you
                                         go back, so you can pick versions of several modules)
          X or Delete                    Uninstall the selected versions, of every module (or the
                                         current one)
          O                              Remove all but the newest version
          U                              Update this module (o also removes its old versions)
          P                             Open the module's project page (or its PowerShell
                                         Gallery page) in the browser
          Esc, Left or Backspace         Back to the list

        The details view shows each version's size, and the module's project and gallery pages
        (click one to open it). Under the versions is what the version under the cursor depends on
        (with the installed version that satisfies each dependency) and which installed modules
        depend on it and accept that version. Only the modules in the list are looked at, so a
        dependency outside it (such as a system module, without -IncludeSystem) shows as not found.

        Modules and versions their publisher has unlisted (withdrawn, often because they're deprecated)
        are flagged. A module unlisted from its repository shows Unlisted in the list and a warning in
        the details view. Unlisted installed versions are marked in the details view, with a warning
        when the cursor is on one, and a module whose newest installed version is unlisted (with no
        newer version to update to) shows Version unlisted. Versions are checked in NuGet v2 feeds,
        such as the PowerShell Gallery; other repositories can only report a whole module unlisted.

        Mouse: click a module to move to it, and double-click it (or click Enter in the help bar) for
        its versions and paths; right-click goes back. Click the [ ] box to select it, a family's arrow
        to expand or collapse the family, and a column header (Name, #, Scope, Status) to sort by it,
        or view:, sort: or scope: in the title bar to cycle them. Click a key in the help bar to press it, and
        y or N to answer a confirmation. The wheel scrolls the list, the details and the output pane;
        right-click, or L hide in its header, hides the pane. While modman has the mouse, select text
        in the terminal with Shift held down. -NoMouse leaves the mouse to the terminal.

        Text pasted into the terminal is ignored (except into the filter), so a paste can't run
        keys as commands. Some terminals paste on right-click instead of passing it on, such as
        VS Code's on Windows: set terminal.integrated.rightClickBehavior to "default" (a menu)
        or "nothing" in VS Code's settings to stop that.

        When you update, the confirmation offers y (update) or o (update, then remove the old
        versions of the modules that were updated, and of dependencies installed with them,
        keeping the newest), so you don't need to press O afterwards. As with O, old versions that
        other installed modules depend on are kept, and so are loaded ones.

        Modules marked with * are loaded in the current session. When you uninstall or remove old
        versions and some of them are loaded, the confirmation offers y (leave the loaded versions
        installed) or f (unload them from the session first, so they're removed too). Modules that
        use .NET assemblies, ModuleManager itself and the package manager can't be unloaded safely,
        so they're skipped with the reason; remove them from a new session.

        On Windows, actions that need administrator rights (moving modules, and updating,
        uninstalling or removing old versions of modules installed for all users) run as
        administrator when this session isn't: the confirmation says so, Windows asks for
        permission, and the action runs in a hidden elevated PowerShell process while the UI stays
        as it is. Choosing No at the Windows prompt changes nothing.

        With -WhatIf, nothing is changed: WHATIF shows in the title bar, and updates, uninstalls,
        moves and removing old versions run as usual but only say, in the output pane, what they
        would change. Confirmations still ask first, and nothing runs as administrator.

        The terminal UI always asks before changing anything, so -Confirm (or -Confirm:$false) has
        no effect, and warns that it doesn't. To update or uninstall without prompts, use
        Update-ManagedModule or Uninstall-ManagedModule with -Confirm:$false.

        With -Verbose, operations write their verbose messages to the output pane as they run (for
        example, which dependencies an update installed, or why old versions were kept).

        If the update check fails because PowerShellGet needs the NuGet package provider (Windows
        PowerShell's built-in PowerShellGet 1.0 does), you're offered to install it for the current
        user, after which the check runs again.

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
        G, or -NoGroup, lists every module separately.
        A view or filter shows the matching members under their family.

    .PARAMETER Name
        Only show modules matching these names. Wildcards are supported. Accepts pipeline input:
        names, or objects with a Name property, such as the output of Get-ManagedModuleUpdate,
        Get-ManagedModule or Get-Module.

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

    .PARAMETER NoMouse
        Don't use the mouse: leave it to the terminal, for selecting and copying text as usual.

    .PARAMETER NoGroup
        Open the UI with module families ungrouped, listing every module separately. Press G to
        group them. -Ungroup also works.

    .PARAMETER View
        The view the UI opens in: All (the default), Updates, MultipleVersions or Loaded. Press V
        to change it.

    .PARAMETER Sort
        The order the UI opens in: Name (the default), Status, Versions, Scope or Reclaimable. Press S
        to change it. Reclaimable (the space removing old versions would free, most first) only applies
        in the Multiple versions view, when the screen is at least 100 characters wide; otherwise
        it's Name.

    .PARAMETER ThrottleLimit
        The maximum number of concurrent repository queries. Queries made with PowerShellGet's own commands (for a repository that isn't a NuGet v2 feed, or a feed that can't be reached) still run one at a time.

    .PARAMETER ComputerName
        Manage the modules on this computer instead, over PowerShell remoting. The UI runs here;
        scanning, repository checks, updates and uninstalls run on that computer, as the user you
        connect as. ModuleManager doesn't need to be installed there: it's sent for the session.

    .PARAMETER Credential
        The credentials to connect to -ComputerName with.

    .PARAMETER ConfigurationName
        The session configuration (endpoint) to connect to on -ComputerName. By default that's
        Microsoft.PowerShell, which is Windows PowerShell; use PowerShell.7 (registered by running
        Enable-PSRemoting in PowerShell 7) to manage the PowerShell 7 modules there.

    .PARAMETER Session
        Manage the modules on the computer this PSSession is connected to (any transport, such as
        WinRM or SSH). The session itself is left as it is: ModuleManager opens its own connection
        using the same connection details, and closes it when you quit.

    .PARAMETER Edition
        Manage the modules of the other PowerShell edition on this computer: Desktop for Windows
        PowerShell 5.1 (from PowerShell 7), or Core for PowerShell 7 (from Windows PowerShell). The
        editions install modules into different folders and use their own package manager defaults,
        so scanning, repository checks, updates and uninstalls run in a hidden process of that
        edition, which closes when you quit. Windows only. Naming the edition this is runs it here,
        as without -Edition.

    .EXAMPLE
        Show-ModuleManager

        Opens the terminal UI listing all installed modules, and checks for updates in the background.

    .EXAMPLE
        modman -Name Az.*

        Opens the terminal UI (via its alias) showing only the Az modules.

    .EXAMPLE
        Get-ManagedModuleUpdate -Outdated | modman

        Opens the terminal UI showing only the modules that have updates.

    .EXAMPLE
        modman -ComputerName Server01

        Manages the modules installed on Server01, from this console.

    .EXAMPLE
        modman -ComputerName Server01 -ConfigurationName PowerShell.7 -Credential (Get-Credential)

        Manages the PowerShell 7 modules on Server01, connecting as another user.

    .EXAMPLE
        $s = New-PSSession -HostName linux01 -UserName admin
        Show-ModuleManager -Session $s

        Manages the modules on linux01, connecting over SSH.

    .EXAMPLE
        modman -View Updates -Sort Scope

        Opens the terminal UI showing only the modules with updates (once the update check has
        found them), sorted by scope.

    .EXAMPLE
        modman -WhatIf

        Opens the terminal UI in WhatIf mode, to see what updates and uninstalls would do without
        changing anything.

    .EXAMPLE
        modman -Edition Desktop

        From PowerShell 7, manages the modules Windows PowerShell 5.1 uses on this computer.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Local')]
    [Alias('modman')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = '-WhatIf puts the terminal UI in WhatIf mode, where operations only say what they would change (see Test-MMShouldProcess).')]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [SupportsWildcards()]
        [string[]]$Name = '*',

        [ValidateSet('CurrentUser', 'AllUsers', 'System', 'Other')]
        [string[]]$Scope,

        [switch]$IncludeSystem,

        [switch]$IncludePrerelease,

        [string]$Repository,

        [switch]$NoUpdateCheck,

        [switch]$NoMouse,

        [Alias('Ungroup')]
        [switch]$NoGroup,

        [ValidateSet('All', 'Updates', 'MultipleVersions', 'Loaded')]
        [string]$View = 'All',

        [ValidateSet('Name', 'Status', 'Versions', 'Scope', 'Reclaimable')]
        [string]$Sort = 'Name',

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 16,

        [Parameter(Mandatory, ParameterSetName = 'ComputerName')]
        [string]$ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [pscredential]$Credential,

        [Parameter(ParameterSetName = 'ComputerName')]
        [string]$ConfigurationName,

        [Parameter(Mandatory, ParameterSetName = 'Session')]
        [System.Management.Automation.Runspaces.PSSession]$Session,

        [Parameter(Mandatory, ParameterSetName = 'Edition')]
        [ValidateSet('Desktop', 'Core')]
        [string]$Edition
    )

    begin { $names = [System.Collections.Generic.List[string]]::new() }
    process { foreach ($n in $Name) { if (-not $names.Contains($n)) { $names.Add($n) } } }
    end {
        # -WhatIf is the UI's WhatIf mode, for the operations it runs (see Invoke-MMTuiAction).
        # In this session it would stop the UI's own work (temporary files, connections), and
        # -Confirm would ask about it, so neither applies here.
        $whatIf = [bool]$WhatIfPreference
        $WhatIfPreference = $false
        if ($PSBoundParameters.ContainsKey('Confirm')) {
            $ConfirmPreference = 'High'
            Write-Warning ('Show-ModuleManager always asks before changing anything; -Confirm has no effect. To update or ' +
                'uninstall without prompts, use Update-ManagedModule or Uninstall-ManagedModule with -Confirm:$false.')
        }

        # Nothing piped (such as Get-ManagedModuleUpdate -Outdated with nothing outdated) shouldn't open
        # the UI on every module.
        if ($names.Count -eq 0) {
            if ($MyInvocation.ExpectingInput) { Write-Warning 'No modules were piped to Show-ModuleManager.'; return }
            $names.Add('*')
        }

        if (-not (Test-MMInteractiveConsole)) {
            throw ('Show-ModuleManager needs an interactive console, so it does not work inside Enter-PSSession or Invoke-Command. ' +
                'To manage another computer, run it here with -ComputerName or -Session, or use Get-ManagedModule and Get-ManagedModuleUpdate.')
        }

        $remote = $null
        # The edition this is runs here, as without -Edition.
        if ($PSCmdlet.ParameterSetName -ne 'Local' -and $Edition -ne $PSVersionTable.PSEdition) {
            Write-Progress -Activity 'Show-ModuleManager' -Status 'Connecting...'
            try {
                if ($Edition) { $remote = Connect-MMEdition -Edition $Edition }
                else { $remote = Connect-MMRemote -ComputerName $ComputerName -Credential $Credential -ConfigurationName $ConfigurationName -Session $Session }
            }
            finally { Write-Progress -Activity 'Show-ModuleManager' -Completed }
        }

        $state = New-MMTuiState -Options @{
            Name              = [string[]]$names
            Scope             = $Scope
            IncludeSystem     = [bool]$IncludeSystem
            IncludePrerelease = [bool]$IncludePrerelease
            Repository        = $Repository
            ThrottleLimit     = $ThrottleLimit
            # With -Verbose, operations (updates, uninstalls, moves) show verbose messages in the
            # output pane as they run (see Invoke-MMTuiAction).
            Verbose           = $VerbosePreference -eq 'Continue'
            WhatIf            = $whatIf
        }
        $state.Remote = $remote
        # -View and -Sort open the UI as if V and S had been pressed. ValidateSet accepts any case,
        # so match with -eq, which ignores it (IndexOf wouldn't). View names are matched without
        # spaces, so MultipleVersions is the Multiple versions view.
        $state.View = @(0..($state.Views.Count - 1)).Where({ ($state.Views[$_] -replace ' ') -eq $View })[0]
        $state.Sort = @(0..($state.Sorts.Count - 1)).Where({ $state.Sorts[$_] -eq $Sort })[0]
        # -NoGroup opens the UI as if G had been pressed.
        $state.Group = -not $NoGroup

        # Progress would be drawn over the terminal UI, and as only the lines that change are redrawn
        # (see Write-MMTuiFrame), it would stay there. This also applies to the commands this calls.
        # So would verbose messages, which operations send to the output pane instead.
        $ProgressPreference = 'SilentlyContinue'
        $VerbosePreference = 'SilentlyContinue'

        $originalEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $script:MMTuiHyperlink = Test-MMTuiHyperlink
            # In this session, WhatIf mode skips administrator rights and unloading modules (see
            # Test-MMTuiNeedsElevation and Remove-MMSessionModule).
            $script:MMTuiWhatIf = $whatIf
            Enter-MMTuiScreen
            # The first scan can take a few seconds (many modules, or a slow disk or connection), so
            # say what's happening rather than leaving the screen blank.
            $state.Scanning = $true
            Write-MMTuiFrame $state
            # After the first frame, as on Windows this compiles a helper the first time (under a second).
            if (-not $NoMouse) { $state.Mouse = Enable-MMTuiMouse }
            try { Update-MMTuiRows $state }
            finally { $state.Scanning = $false }
            if ($NoUpdateCheck) { Set-MMTuiMessage $state 'Update check skipped. Press R to check repositories.' }
            else { Start-MMTuiLookup $state }
            Update-MMTuiVisible $state

            $dirty = $true
            $lastSpin = [datetime]::MinValue
            while (-not $state.Quit) {
                if ($state.Job -and (Receive-MMTuiLookup $state)) { Update-MMTuiVisible $state; $dirty = $true }
                if ($state.Task -and (Receive-MMTuiTask $state)) { $dirty = $true }
                if ($state.Detail -and $state.Mode -ne 'list' -and (Update-MMTuiDetailSize $state)) { $dirty = $true }
                if ($state.Mode -eq 'list' -and (Update-MMTuiReclaimable $state)) {
                    # Sorted by Reclaimable, the list is sorted again once it's all worked out.
                    Update-MMTuiVisible $state -IfChanged
                    $dirty = $true
                }
                if ($state.Job -or $state.Task) {
                    if (([datetime]::UtcNow - $lastSpin).TotalMilliseconds -ge 150) {
                        $state.Spinner++; $lastSpin = [datetime]::UtcNow; $dirty = $true
                    }
                }
                $size = Get-MMConsoleSize
                if ($size.Width -ne $state.Width -or $size.Height -ne $state.Height) {
                    $dirty = $true
                    # Narrowing the screen can hide the Reclaimable column, which then can't be the sort.
                    if ($state.Sorts[$state.Sort] -eq 'Reclaimable' -and -not (Test-MMTuiReclaimShown $state $size.Width)) { $state.Sort = 0; Update-MMTuiVisible $state }
                }
                if ($dirty) { Write-MMTuiFrame $state; $dirty = $false }

                $received = Read-MMTuiInput -State $state
                if ($null -eq $received) {
                    # Ignoring pasted text leaves nothing to handle, but a message to show.
                    if ($state.Redraw) { $state.Redraw = $false; $dirty = $true; continue }
                    Start-Sleep -Milliseconds 30; continue
                }
                if ($received -is [ConsoleKeyInfo]) { Invoke-MMTuiKey -State $state -Key $received }
                else { Invoke-MMTuiMouse -State $state -Mouse $received }
                Update-MMTuiVisible $state -IfChanged
                $dirty = $true
            }
        }
        finally {
            Stop-MMTuiTask $state -Closing
            Stop-MMTuiLookup $state -Closing
            Stop-MMTuiReclaimable $state
            Disable-MMTuiMouse $state.Mouse
            Exit-MMTuiScreen
            $script:MMTuiHyperlink = $false
            $script:MMTuiWhatIf = $false
            [Console]::OutputEncoding = $originalEncoding
            Disconnect-MMRemote $remote
        }
    }
}
