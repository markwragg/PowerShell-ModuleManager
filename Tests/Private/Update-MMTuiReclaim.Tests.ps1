BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment

    function Add-Blob([string]$Root, [string]$Name, [string]$Version, [int]$KB) {
        $path = Join-Path (Join-Path (Join-Path $Root $Name) $Version) 'blob.bin'
        [IO.File]::WriteAllBytes($path, [byte[]]::new($KB * 1KB))
    }
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'The Frees column of the Multiple versions view' {

    BeforeEach {
        Reset-FakeModules
        Add-FakeFamily
        # Temp folders may not be classified as CurrentUser on every OS; make removals allowed.
        Mock -ModuleName ModuleManager Get-MMScope { 'CurrentUser' }
        Add-Blob $script:UserRoot 'MMAlpha' '1.0.0' 1024
        Add-Blob $script:OtherRoot 'MMAlpha' '0.9' 512
        Add-Blob $script:UserRoot 'MMRoll' '1.0.0' 1024        # old, and nothing needs it
        Add-Blob $script:UserRoot 'MMRoll.Core' '1.0.0' 1024   # freed once MMRoll 1.0.0 goes
        Add-Blob $script:UserRoot 'MMRoll.Core' '2.0.0' 1024   # MMRoll 2.0.0 pins it
    }

    AfterAll { Reset-FakeModules }

    It 'Shows ... until the sizes are known, then how much removing old versions would free (<Group>)' -ForEach @(
        @{ Group = 'grouped'; Grouped = $true }
        @{ Group = 'ungrouped'; Grouped = $false }
    ) {
        InModuleScope ModuleManager -Parameters ($_ + @{ Options = $TuiOptions }) {
            function Get-Plain($s) { @(((Get-MMTuiFrame $s 120 16) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", '') -split "`r`n") }
            function Get-Frees($lines, $name) {
                # The cell is right-aligned under the Frees header, 9 characters wide.
                $end = $lines[1].IndexOf('Frees') + 'Frees'.Length
                $line = $lines | Where-Object { $_ -match "\b$([regex]::Escape($name))\s{2,}" } | Select-Object -First 1
                $line.Substring($end - 9, 9).Trim()
            }
            $s = New-MMTuiState -Options $Options
            $s.Group = $Grouped
            Update-MMTuiRows $s
            $s.View = $s.Views.IndexOf('Multiple versions')
            Update-MMTuiVisible $s

            $before = Get-Plain $s
            $before | ForEach-Object { $_.Length | Should -Be 120 }
            $before[1] | Should -Match '#\s+Frees\s+Scope'
            Get-Frees $before 'MMAlpha' | Should -Be '...'

            $calls = 0
            while (Update-MMTuiReclaim $s) { $calls++; if ($calls -gt 20) { throw 'Update-MMTuiReclaim never finished' } }
            $s.ReclaimDone | Should -BeTrue
            $after = Get-Plain $s
            $after | ForEach-Object { $_.Length | Should -Be 120 }
            Get-Frees $after 'MMAlpha' | Should -Be '1.5 MB'
            Get-Frees $after 'MMRoll' | Should -Be '1.0 MB'
            Get-Frees $after 'MMRoll.Core' | Should -Be '1.0 MB'
        }
    }

    It 'Matches what Get-ManagedModule -IncludeSize reports' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s
            $s.View = $s.Views.IndexOf('Multiple versions')
            Update-MMTuiVisible $s
            [void](Get-MMTuiFrame $s 120 16)
            while (Update-MMTuiReclaim $s) { }
            $tuiBytes = 0L
            foreach ($base in $s.Reclaim.Keys) { $tuiBytes += [long]$s.Sizes[$base] }
            $cmdletMB = (Get-ManagedModule -IncludeSize | Measure-Object ReclaimableMB -Sum).Sum
            [Math]::Round($tuiBytes / 1MB, 1) | Should -Be $cmdletMB
        }
    }

    It 'Sizes a little at a time, the rows in view first' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            $s.Group = $false
            Update-MMTuiRows $s
            $s.View = $s.Views.IndexOf('Multiple versions')
            Update-MMTuiVisible $s
            # Only the first row (MMAlpha) is in view.
            $s.Top = 0; $s.ListHeight = 1
            Update-MMTuiReclaim $s -BudgetMs 0 | Should -BeTrue    # works out which versions, and sizes one
            Update-MMTuiReclaim $s -BudgetMs 0 | Should -BeTrue
            Update-MMTuiReclaim $s -BudgetMs 0 | Should -BeTrue
            $sized = @($s.Reclaim.Keys | Where-Object { $s.Sizes.ContainsKey($_) })
            $sized | Should -HaveCount 3
            $sized | ForEach-Object { $_ | Should -Match 'MMAlpha' }
            $s.ReclaimDone | Should -BeFalse
        }
    }

    It 'Does nothing outside the Multiple versions view, or once every size is known, until the next scan' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s
            Update-MMTuiVisible $s
            Update-MMTuiReclaim $s | Should -BeFalse
            $s.Reclaim | Should -BeNullOrEmpty
            $plain = @(((Get-MMTuiFrame $s 120 16) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", '') -split "`r`n")
            $plain[1] | Should -Not -Match 'Frees'

            $s.View = $s.Views.IndexOf('Multiple versions')
            Update-MMTuiVisible $s
            while (Update-MMTuiReclaim $s) { }
            Mock Get-MMFolderSize { throw 'should not be called' }
            Update-MMTuiReclaim $s | Should -BeFalse

            Update-MMTuiRows $s
            $s.Reclaim | Should -BeNullOrEmpty
            $s.ReclaimDone | Should -BeFalse
        }
    }

    It 'Leaves the cell blank when none of the old versions would be removed' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            $s.Group = $false
            Update-MMTuiRows $s
            $s.View = $s.Views.IndexOf('Multiple versions')
            Update-MMTuiVisible $s
            Mock Get-MMOldVersion { [pscustomobject]@{ Removable = @(); System = @(); Loaded = @(); Required = @() } }
            Update-MMTuiReclaim $s | Should -BeTrue
            $s.ReclaimDone | Should -BeTrue
            $plain = @(((Get-MMTuiFrame $s 120 16) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", '') -split "`r`n")
            $alpha = $plain | Where-Object { $_ -match 'MMAlpha' }
            $alpha | Should -Not -Match '\.\.\.|MB|KB'
        }
    }

    It 'Has no Frees column when the terminal is narrow' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s
            $s.View = $s.Views.IndexOf('Multiple versions')
            Update-MMTuiVisible $s
            $plain = @(((Get-MMTuiFrame $s 90 16) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", '') -split "`r`n")
            $plain | ForEach-Object { $_.Length | Should -Be 90 }
            $plain[1] | Should -Not -Match 'Frees'
        }
    }
}
