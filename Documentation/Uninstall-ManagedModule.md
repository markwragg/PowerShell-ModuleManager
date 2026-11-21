# Uninstall-ManagedModule

## SYNOPSIS
Uninstalls modules, or specific versions of modules.

## SYNTAX

### ByModuleBase (Default)
```
Uninstall-ManagedModule -ModuleBase <String[]> [-Force] [-ProgressAction <ActionPreference>] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

### ByName
```
Uninstall-ManagedModule [-Name] <String[]> [-Version <String[]>] [-Scope <String[]>] [-Force]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Removes installed module versions from disk, whether they were installed by
PowerShellGet, PSResourceGet or copied in by hand.

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

## PARAMETERS

### -Name
The module name(s) to uninstall.
Wildcards are supported.
All versions are removed
unless -Version is given.

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

### -Scope
Only remove versions installed in these scopes.

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

## NOTES

## RELATED LINKS
