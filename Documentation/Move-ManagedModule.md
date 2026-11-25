# Move-ManagedModule

## SYNOPSIS
Moves modules, or specific versions of modules, between the CurrentUser and AllUsers scopes.

## SYNTAX

### ByModuleBase (Default)
```
Move-ManagedModule -ModuleBase <String[]> -Destination <String> [-Force] [-PassThru]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### ByName
```
Move-ManagedModule [-Name] <String[]> [-Version <String[]>] [-Scope <String[]>] -Destination <String> [-Force]
 [-PassThru] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Moves installed module versions to the module folder of another scope.
Each version
keeps its folder layout, and the location in its install record (PSGetModuleInfo.xml) is
updated, so PowerShellGet and PSResourceGet still recognise it.

On Windows, a version stays with its edition's modules: one in a WindowsPowerShell\Modules
folder moves to the other WindowsPowerShell\Modules folder (Documents or Program Files),
and one in a PowerShell\Modules folder to the other PowerShell\Modules folder.
This keeps
it where the edition it was installed for looks.
For example, from PowerShell 7, a module
in Program Files\WindowsPowerShell\Modules (which both editions use) moved to CurrentUser
goes to Documents\WindowsPowerShell\Modules.
PowerShell 7 doesn't look there by default
(only when it's started from Windows PowerShell), so a warning says when the session
can't see where a version went.
Other versions move to the first PSModulePath entry for
the scope.

Each version is copied, so it takes the permissions of the destination folder, and the
original is removed only once the copy is complete.
If the copy fails, the original is
left as it was.

Safety checks:
  - Modules that ship with PowerShell or Windows are never moved.
  - Versions already installed for the destination scope are skipped.
  - Versions that already exist at the destination are not overwritten.
  - Loaded modules are skipped unless -Force is used, which unloads them first.
  - Moving to or from AllUsers requires an elevated session.
  - Moving to CurrentUser a version that a module installed for all users depends on
    warns that other users will no longer have it.

## EXAMPLES

### EXAMPLE 1
```
Move-ManagedModule Pester -Destination AllUsers
```

Moves every version of Pester installed for the current user to the all users module folder.

### EXAMPLE 2
```
Get-ManagedModuleLocation -Scope AllUsers | Move-ManagedModule -Destination CurrentUser -WhatIf
```

Shows which all-users module versions would be moved to the current user's module folder,
without moving anything.

### EXAMPLE 3
```
Move-ManagedModule Az.* -Version 14.* -Destination AllUsers -PassThru
```

Moves the Az 14.x versions to the all users module folder and lists where they are now.

## PARAMETERS

### -Name
The module name(s) to move.
Wildcards are supported.
All versions are moved unless
-Version is given.

Different modules can share a name (see Get-ManagedModule).
A name (not a wildcard
pattern) that matches versions of more than one of them is an error, and nothing of
that name is moved: use -Scope or -Version to choose, or pipe the versions to move from
Get-ManagedModule -AllVersions.
Versions that ship with PowerShell or Windows don't
count, as they're never moved.

```yaml
Type: String[]
Parameter Sets: ByName
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName)
Accept wildcard characters: True
```

### -Version
Only move these versions (for example '1.2.0' or '2.0.0-beta1').
Wildcards are supported.

```yaml
Type: String[]
Parameter Sets: ByName
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: True
```

### -Scope
Only move versions installed in these scopes.

```yaml
Type: String[]
Parameter Sets: ByName
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ModuleBase
The folder of a specific installed version.
Bound automatically when you pipe output
from Get-ManagedModuleLocation or Get-ManagedModule -AllVersions.

```yaml
Type: String[]
Parameter Sets: ByModuleBase
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: True (ByPropertyName)
Accept wildcard characters: False
```

### -Destination
The scope to move to: CurrentUser or AllUsers.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Force
Move modules even if they are loaded, unloading them from the session first.

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

### -PassThru
Output the moved versions, at their new locations.

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

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
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

### ModuleManager.InstalledVersion
## NOTES

## RELATED LINKS
