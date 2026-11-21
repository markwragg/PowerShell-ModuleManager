Describe "ModuleManager Module Tests PS$PSVersion" {

    BeforeAll {
        if (-not $PSScriptRoot) { $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent }

        $PSVersion = $PSVersionTable.PSVersion.Major
        $Root = "$PSScriptRoot\.."
        $Module = 'ModuleManager'

        Get-Module $Module | Remove-Module -Force
    }

    It "Should import $Module without errors" {
        { Import-Module (Join-Path $Root $Module) -Force -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Should export only the public functions and their aliases' {
        $exported = (Get-Module $Module).ExportedCommands.Keys | Sort-Object
        $exported | Should -Be @(
            'Get-ManagedModule', 'Get-ManagedModuleLocation', 'Get-ManagedModuleUpdate',
            'Get-ModuleInventory', 'Get-ModuleLocation', 'Get-ModuleUpdate', 'modman', 'Move-ManagedModule',
            'Show-ModuleManager', 'Uninstall-ManagedModule', 'Update-ManagedModule'
        )
    }

    It 'Keeps the old name <Alias> as an alias of <Command>' -ForEach @(
        @{ Alias = 'Get-ModuleInventory'; Command = 'Get-ManagedModule' }
        @{ Alias = 'Get-ModuleUpdate'; Command = 'Get-ManagedModuleUpdate' }
        @{ Alias = 'Get-ModuleLocation'; Command = 'Get-ManagedModuleLocation' }
        @{ Alias = 'modman'; Command = 'Show-ModuleManager' }
    ) {
        (Get-Command $Alias -Module $Module).ResolvedCommand.Name | Should -Be $Command
    }
}
