function Select-MMUnambiguousMatch {
    <#
    .SYNOPSIS
        Leaves out the versions matched by a module name that means more than one module.

    .DESCRIPTION
        Different modules can share a name (see Group-MMInstallation). When an exact name (not a
        wildcard pattern) matches versions of more than one of them that the command would act
        on, it's ambiguous: those versions are left out, and a message says which modules the
        name could mean and how to choose. Versions that ship with PowerShell or Windows aren't
        counted, as they're never removed or moved, so a module of the same name as one of them
        isn't ambiguous.

        Returns @{ Matched = the versions to act on; Messages = one per ambiguous name }.
    #>
    param(
        [AllowEmptyCollection()][object[]]$Matched,
        [AllowEmptyCollection()][object[]]$All,
        [string[]]$Name,
        # What the command does to the versions, for the message: 'remove' or 'move'.
        [string]$Action
    )

    $result = @{ Matched = @($Matched); Messages = @() }
    $messages = [System.Collections.Generic.List[string]]::new()
    $dropped = @{}
    foreach ($n in $Name) {
        if (-not $n -or [WildcardPattern]::ContainsWildcardCharacters($n)) { continue }
        $hits = @{}
        foreach ($m in $Matched) {
            if ($m.Name -eq $n -and $m.Scope -ne 'System') { $hits[(Get-MMPathKey $m.ModuleBase)] = $m }
        }
        if (-not $hits.Count) { continue }

        # Grouped with every installed version of the name, so each version joins the module it belongs to.
        $modules = @(Group-MMInstallation -Installation @($All | Where-Object { $_.Name -eq $n }))
        $described = @(foreach ($module in $modules) {
                $mine = @($module.Installations | Where-Object { $hits.ContainsKey((Get-MMPathKey $_.ModuleBase)) })
                if (-not $mine) { continue }
                $scopes = @($mine | ForEach-Object { $_.Scope } | Select-Object -Unique) -join ', '
                $source = 'copied in by hand'
                if ($module.Repository) { $source = "from $($module.Repository)" }
                "$($module.Name) $(@($mine | ForEach-Object { $_.Version }) -join ', ') ($scopes, $source)"
            })
        if ($described.Count -lt 2) { continue }

        foreach ($k in $hits.Keys) { $dropped[$k] = $true }
        $list = (@($described | Select-Object -SkipLast 1) -join ', ') + " and $($described[-1])"
        $messages.Add("'$n' matches $($described.Count) different modules with that name: $list. Use -Scope or -Version to choose, or pipe the versions to $Action from Get-ManagedModule $n -AllVersions.")
    }
    if ($dropped.Count) {
        $result.Matched = @($Matched | Where-Object { -not $dropped.ContainsKey((Get-MMPathKey $_.ModuleBase)) })
    }
    $result.Messages = $messages.ToArray()
    $result
}
