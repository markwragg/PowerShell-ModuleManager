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

    It 'Should export only the public functions and the modman alias' {
        $exported = (Get-Module $Module).ExportedCommands.Keys | Sort-Object
        $exported | Should -Be @(
            'Get-ModuleInventory', 'Get-ModuleLocation', 'Get-ModuleUpdate', 'modman', 'Move-ManagedModule', 'Show-ModuleManager',
            'Uninstall-ManagedModule', 'Uninstall-OldModuleVersion', 'Update-ManagedModule'
        )
    }
}
