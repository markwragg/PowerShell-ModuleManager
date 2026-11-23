# Change Log

## [0.10.2] - 2026-11-23

* [fix] A module version's install date (`InstalledDate`, and the Installed column in the terminal UI's details view) is now when that version was installed. For modules updated with `Update-Module`, it used to show when the first version of the module was installed, as PowerShellGet copies that date into each new version's record (it records when the new version was installed as `UpdatedDate`, which is now used when it's later).

## [0.10.1] - 2026-11-23

* [fix] The terminal UI ignores text pasted into the terminal, which it used to take as key presses, one command per character: a clipboard holding "xy" would uninstall the module under the cursor. That's easy to do by accident, as some terminals paste on right-click, such as VS Code's on Windows (set `terminal.integrated.rightClickBehavior` to `default` or `nothing` to stop it). Keys that arrive together are taken as pasted when they're different and include a character (holding a key down, or arrow keys queuing up during a redraw, still work), and a confirmation only takes a key that arrives on its own. Text pasted into the filter is kept, without Enter or Esc.

## [0.10.0] - 2026-11-21

* [feature] **Breaking:** the commands are renamed so they all use the `ManagedModule` noun. The old `Get-` names still work, as aliases, but `Uninstall-OldModuleVersion` is removed, so update any scripts that use it:
  * `Get-ModuleInventory` → `Get-ManagedModule` (alias kept)
  * `Get-ModuleUpdate` → `Get-ManagedModuleUpdate` (alias kept)
  * `Get-ModuleLocation` → `Get-ManagedModuleLocation` (alias kept)
  * `Uninstall-OldModuleVersion` → `Uninstall-ManagedModule -OldVersions` (with `-Keep` as before), for example `Uninstall-ManagedModule Az.* -OldVersions -WhatIf`

  `Uninstall-ManagedModule` also has a `-PassThru` switch, which outputs the versions it removed.
* [feature] `Show-ModuleManager` (`modman`) takes module names from the pipeline: names, or objects with a `Name` property, such as the output of `Get-ManagedModuleUpdate`, `Get-ManagedModule` or `Get-Module`. For example, `Get-ManagedModuleUpdate -Outdated | modman` opens the terminal UI on just the modules with updates. When nothing is piped (nothing is outdated, say), it warns instead of opening on every module.

## [0.9.0] - 2026-11-21

* [feature] In the terminal UI, A in the **Multiple versions** view selects every module in view that has old versions (the help bar shows `A select old`), so V to that view, A, then O removes the old versions of them all, keeping the newest. In the other views, A still selects the modules with updates.

## [0.8.0] - 2026-11-21

* [feature] The terminal UI warns about modules and versions their publisher has unlisted. For an unlisted module, the details view shows the PowerShell Gallery's warning: "The owner has unlisted this package. This could mean that the module is deprecated or shouldn't be used anymore." The repository check now also finds which installed versions have been unlisted (in NuGet v2 feeds such as the PowerShell Gallery, with one extra request per batch of modules). The details view marks them, with a warning when the cursor is on one, and a module whose newest installed version is unlisted shows **Version unlisted** when there's no newer version to update to (before, it showed as up to date, or as newer than the repository). `Get-ModuleUpdate` reports this as the new `VersionUnlisted` status.

* [fix] The terminal UI no longer flickers while the update check runs (as when it first lists the modules). It used to repaint the whole screen several times a second, for the spinner and each batch of repository results; now it redraws only the lines that changed, and in terminals that support synchronized output (such as Windows Terminal) each frame appears all at once. The repository check's web requests also no longer draw progress bars over the screen.
* [fix] The terminal UI responds faster with many modules: drawing the screen takes about a third of the time it did, and moving the cursor or selecting no longer re-sorts the list.

## [0.7.0] - 2026-11-21

* [feature] In the terminal UI, updating and removing old versions is one step. When you press U, the confirmation offers **o** as well as **y**: it updates the modules, then removes their old versions (and those of any dependencies installed with them), keeping the newest, so you no longer need to press O afterwards. A module whose update failed keeps its old versions, and as with O, old versions that other installed modules depend on are kept, as are loaded ones. When removing an old version installed for all users needs administrator rights but the update doesn't, the confirmation says that **o** runs as administrator. From the command line, `Update-ManagedModule -RemoveOldVersions` already does this in one step.
* [fix] `Update-ManagedModule` (and U in the terminal UI) installed updates with PSResourceGet whenever it was available, so a module installed with `Install-Module` was no longer recognised by PowerShellGet afterwards: `Update-Module` said it "was not installed by using Install-Module", and `Get-InstalledModule` didn't list it. Each module is now updated with the package manager that installed it, when that's available (modules with no install record still use PSResourceGet when available, otherwise PowerShellGet). You're warned when a module has to be updated with the other package manager: when the one that installed it isn't available in the session, or for a prerelease of a module installed by PowerShellGet 1.x (as shipped with Windows PowerShell), which can't install prereleases, so PSResourceGet installs it instead. Before updating, the terminal UI now asks about a repository that either package manager doesn't trust, as each keeps its own trust setting. `Get-ModuleInventory` installations have a new `InstalledBy` property.

## [0.6.0] - 2026-11-21

* [feature] The terminal UI's details view shows more about a module. Each version's size is shown, with the total for the module (worked out when you open the details, which takes a few milliseconds per version). The module's project page and its PowerShell Gallery page are shown under its description: click one, or press P, to open it in the browser. In terminals that support hyperlinks (such as Windows Terminal and the VS Code terminal), they're also links. Below the versions, a panel shows what the version under the cursor depends on, with the installed version that satisfies each dependency (or "not found"), and which installed modules need it. `Get-ModuleInventory` objects have a new `ProjectUri` property.

## [0.5.1] - 2026-11-20

* [feature] In the terminal UI, the output pane can be used with the mouse: right-click hides it (anywhere in the list, or over the pane in the details view), as does clicking `L hide` (or `L/Esc hide`) in its header, and clicking `[` or `]` there scrolls it.

## [0.5.0] - 2026-11-20

* [feature] The terminal UI can be used with the mouse. Click a module to move to it, and double-click it for its details (right-click to go back). Click its `[ ]` box to select it, a family's arrow to expand or collapse it, a column header to sort by that column, and `view:` or `sort:` in the title bar to cycle them. Click a key in the help bar to press it, and y or N to answer a confirmation. The wheel scrolls the list, the details view and the output pane. On Windows it uses the console's own mouse input; elsewhere it needs a terminal that reports the mouse in xterm's SGR format, as most do. Hold Shift to select text in the terminal while modman has the mouse, or use `Show-ModuleManager -NoMouse` to leave it to the terminal.
* [feature] Update checks are several times faster. The PowerShell Gallery, and other NuGet v2 feeds, are now queried directly over their API, 30 modules per request, instead of with `Find-PSResource` or `Find-Module` for each module: about 230 modules take about 2 s, against about 9 s with PSResourceGet and minutes with PowerShellGet. Other repositories, and feeds that can't be reached or that need credentials, are still queried with the package manager.

## [0.4.1] - 2026-11-20

* [fix] With PowerShellGet (such as Windows PowerShell's built-in PowerShellGet 1.0), most update checks failed at random with "A parameter cannot be found that matches parameter name 'Provider'" (or 'MessageResolver'), as the PackageManagement module it uses breaks when used by several lookups at once. PowerShellGet lookups now run one at a time; installing Microsoft.PowerShell.PSResourceGet keeps them parallel and faster.

## [0.4.0] - 2026-11-20

* [feature] On Windows, the terminal UI no longer needs to be started as administrator to change modules installed for all users. Moving modules (M), and updating, uninstalling or removing old versions of `AllUsers` modules, run as administrator when the session isn't: the confirmation says so, Windows asks for permission, and the action runs in a hidden elevated PowerShell process, with its output and progress in the output pane as usual. Choosing No at the Windows prompt changes nothing.
* [feature] The terminal UI says it's scanning installed modules while it starts, instead of showing a blank screen, which could take a few seconds with many modules.
* [fix] Moving a module installed by PowerShellGet left its install record pointing at the old folder, with the warning "Access to the path ... PSGetModuleInfo.xml is denied", as PowerShellGet makes that file hidden and Windows won't overwrite hidden files. Its location is now updated, and the file stays hidden.

## [0.3.1] - 2026-11-19

* [fix] On Windows, `Move-ManagedModule` (and M in the terminal UI) keeps each module with its edition's modules. Before, a module in `Program Files\WindowsPowerShell\Modules`, which both Windows PowerShell and PowerShell 7 use, moved to `CurrentUser` from PowerShell 7 went to `Documents\PowerShell\Modules`, where Windows PowerShell doesn't look. It now goes to `Documents\WindowsPowerShell\Modules`, with a warning when the session doesn't look there (PowerShell 7 only does by default when it's started from Windows PowerShell).
* [fix] In the terminal UI on another computer (`-ComputerName`, `-Session`) or the other edition (`-Edition`), stopping the repository check or an operation could leave the connection unable to run anything else, or freeze the UI. This happened when the stop came before the command had started on the other end (for example, pressing R straight after starting), as the stop was lost and the command carried on there. Stops now wait for the command to start, and give up after a time limit; if the connection is still busy afterwards, the terminal UI reconnects, and says so.

## [0.3.0] - 2026-11-19

* [feature] `Move-ManagedModule` moves modules, or specific versions, between the `CurrentUser` and `AllUsers` scopes, for example `Move-ManagedModule Pester -Destination AllUsers`. Each version is copied (so it takes the destination folder's permissions) and the original removed only once the copy is complete; the install record is updated so PowerShellGet and PSResourceGet still recognise it. It needs an elevated session, and warns when moving to `CurrentUser` a version that a module installed for all users depends on.
* [feature] In the terminal UI, M moves the selected modules and versions (or the current one) to the other scope.
* [feature] The terminal UI's title bar shows the share of modules on their latest version (for example `32% latest`) once the repository check is done, when the window is wide enough.

## [0.2.1] - 2026-11-19

* [feature] Modules whose publisher has unlisted them from the repository (usually because they're deprecated, such as `Az.DeploymentManager`) are reported as `Unlisted` instead of `NotInRepository`, by `Get-ModuleUpdate` and in the terminal UI.

## [0.2.0] - 2026-11-19

* [feature] The terminal UI can manage the modules on another computer: `modman -ComputerName Server01` (with optional `-Credential` and `-ConfigurationName`) or `modman -Session $session` (any transport, such as SSH). The UI runs locally and everything else runs remotely; ModuleManager is sent for the session, so it doesn't need to be installed there.
* [feature] On Windows, the terminal UI can manage the other PowerShell edition's modules: `modman -Edition Desktop` from PowerShell 7 manages Windows PowerShell 5.1's modules, and `modman -Edition Core` from Windows PowerShell manages PowerShell 7's. It uses that edition's module paths and package manager, in a hidden process of that edition, without needing remoting set up.
* [feature] When the update check fails because PowerShellGet needs the NuGet package provider, the terminal UI offers to install it for the current user (no administrator rights needed) and checks again.
* [fix] Update checks and updates failed with Windows PowerShell's built-in PowerShellGet 1.0 ("A parameter cannot be found that matches parameter name 'AllowPrerelease'"), as it doesn't have the -AllowPrerelease and -AllowClobber parameters ModuleManager passed.
* [fix] Every update check failed, with no reason given, where only Windows PowerShell's built-in PowerShellGet 1.0 is available and the NuGet provider isn't installed (it asks to install the provider, which nothing can answer). The check now says how to fix it, and the terminal UI shows why lookups failed when the check finishes.

## [0.1.2] - 2026-11-19

* [feature] The terminal UI can uninstall loaded modules: when some of the versions being uninstalled or removed are loaded, the confirmation offers f to unload them from the session first. Modules that use .NET assemblies, ModuleManager itself and the package manager are skipped with the reason, as they can't be unloaded safely.
* [feature] Versions selected in the terminal UI's details view stay selected when you go back to the list, so you can select versions of several modules and uninstall them together with X. The title bar shows how many are selected, and the list marks modules with selected versions `[-]`.
* [feature] The terminal UI's help bar says when U, X and O will act on the selection ("update selected", "uninstall selected", "remove old from selected").
* [fix] Dependencies were missed when several share the same version range (as in the `Az` rollup, where about half were missed). This left many `Az.*` modules outside the `Az` family in the terminal UI, and could let `Uninstall-OldModuleVersion` and `Uninstall-ManagedModule` remove a version that a rollup still pins.

## [0.1.1] - 2026-11-18

* [fix] The terminal UI showed several "Failed" lines for one failed update.
* [fix] The checkbox and version ran together in the terminal UI's details view.

## [0.1.0] - 2026-11-18

* [feature] Initial version: `Get-ModuleInventory`, `Get-ModuleUpdate`, `Get-ModuleLocation`, `Update-ManagedModule`, `Uninstall-ManagedModule`, `Uninstall-OldModuleVersion` and the `Show-ModuleManager` terminal UI (alias `modman`).
* [feature] `Update-ManagedModule` shows a progress bar while installing, and the terminal UI shows one result line per module instead of the package manager's verbose output.
* [feature] Dependency awareness, for module families such as Az:
  * Dependencies and their version ranges are read from `PSGetModuleInfo.xml` (PSResourceGet and PowerShellGet formats), falling back to the manifest's `RequiredModules` and versioned `ModuleList` entries. They're shown as `Dependencies` on inventory objects.
  * `Uninstall-ManagedModule` blocks removing any version another installed module needs (for example an `Az.*` version that an `Az` rollup pins), not just the last version of a module listed in `RequiredModules`. `Uninstall-OldModuleVersion` keeps such versions and warns.
  * `Update-ManagedModule` installs dependencies first, skips modules an earlier update already installed as a dependency (reported through `UpdatedAsDependencyOf` with `-PassThru`), warns up front when a loaded module is too old for the new versions, and runs `-RemoveOldVersions` once at the end.
  * `Get-ModuleUpdate` returns the latest version's dependencies as `LatestDependencies`.
  * The terminal UI groups module families (for example `Az` and its `Az.*` modules) into one collapsible row. Actions on a collapsed family apply to all of it, and G turns grouping off.
* [feature] The terminal UI runs updates, uninstalls and old-version removal in the background, showing progress and output in a pane at the bottom of the screen instead of leaving the UI. L shows or hides the pane and `[` `]` scroll it.
* [fix] `-WhatIf` showed spurious "What if: Retrieve the value for property" messages.
