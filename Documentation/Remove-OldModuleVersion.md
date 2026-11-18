# Remove-OldModuleVersion

## SYNOPSIS
Removes older versions of modules, keeping only the newest.

## SYNTAX

```
Remove-OldModuleVersion [[-Name] <String[]>] [-Keep <Int32>] [-Scope <String[]>] [-Force] [-PassThru]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Updating a module installs the new version alongside the old one, so versions
build up over time.
This removes all but the newest -Keep versions of each module.

Versions that ship with PowerShell or Windows are never removed.
Versions loaded in
the current session, and old versions that another installed module depends on, are
kept unless -Force is used.
For example, each Az rollup version pins exact versions of
the Az.* modules, so those are kept while that Az version is installed.
Prompts for
confirmation by default.

## EXAMPLES

### EXAMPLE 1
```
Remove-OldModuleVersion -WhatIf
```

Previews which old versions would be removed.

### EXAMPLE 2
```
Remove-OldModuleVersion Pester -Keep 2 -Confirm:$false
```

Keeps the two newest versions of Pester and removes the rest, without prompting.

## PARAMETERS

### -Name
One or more module names.
Wildcards are supported.
Defaults to all modules.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: *
Accept pipeline input: True (ByPropertyName, ByValue)
Accept wildcard characters: True
```

### -Keep
How many of the newest versions to keep.
Defaults to 1.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 1
Accept pipeline input: False
Accept wildcard characters: False
```

### -Scope
Only remove versions installed in these scopes.
All scopes are still counted when
working out which versions are newest.

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

### -Force
Remove versions even if they are loaded in the current session, or other installed
modules depend on them.

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
Output an object for each version that was removed.

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
{{ Fill ProgressAction Description }}

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
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### ModuleManager.InstalledVersion
## NOTES

## RELATED LINKS
