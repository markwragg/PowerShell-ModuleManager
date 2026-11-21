# Get-ManagedModule

## SYNOPSIS
Lists the PowerShell modules installed on this machine, one row per module.

## SYNTAX

```
Get-ManagedModule [[-Name] <String[]>] [-Scope <String[]>] [-IncludeSystem] [-MultipleVersions]
 [-AllVersions] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Scans every folder on $env:PSModulePath and summarises each module: the newest
installed version, every other installed version, the scope it is installed in,
the repository it came from and whether it is loaded in the current session.

The scan reads folders and manifests directly, so it is much faster than
Get-Module -ListAvailable.

Modules that ship with PowerShell or Windows (scope 'System') are hidden unless
-IncludeSystem or -Scope System is used.

## EXAMPLES

### EXAMPLE 1
```
Get-ManagedModule
```

Lists all user-installed modules.

### EXAMPLE 2
```
Get-ManagedModule -MultipleVersions | Sort-Object VersionCount -Descending
```

Shows which modules have accumulated the most old versions.

### EXAMPLE 3
```
Get-ManagedModule Az.* -AllVersions
```

Lists every installed version of the Az modules, one row per version.

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
Only include installations in these scopes: CurrentUser, AllUsers, System, Other.

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

### -MultipleVersions
Only return modules that have more than one version installed.

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

### -AllVersions
Return one object per installed version instead of one per module.

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

### ModuleManager.ModuleInfo
### ModuleManager.InstalledVersion
## NOTES

## RELATED LINKS
