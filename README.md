# PowerShell-ModuleManager

[![Build Status](https://github.com/markwragg/PowerShell-ModuleManager/actions/workflows/build.yml/badge.svg)](https://github.com/markwragg/PowerShell-ModuleManager/actions/workflows/build.yml)
![coverage](https://img.shields.io/badge/coverage-0%25-red.svg)
[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/ModuleManager?label=PS%20Gallery)](https://www.powershellgallery.com/packages/ModuleManager)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/ModuleManager?color=D3D3D3)](https://www.powershellgallery.com/packages/ModuleManager)

> A PowerShell module for understanding and managing your other PowerShell modules.

- See which modules you have installed, and every version of each.
- Compare installed versions with the latest version in the gallery.
- Find out where each version is installed, and in which scope.
- Update modules, uninstall them, and clean up old versions.
- Do all of the above from an interactive terminal UI.

Works with **PSResourceGet** (`Microsoft.PowerShell.PSResourceGet`) and falls back to **PowerShellGet** if
PSResourceGet isn't installed.

## Installation

The module is published in the PowerShell Gallery, so if you have PowerShell 5.1 or newer it can be installed by running:

```powershell
Install-Module ModuleManager
```

Or

```powershell
Install-PSResource ModuleManager
```

## Quick start

```powershell
Show-ModuleManager          # interactive UI (alias: modman)
Get-ModuleUpdate -Outdated  # what can be updated?
```

## Cmdlets

| Cmdlet | Synopsis |
| --- | --- |
| `Get-ModuleInventory` | One row per installed module: newest version, number of versions, scope, repository, path. `-AllVersions` lists each version; `-MultipleVersions` shows only modules with more than one version. |
| `Get-ModuleUpdate` | Compares the newest installed version with the latest in the module's repository. Status is `UpdateAvailable`, `UpToDate`, `LocalNewer`, `NotInRepository` or `Error`. |
| `Get-ModuleLocation` | Where every version is installed. `-Summary` gives counts per `PSModulePath` entry; `-IncludeSize` adds disk usage. |
| `Update-ManagedModule` | Installs the latest version into the same scope as the existing one, showing a progress bar. `-RemoveOldVersions` removes the old versions afterwards. Supports `-WhatIf`. |
| `Uninstall-ManagedModule` | Removes modules or specific versions (`-Version 4.*`). Supports `-WhatIf` and `-Confirm`. |
| `Uninstall-OldModuleVersion` | Keeps the newest `-Keep` versions of each module and removes the rest. Supports `-WhatIf` and `-Confirm`. |
| `Show-ModuleManager` | The terminal UI. |

See the [Documentation](/Documentation/) folder for full help on each cmdlet.

All of these accept wildcards and pipeline input:

```powershell
Get-ModuleUpdate -Outdated | Update-ManagedModule -RemoveOldVersions -WhatIf
Get-ModuleInventory -MultipleVersions | Sort-Object VersionCount -Descending
Get-ModuleLocation Pester | Where-Object Version -like '4.*' | Uninstall-ManagedModule
Get-ModuleLocation -Summary -IncludeSize
Uninstall-OldModuleVersion Az.* -WhatIf
```

## Terminal UI

```
 ModuleManager  222 modules  |  151 updates  |  view: All  |  sort: Status    | / Updating 76 module(s) 41%
    Name                          Installed       Latest           #  Scope        Status
 [ ]  AIShell                     1.0.3-preview3  1.0.8-preview8   1  CurrentUser  Update available
 [x]► Az (+92)                    13.2.0          17.0.0           9  CurrentUser  75 updates
 [ ]  Az.CostManagement           0.4.2                            2  CurrentUser  Up to date
 [ ]  Pester                      6.2.0           6.2.0           11  CurrentUser… Up to date
 ...
 Output: Updating 76 module(s)  (/ running 1:12)                                    [ ] scroll  L hide
 [################------------------------]  41%  32 of 76: Az.KeyVault 6.3.1 -> 6.4.0
 WARNING: Az.Accounts 5.4.0 is loaded in this session, but Az.Aks 7.1.0 needs [5.5.0, ); ...
 Updating 76 module(s)...
 Up/Dn move  Space select  A select updates  Enter details  U update  X uninstall  O remove old ...
```

The update check runs in the background, so you can use the list while it fills in.

| Key | Module list | Details view (Enter) |
| --- | --- | --- |
| ↑ ↓ / PgUp PgDn / Home End (or j k) | Move | Move |
| Space | Select a module (a collapsed family: all of it) | Select a version |
| A | Select every module with an update (press again to clear) | |
| → | Expand a module family, or show versions and paths | |
| ← | Collapse the module family | Back to the list |
| Enter | Show versions and paths | |
| U | Update the selected modules (or the current one) | Update this module |
| X / Del | Uninstall the selected modules (all versions) | Uninstall the selected versions |
| O | Remove old versions, keeping the newest | Same, for this module |
| L | Show or hide the output pane | Same |
| [ ] | Scroll the output pane back and forward | Same |
| / | Filter by name or description | |
| V | Cycle the view: All, Updates, Multiple versions, Loaded | |
| S | Cycle the sort: Name, Status, Versions, Scope | |
| G | Turn grouping of module families on or off | |
| R | Rescan and re-check the repositories | |
| Esc | Close the output pane, then clear the selection, then the filter | Back to the list |
| Q | Quit (Ctrl+C while an operation is running stops it first) | Back to the list |

Every action asks for confirmation first, then runs in the background with its progress bar, output, warnings
and errors in a pane at the bottom of the screen. The list stays on screen and you can keep browsing while it
runs. Updates end with one result line per module. When the action finishes, the list is rescanned and the
output stays in the pane until you close it (Esc or L). Only one action runs at a time. Nothing can answer a
prompt while an action runs, so anything that would prompt is asked up front: updating from an untrusted
repository says so in the confirmation. Modules marked `*` are loaded in the current session.

## How it works and safety

- **Fast scan.** ModuleManager reads `$env:PSModulePath` folders and manifests directly instead of calling
  `Get-Module -ListAvailable`. On a machine with about 800 module versions that takes about 1.5 s, against
  about 17 s for `Get-Module -ListAvailable`. The parsed results are cached per folder, so rescans are faster.
- **Parallel, cached gallery lookups.** Lookups run in a runspace pool, which works in both Windows PowerShell
  5.1 and PowerShell 7. About 220 modules take roughly 10 s. Results are cached for 30 minutes; use `-Refresh`
  to bypass the cache.
- **Scopes.** `CurrentUser` means under your profile. `AllUsers` means Program Files or `/usr/local/share`.
  `System` means it ships with PowerShell (`$PSHOME`) or Windows, and is hidden unless you use
  `-IncludeSystem`. `Other` is anything else.
- **Repositories.** Each module is checked against the repository it was installed from, read from
  `PSGetModuleInfo.xml`. Modules copied in by hand are checked against PSGallery.
- **Uninstalling is protected:**
  - `System` modules are never removed.
  - Loaded modules are skipped unless you use `-Force`.
  - Removing a version that another installed module depends on is blocked unless you use `-Force` (see
    below).
  - `AllUsers` changes require an elevated session.

### Dependencies (for example, the Az modules)

Dependencies are read from the package manager's install record (`PSGetModuleInfo.xml`), including the version
range each module needs. Modules copied in by hand fall back to `RequiredModules` and versioned `ModuleList`
entries in the manifest. This matters for families like Az: the `Az` rollup module pins an exact version of
every `Az.*` module, and the `Az.*` modules need a minimum version of `Az.Accounts`.

- **Removing.** `Uninstall-ManagedModule` refuses to remove a version that a module staying installed needs, and
  `Uninstall-OldModuleVersion` keeps such versions, with one warning (details with `-Verbose`). For example, old
  `Az.*` versions are kept while the `Az` version that pins them is installed. Remove them together with
  `Uninstall-OldModuleVersion Az, Az.*`.
- **Updating.** `Update-ManagedModule` updates dependencies first (`Az.Accounts`, then `Az.*`, then `Az`). If an
  update installs another module as a dependency, that module is skipped later in the same run, and `-PassThru`
  shows it with `UpdatedAsDependencyOf`. `-RemoveOldVersions` runs once at the end, so an old rollup and the
  versions it pins are removed together.
- **Loaded modules.** If a module loaded in your session (typically `Az.Accounts`) is older than the new versions
  need, you're warned before anything installs: a module can only be loaded once per session, so start a new
  session to use the updates.
- **Families in the UI.** `modman` shows a module and the `<Name>.*` modules it depends on as one collapsed row,
  such as `► Az (+92)` with the number of updates in the family. Space, U, X and O on a collapsed family act on
  all of it. Right expands it, Left collapses it, and G turns grouping off.

## Building and testing

The build uses [psake](https://github.com/psake/psake), [BuildHelpers](https://github.com/RamblingCookieMonster/BuildHelpers)
and [Pester](https://pester.dev). To install the build dependencies and run the tests:

```powershell
./Build/build.ps1 -ResolveDependency -TaskList 'Init'
./Build/build.ps1 -TaskList 'CombineFunctionsAndStage', 'Analyze', 'Test'
```

The unit tests build fake module trees in a temporary folder and point `PSModulePath` at them. They never
touch your real modules or the network.

See [CONTRIBUTING.md](CONTRIBUTING.md) for how releases are deployed.
