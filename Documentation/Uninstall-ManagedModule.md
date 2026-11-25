# Uninstall-ManagedModule

## SYNOPSIS
Uninstalls modules, specific versions of modules, or the old versions of modules.

## SYNTAX

### ByModuleBase (Default)
```
Uninstall-ManagedModule -ModuleBase <String[]> [-Force] [-PassThru] [-ProgressAction <ActionPreference>]
 [-WhatIf] [-Confirm] [<CommonParameters>]
```

### OldVersions
```
Uninstall-ManagedModule [[-Name] <String[]>] [-OldVersions] [-Keep <Int32>] [-Scope <String[]>] [-Force]
 [-PassThru] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

### ByName
```
Uninstall-ManagedModule [-Name] <String[]> [-Version <String[]>] [-Scope <String[]>] [-Force] [-PassThru]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Removes installed module versions from disk, whether they were installed by
PowerShellGet, PSResourceGet or copied in by hand.

With -OldVersions, removes all but the newest -Keep versions of each module instead.
Updating a module installs the new version alongside the old one, so versions build up
over time.
Loaded versions, and old versions that another installed module depends on,
are skipped with a warning (unless -Force is used) rather than as errors.
For example,
each Az rollup version pins exact versions of the Az.* modules, so those are kept while
that Az version is installed.

Safety checks:
  - Modules that ship with PowerShell or Windows are never removed.
  - Loaded modules are skipped unless -Force is used.
  - Removing a version that another installed module depends on is blocked unless
    -Force is used.
Dependencies are read from the package manager's install record
    (PSGetModuleInfo.xml), or the manifest for modules copied in by hand, and are
    checked against the version range each module needs.
For example, the Az rollup
    module pins exact versions of each Az.* module.
  - AllUsers installs require an elevated session.

Prompts for confirmation for each version by default.
Use -Confirm:$false to skip
prompts, or -WhatIf to preview.

Each version's size is shown in its confirmation prompt (and -WhatIf line).
When it's done,
it says how many versions it removed and how much disk space that freed, or with -WhatIf,
how much it would free.
This is an information message, so -InformationAction
SilentlyContinue (or 6\>$null) hides it without hiding warnings.

## EXAMPLES

### EXAMPLE 1
```
Uninstall-ManagedModule OldModule
```

Removes every installed version of OldModule.

### EXAMPLE 2
```
Uninstall-ManagedModule Pester -Version 4.*
```

Removes only the Pester 4.x versions, keeping any others.

### EXAMPLE 3
```
Get-ManagedModuleLocation Az.* -Scope AllUsers | Uninstall-ManagedModule -WhatIf
```

Shows which all-users Az module versions would be removed, without removing anything.

### EXAMPLE 4
```
Uninstall-ManagedModule -OldVersions -WhatIf
```

Previews which old versions of every module would be removed.

### EXAMPLE 5
```
Uninstall-ManagedModule Pester -OldVersions -Keep 2 -Confirm:$false
```

Keeps the two newest versions of Pester and removes the rest, without prompting.

### EXAMPLE 6
```
Uninstall-ManagedModule -OldVersions -Confirm:$false -PassThru | Measure-Object SizeMB -Sum
```

Removes the old versions of every module, and totals the space freed from the versions output.

## PARAMETERS

### -Name
The module name(s) to uninstall.
Wildcards are supported.
All versions are removed
unless -Version or -OldVersions is given.
With -OldVersions it defaults to all modules,
and accepts names from the pipeline.

Different modules can share a name (see Get-ManagedModule).
Without -OldVersions, a name
(not a wildcard pattern) that matches versions of more than one of them is an error,
and nothing of that name is removed: use -Scope or -Version to choose, or pipe the
versions to remove from Get-ManagedModule -AllVersions.
Versions that ship with
PowerShell or Windows don't count, as they're never removed.

```yaml
Type: String[]
Parameter Sets: OldVersions
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
Accept wildcard characters: True
```

```yaml
Type: String[]
Parameter Sets: ByName
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
Accept wildcard characters: True
```

### -Version
Only remove these versions (for example '1.2.0' or '2.0.0-beta1').
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

### -OldVersions
Remove the old versions of each module, keeping the newest (or the newest -Keep).

```yaml
Type: SwitchParameter
Parameter Sets: OldVersions
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Keep
With -OldVersions, how many of the newest versions to keep.
Defaults to 1.

```yaml
Type: Int32
Parameter Sets: OldVersions
Aliases:

Required: False
Position: Named
Default value: 1
Accept pipeline input: False
Accept wildcard characters: False
```

### -Scope
Only remove versions installed in these scopes.
With -OldVersions, all scopes are still
counted when working out which versions are newest.

```yaml
Type: String[]
Parameter Sets: OldVersions, ByName
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

### -Force
Remove modules even if they are loaded, or required by other installed modules.

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
Output an object for each version that was removed, with its size in MB (SizeMB).

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
