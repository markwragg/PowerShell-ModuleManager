# Change Log

## [0.5.0] - 2026-11-20

* [feature] The terminal UI can be used with the mouse. Click a module to move to it, and double-click it for its details (right-click to go back). Click its `[ ]` box to select it, a family's arrow to expand or collapse it, a column header to sort by that column, and `view:` or `sort:` in the title bar to cycle them. Click a key in the help bar to press it, and y or N to answer a confirmation. The wheel scrolls the list, the details view and the output pane, and right-click (or clicking `L hide` in its header) hides the output pane.  On Windows it uses the console's own mouse input; elsewhere it needs a terminal that reports the mouse in xterm's SGR format, as most do. Hold Shift to select text in the terminal while modman has the mouse, or use `Show-ModuleManager -NoMouse` to leave it to the terminal.
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
