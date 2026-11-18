BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-MMTestModule

    function New-TestUpdate([string]$Name, [string[]]$Latest, [string[]]$Installed) {
        InModuleScope ModuleManager -Parameters @{ N = $Name; L = $Latest; I = $Installed } {
            [pscustomobject]@{
                Name               = $N
                LatestVersion      = '2.0.0'
                LatestDependencies = @(foreach ($d in $L) { New-MMDependency -Name $d })
                Dependencies       = @(foreach ($d in $I) { New-MMDependency -Name $d })
            }
        }
    }
}

AfterAll {
    Remove-Module ModuleManager -Force -ErrorAction SilentlyContinue
}

Describe 'Get-MMUpdateOrder' {

    It 'Puts dependencies before the modules that need them' {
        $updates = @(
            New-TestUpdate 'Az' -Latest 'Az.Accounts', 'Az.Compute', 'Az.Storage'
            New-TestUpdate 'Az.Accounts'
            New-TestUpdate 'Az.Compute' -Latest 'Az.Accounts'
            New-TestUpdate 'Az.Storage' -Installed 'Az.Accounts'
            New-TestUpdate 'Pester'
        )
        $order = InModuleScope ModuleManager -Parameters @{ U = $updates } { Get-MMUpdateOrder -Update $U }
        $order.Name | Should -Be @('Az.Accounts', 'Az.Compute', 'Az.Storage', 'Az', 'Pester')
    }

    It 'Keeps the original order when there are no dependencies between them' {
        $updates = @((New-TestUpdate 'B'), (New-TestUpdate 'A' -Latest 'NotInTheList'), (New-TestUpdate 'C'))
        $order = InModuleScope ModuleManager -Parameters @{ U = $updates } { Get-MMUpdateOrder -Update $U }
        $order.Name | Should -Be @('B', 'A', 'C')
    }

    It 'Copes with dependency cycles' {
        $updates = @((New-TestUpdate 'A' -Latest 'B'), (New-TestUpdate 'B' -Latest 'A'))
        $order = InModuleScope ModuleManager -Parameters @{ U = $updates } { Get-MMUpdateOrder -Update $U }
        $order.Name | Should -Be @('B', 'A')
    }
}
