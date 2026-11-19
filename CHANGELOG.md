# Change Log

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
