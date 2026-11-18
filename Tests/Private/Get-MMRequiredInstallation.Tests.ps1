BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-MMTestModule

    # A rollup (Roll) pinning exact versions of its members, like the Az module does.
    function New-TestInstall([string]$Name, [string]$Version, [string[]]$Dependency) {
        InModuleScope ModuleManager -Parameters @{ N = $Name; V = $Version; D = $Dependency } {
            [pscustomobject]@{
                Name          = $N
                Version       = $V
                ModuleVersion = [version]$V
                Prerelease    = $null
                ModuleBase    = "C:\fake\$N\$V"
                Dependencies  = @(foreach ($d in $D) { $n, $r = $d.Split('|'); New-MMDependency -Name $n -VersionRange $r })
            }
        }
    }
}

AfterAll {
    Remove-Module ModuleManager -Force -ErrorAction SilentlyContinue
}

Describe 'Get-MMRequiredInstallation' {

    BeforeEach {
        $core1 = New-TestInstall 'Roll.Core' '1.0.0'
        $core2 = New-TestInstall 'Roll.Core' '2.0.0'
        $core3 = New-TestInstall 'Roll.Core' '3.0.0'
        $extra = New-TestInstall 'Roll.Extra' '1.0.0' 'Roll.Core|[1.0.0, )'
        $roll1 = New-TestInstall 'Roll' '1.0.0' 'Roll.Core|[1.0.0]', 'Roll.Extra|[1.0.0]'
        $roll2 = New-TestInstall 'Roll' '2.0.0' 'Roll.Core|[2.0.0]', 'Roll.Extra|[1.0.0]'
        $all = @($core1, $core2, $core3, $extra, $roll1, $roll2)
    }

    It 'Keeps an exact version that a remaining module pins' {
        $kept = @(InModuleScope ModuleManager -Parameters @{ R = @($core1, $core2); A = $all } { Get-MMRequiredInstallation -Removing $R -AllInstallation $A })
        $kept.Installation.Version | Should -Be @('1.0.0', '2.0.0')
        $kept[0].RequiredBy | Should -Be 'Roll 1.0.0 needs [1.0.0]'
    }

    It 'Allows removal when the dependent is removed too' {
        $kept = @(InModuleScope ModuleManager -Parameters @{ R = @($core1, $roll1); A = $all } { Get-MMRequiredInstallation -Removing $R -AllInstallation $A })
        $kept | Should -BeNullOrEmpty
    }

    It 'Allows removal when another remaining version satisfies a minimum version' {
        $kept = @(InModuleScope ModuleManager -Parameters @{ R = @($core1); A = @($core1, $core3, $extra) } { Get-MMRequiredInstallation -Removing $R -AllInstallation $A })
        $kept | Should -BeNullOrEmpty
    }

    It 'Keeps the newest matching version when every match is being removed' {
        $kept = @(InModuleScope ModuleManager -Parameters @{ R = @($core1, $core2, $core3); A = @($core1, $core2, $core3, $extra) } {
                Get-MMRequiredInstallation -Removing $R -AllInstallation $A
            })
        $kept.Installation.Version | Should -Be '3.0.0'
    }

    It 'Protects the dependencies of a version it keeps' {
        # Removing Roll.Extra (needed by both rollups) and Roll.Core 3.0.0 (needed only by Roll.Extra).
        $kept = @(InModuleScope ModuleManager -Parameters @{ R = @($extra, $core1, $core2, $core3); A = @($core1, $core2, $core3, $extra) + @(New-TestInstall 'Other' '1.0.0' 'Roll.Extra|') } {
                Get-MMRequiredInstallation -Removing $R -AllInstallation $A
            })
        $kept.Installation.Name | Should -Be @('Roll.Extra', 'Roll.Core')
        $kept[1].Installation.Version | Should -Be '3.0.0'
    }

    It 'Ignores dependencies that were never satisfied' {
        $broken = New-TestInstall 'Broken' '1.0.0' 'Roll.Core|[9.0.0]'
        $kept = @(InModuleScope ModuleManager -Parameters @{ R = @($core3); A = @($core3, $broken) } { Get-MMRequiredInstallation -Removing $R -AllInstallation $A })
        $kept | Should -BeNullOrEmpty
    }
}
