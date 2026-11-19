# Show-ModuleManager

## SYNOPSIS
Opens an interactive terminal UI for browsing, updating and uninstalling modules.

## SYNTAX

```
Show-ModuleManager [[-Name] <String[]>] [-Scope <String[]>] [-IncludeSystem] [-IncludePrerelease]
 [-Repository <String>] [-NoUpdateCheck] [-ThrottleLimit <Int32>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Shows every installed module with its installed version, the latest version in its
repository, how many versions are installed and where.
The update check runs in the
background, so you can use the list straight away.

Keys (module list):
  Up/Down, PgUp/PgDn, Home/End   Move
  Space                          Select / deselect module (a collapsed family: all of it)
  A                              Select every module with an update (press again to clear)
  Right                          Expand a module family, or show versions and paths
  Left                           Collapse the module family
  Enter                          Show installed versions and paths
  U                              Update selected modules (or the current one)
  X or Delete                    Uninstall everything selected: modules (all versions) and
                                 versions selected in the details view
  O                              Remove old versions, keeping the newest
  L                              Show or hide the output pane
  \[ and \]                        Scroll the output pane back and forward
  /                              Filter by name or description
  V                              Cycle view: All, Updates, Multiple versions, Loaded
  S                              Cycle sort: Name, Status, Versions, Scope
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
  U                              Update this module
  Esc, Left or Backspace         Back to the list

Modules marked with * are loaded in the current session.
When you uninstall or remove old
versions and some of them are loaded, the confirmation offers y (leave the loaded versions
installed) or f (unload them from the session first, so they're removed too).
Modules that
use .NET assemblies, ModuleManager itself and the package manager can't be unloaded safely,
so they're skipped with the reason; remove them from a new session.

Updates, uninstalls and removing old versions run in the background, with their progress
and output in a pane at the bottom of the screen, so the list stays on screen and you can
keep browsing.
Only one operation runs at a time.
When it finishes the list is rescanned
and the output stays in the pane until you close it (Esc or L).
Nothing can answer a
prompt while an operation runs, so you're asked beforehand: for example, updating from
an untrusted repository says so in the confirmation.

Module families: a module that depends on two or more installed modules named after it
(Az and the Az.* modules, or Microsoft.Graph and Microsoft.Graph.*) is shown as one
collapsed row, with the number of family members and how many have updates.
U, X, O
and Space on a collapsed family act on the whole family; expand it to act on one member.
A view or filter shows the matching members under their family.

## EXAMPLES

### EXAMPLE 1
```
Show-ModuleManager
```

Opens the terminal UI listing all installed modules, and checks for updates in the background.

### EXAMPLE 2
```
modman -Name Az.*
```

Opens the terminal UI (via its alias) showing only the Az modules.

## PARAMETERS

### -Name
Only show modules matching these names.
Wildcards are supported.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: *
Accept pipeline input: False
Accept wildcard characters: True
```

### -Scope
Only show modules in these scopes.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -IncludeSystem
Include modules that ship with PowerShell or Windows.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -IncludePrerelease
Consider prerelease versions when checking for updates.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Repository
Check this repository instead of the one each module was installed from.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -NoUpdateCheck
Don't check repositories when the UI opens.
Press R to check later.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ThrottleLimit
The maximum number of concurrent repository queries.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 16
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
{{Fill ProgressAction Description}}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable.
For more information, see about_CommonParameters (http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

## RELATED LINKS
