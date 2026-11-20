# Show-ModuleManager

## SYNOPSIS
Opens an interactive terminal UI for browsing, updating and uninstalling modules.

## SYNTAX

### Local (Default)
```
Show-ModuleManager [[-Name] <String[]>] [-Scope <String[]>] [-IncludeSystem] [-IncludePrerelease]
 [-Repository <String>] [-NoUpdateCheck] [-ThrottleLimit <Int32>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

### ComputerName
```
Show-ModuleManager [[-Name] <String[]>] [-Scope <String[]>] [-IncludeSystem] [-IncludePrerelease]
 [-Repository <String>] [-NoUpdateCheck] [-ThrottleLimit <Int32>] -ComputerName <String>
 [-Credential <PSCredential>] [-ConfigurationName <String>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

### Session
```
Show-ModuleManager [[-Name] <String[]>] [-Scope <String[]>] [-IncludeSystem] [-IncludePrerelease]
 [-Repository <String>] [-NoUpdateCheck] [-ThrottleLimit <Int32>] -Session <PSSession>
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### Edition
```
Show-ModuleManager [[-Name] <String[]>] [-Scope <String[]>] [-IncludeSystem] [-IncludePrerelease]
 [-Repository <String>] [-NoUpdateCheck] [-ThrottleLimit <Int32>] -Edition <String>
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
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
  M                              Move selected modules (or the current one) to the other
                                 scope: CurrentUser or AllUsers
  L                            Show or hide the output pane
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

On Windows, actions that need administrator rights (moving modules, and updating,
uninstalling or removing old versions of modules installed for all users) run as
administrator when this session isn't: the confirmation says so, Windows asks for
permission, and the action runs in a hidden elevated PowerShell process while the UI stays
as it is.
Choosing No at the Windows prompt changes nothing.

If the update check fails because PowerShellGet needs the NuGet package provider (Windows
PowerShell's built-in PowerShellGet 1.0 does), you're offered to install it for the current
user, after which the check runs again.

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

### EXAMPLE 3
```
modman -ComputerName Server01
```

Manages the modules installed on Server01, from this console.

### EXAMPLE 4
```
modman -ComputerName Server01 -ConfigurationName PowerShell.7 -Credential (Get-Credential)
```

Manages the PowerShell 7 modules on Server01, connecting as another user.

### EXAMPLE 5
```
$s = New-PSSession -HostName linux01 -UserName admin
Show-ModuleManager -Session $s
```

Manages the modules on linux01, connecting over SSH.

### EXAMPLE 6
```
modman -Edition Desktop
```

From PowerShell 7, manages the modules Windows PowerShell 5.1 uses on this computer.

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

### -ComputerName
Manage the modules on this computer instead, over PowerShell remoting.
The UI runs here;
scanning, repository checks, updates and uninstalls run on that computer, as the user you
connect as.
ModuleManager doesn't need to be installed there: it's sent for the session.

```yaml
Type: String
Parameter Sets: ComputerName
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Credential
The credentials to connect to -ComputerName with.

```yaml
Type: PSCredential
Parameter Sets: ComputerName
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ConfigurationName
The session configuration (endpoint) to connect to on -ComputerName.
By default that's
Microsoft.PowerShell, which is Windows PowerShell; use PowerShell.7 (registered by running
Enable-PSRemoting in PowerShell 7) to manage the PowerShell 7 modules there.

```yaml
Type: String
Parameter Sets: ComputerName
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Session
Manage the modules on the computer this PSSession is connected to (any transport, such as
WinRM or SSH).
The session itself is left as it is: ModuleManager opens its own connection
using the same connection details, and closes it when you quit.

```yaml
Type: PSSession
Parameter Sets: Session
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Edition
Manage the modules of the other PowerShell edition on this computer: Desktop for Windows
PowerShell 5.1 (from PowerShell 7), or Core for PowerShell 7 (from Windows PowerShell).
The
editions install modules into different folders and use their own package manager defaults,
so scanning, repository checks, updates and uninstalls run in a hidden process of that
edition, which closes when you quit.
Windows only.
Naming the edition this is runs it here,
as without -Edition.

```yaml
Type: String
Parameter Sets: Edition
Aliases:

Required: True
Position: Named
Default value: None
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
