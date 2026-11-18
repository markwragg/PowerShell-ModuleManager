# Change Log

## [0.1.1] - 2026-11-18

* Fixed the terminal UI showing several "Failed" lines for one failed update.
* Fixed the checkbox and version running together in the terminal UI's details view.

## [0.1.0] - 2026-11-18

* Initial version: `Get-ModuleInventory`, `Get-ModuleUpdate`, `Get-ModuleLocation`, `Update-ManagedModule`, `Uninstall-ManagedModule`, `Uninstall-OldModuleVersion` and the `Show-ModuleManager` terminal UI (alias `modman`).
* `Update-ManagedModule` shows a progress bar while installing, and the terminal UI shows one result line per module instead of the package manager's verbose output.
* Dependency awareness, for module families such as Az:
  * Dependencies and their version ranges are read from `PSGetModuleInfo.xml` (PSResourceGet and PowerShellGet formats), falling back to the manifest's `RequiredModules` and versioned `ModuleList` entries. They're shown as `Dependencies` on inventory objects.
  * `Uninstall-ManagedModule` blocks removing any version another installed module needs (for example an `Az.*` version that an `Az` rollup pins), not just the last version of a module listed in `RequiredModules`. `Uninstall-OldModuleVersion` keeps such versions and warns.
  * `Update-ManagedModule` installs dependencies first, skips modules an earlier update already installed as a dependency (reported through `UpdatedAsDependencyOf` with `-PassThru`), warns up front when a loaded module is too old for the new versions, and runs `-RemoveOldVersions` once at the end.
  * `Get-ModuleUpdate` returns the latest version's dependencies as `LatestDependencies`.
  * The terminal UI groups module families (for example `Az` and its `Az.*` modules) into one collapsible row. Actions on a collapsed family apply to all of it, and G turns grouping off.
* The terminal UI runs updates, uninstalls and old-version removal in the background, showing progress and output in a pane at the bottom of the screen instead of leaving the UI. L shows or hides the pane and `[` `]` scroll it.
* Fixed spurious "What if: Retrieve the value for property" messages when using `-WhatIf`.
