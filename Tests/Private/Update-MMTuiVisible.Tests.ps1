BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Update-MMTuiVisible' {

    It 'Builds rows, filters, sorts and views without error' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s
            Update-MMTuiVisible $s
            $s.Visible.Count | Should -Be 4
            $s.Filter = 'gam'; Update-MMTuiVisible $s
            $s.Visible.Name | Should -Be 'MMGamma'
            $s.Filter = ''; $s.View = 2; Update-MMTuiVisible $s
            $s.Visible.Name | Should -Be 'MMAlpha'
            foreach ($i in 0..3) { $s.Sort = $i; $s.View = 0; Update-MMTuiVisible $s; $s.Visible.Count | Should -Be 4 }
        }
    }

    Context 'Module families' {

        BeforeAll {
            Reset-FakeModules
            Add-FakeFamily
        }

        It 'Groups a family under its parent, collapsed until expanded' {
            InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
                $s = New-MMTuiState -Options $Options
                Update-MMTuiRows $s
                Update-MMTuiVisible $s
                $roll = $s.Rows | Where-Object Name -EQ 'MMRoll'
                $roll.Children.Name | Should -Be @('MMRoll.Core', 'MMRoll.Extra')
                $s.Visible.Name | Should -Not -Contain 'MMRoll.Core'
                $s.Visible.Count | Should -Be 5

                # Actions on the collapsed parent cover the whole family
                Set-MMTuiCursor $s ([array]::IndexOf(@($s.Visible.Name), 'MMRoll'))
                (Get-MMTuiTarget $s).Name | Should -Be @('MMRoll', 'MMRoll.Core', 'MMRoll.Extra')
                Invoke-MMTuiKey $s ([ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false))
                @($s.Rows | Where-Object Selected).Count | Should -Be 3
                foreach ($r in $s.Rows) { $r.Selected = $false }

                # Right expands; members are listed under the parent and act on their own
                Invoke-MMTuiKey $s ([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::RightArrow, $false, $false, $false))
                Update-MMTuiVisible $s
                $s.Mode | Should -Be 'list'
                $i = [array]::IndexOf(@($s.Visible.Name), 'MMRoll')
                $s.Visible[$i + 1].Name | Should -Be 'MMRoll.Core'
                $s.Visible[$i + 2].Last | Should -BeTrue
                (Get-MMTuiTarget $s).Name | Should -Be 'MMRoll'
                $frame = Get-MMTuiFrame $s 100 12
                $frame | Should -Match ([regex]::Escape("$($script:MMGlyph.LastBranch) MMRoll.Extra"))

                # Left on a member collapses the family and moves to the parent
                Set-MMTuiCursor $s ($i + 2)
                Invoke-MMTuiKey $s ([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::LeftArrow, $false, $false, $false))
                Update-MMTuiVisible $s
                $s.Visible[$s.Cursor].Name | Should -Be 'MMRoll'
                $s.Visible.Count | Should -Be 5
            }
        }

        It 'Shows matching members when filtering, and every module when grouping is off' {
            InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
                $s = New-MMTuiState -Options $Options
                Update-MMTuiRows $s
                $s.Filter = 'extra'; Update-MMTuiVisible $s
                $s.Visible.Name | Should -Be @('MMRoll', 'MMRoll.Extra')
                $s.Filter = ''
                Invoke-MMTuiKey $s ([ConsoleKeyInfo]::new('g', [ConsoleKey]::G, $false, $false, $false))
                Update-MMTuiVisible $s
                $s.Visible.Count | Should -Be 7
            }
        }
    }
}
