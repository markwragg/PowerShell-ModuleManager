# Get-ModuleUpdate

## SYNOPSIS
Compares the installed version of each module with the latest version in its repository.

## SYNTAX

```
Get-ModuleUpdate [[-Name] <String[]>] [-Scope <String[]>] [-Repository <String>] [-IncludePrerelease]
 [-Outdated] [-Refresh] [-IncludeSystem] [-ThrottleLimit <Int32>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
For every installed module, looks up the newest version available in the repository
it was installed from (or PSGallery for modules installed manually) and reports
whether an update is available.

Lookups run in parallel and are cached for 30 minutes, so running this again, or
running Update-ManagedModule afterwards, doesn't query the repository again.
Use
-Refresh to bypass the cache.

Status values:
  UpdateAvailable  A newer version exists in the repository.
  UpToDate         The newest installed version matches the repository.
  LocalNewer       The installed version is newer than the repository version.
  NotInRepository  The module was not found in the repository.
  Unlisted         The module is in the repository but its publisher has unlisted it
                   (usually because it is deprecated), so it can't be updated.
  VersionUnlisted  The module is listed, but its publisher has unlisted the newest
                   installed version and there's no newer one to update to.
Only
                   checked for NuGet v2 feeds, such as the PowerShell Gallery.
  Error            The repository could not be queried.

## EXAMPLES

### EXAMPLE 1
```
Get-ModuleUpdate -Outdated
```

Lists only the installed modules that have a newer version available in their repository.

### EXAMPLE 2
```
Get-ModuleUpdate Pester, PSReadLine
```

Compares the installed versions of Pester and PSReadLine with the latest available.

### EXAMPLE 3
```
Get-ModuleUpdate -Outdated | Update-ManagedModule -WhatIf
```

Shows which updates would be installed, without installing anything.

## PARAMETERS

### -Name
One or more module names.
Wildcards are supported.
Accepts pipeline input from
Get-ModuleInventory.

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
Only check modules installed in these scopes.

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

### -Repository
Query this repository for every module instead of the one each was installed from.

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
Consider prerelease versions when finding the latest version.
Modules whose newest
installed version is a prerelease always consider prereleases.

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

### -Outdated
Only return modules with an update available.

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

### -Refresh
Ignore cached results and query the repository again.

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
Queries made with PowerShellGet's own commands (for a repository that isn't a NuGet v2 feed, or a feed that can't be reached) still run one at a time.

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

### ModuleManager.ModuleUpdate
## NOTES

## RELATED LINKS
