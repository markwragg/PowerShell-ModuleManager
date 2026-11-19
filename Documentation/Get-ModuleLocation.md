# Get-ModuleLocation

## SYNOPSIS
Shows where modules are installed on disk.

## SYNTAX

```
Get-ModuleLocation [[-Name] <String[]>] [-Scope <String[]>] [-Summary] [-IncludeSize] [-IncludeSystem]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
By default returns one object per installed module version, with its scope, the
folder it lives in and the PSModulePath entry that contains it.

With -Summary, returns one object per PSModulePath entry in search order, with
the number of modules and versions in each.
Use -IncludeSize to add disk usage.

## EXAMPLES

### EXAMPLE 1
```
Get-ModuleLocation Pester
```

Lists every installed Pester version and where it is.

### EXAMPLE 2
```
Get-ModuleLocation -Summary -IncludeSize
```

Shows how many modules and versions are in each PSModulePath location, and the disk space they use.

### EXAMPLE 3
```
Get-ModuleInventory | Where-Object { ($_.Installations.ModuleRoot | Select-Object -Unique).Count -gt 1 }
```

Finds modules installed in more than one PSModulePath location.

## PARAMETERS

### -Name
One or more module names.
Wildcards are supported.

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

### -Scope
Only include these scopes: CurrentUser, AllUsers, System, Other.

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

### -Summary
Summarise by PSModulePath entry instead of listing each module version.

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

### -IncludeSize
Calculate the size on disk of each module version (or each path, with -Summary).
This reads every file, so it can be slow.

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

### -IncludeSystem
Include modules that ship with PowerShell or Windows.
-Summary always includes them.

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
### ModuleManager.ModuleRoot
## NOTES

## RELATED LINKS
