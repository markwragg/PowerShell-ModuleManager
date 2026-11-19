# Update-ManagedModule

## SYNOPSIS
Installs the latest version of one or more modules.

## SYNTAX

```
Update-ManagedModule [-Name] <String[]> [-Scope <String>] [-Repository <String>] [-IncludePrerelease]
 [-RemoveOldVersions] [-TrustRepository] [-PassThru] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
Checks each module against its repository (using cached results from
Get-ModuleUpdate where available) and installs the newest version alongside
the existing ones.
Modules that are already up to date are skipped.

By default the new version is installed into the same scope as the newest
version you already have.
Installing for AllUsers requires an elevated session.

Uses Microsoft.PowerShell.PSResourceGet when available, otherwise PowerShellGet.

Dependencies:
  - The package manager installs any dependencies the new version needs.
  - When several modules are updated together, modules are updated after the modules
    they depend on (for example Az.Accounts, then the Az.* modules, then Az).
  - A module that an earlier update in the same run already installed as a dependency
    is skipped.
-Verbose and -PassThru show which module each one came with.
  - If a module loaded in this session is older than a new version needs (for example
    Az.Accounts), you're warned before anything is installed, because the new version
    can't be used until you start a new session.
  - -RemoveOldVersions runs once at the end, for every module that was updated
    (including dependencies), and keeps any old version another installed module still
    depends on.

## EXAMPLES

### EXAMPLE 1
```
Update-ManagedModule Pester
```

Installs the latest version of Pester alongside the existing versions, in the same scope.

### EXAMPLE 2
```
Get-ModuleUpdate -Outdated | Update-ManagedModule -RemoveOldVersions
```

Updates every module that has a newer version available, then removes the old versions.

### EXAMPLE 3
```
Update-ManagedModule * -WhatIf
```

Shows what would be updated without installing anything.

## PARAMETERS

### -Name
One or more module names.
Wildcards are supported.
Accepts pipeline input from
Get-ModuleInventory and Get-ModuleUpdate.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
Accept wildcard characters: True
```

### -Scope
Install the new version into this scope instead of the existing one.

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

### -Repository
Install from this repository instead of the one the module came from.

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

### -IncludePrerelease
Allow updating to a prerelease version.

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

### -RemoveOldVersions
After updating, uninstall the older versions of the updated modules (and of any
dependencies installed with them), except versions other installed modules depend on.

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

### -TrustRepository
Don't prompt when installing from an untrusted repository.

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
Output the inventory entry of each updated module.
Modules installed as a dependency of
another update have an UpdatedAsDependencyOf property naming that module.

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

### ModuleManager.ModuleInfo
## NOTES

## RELATED LINKS
