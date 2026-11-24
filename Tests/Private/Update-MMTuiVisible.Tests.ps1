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
            # Each fake module's description is 'Fake module <name>'. n: matches only names, d: only
            # descriptions, and no prefix either.
            $s.Filter = 'fake'; Update-MMTuiVisible $s; $s.Visible.Count | Should -Be 4
            $s.Filter = 'n:fake'; Update-MMTuiVisible $s; $s.Visible.Count | Should -Be 0
            $s.Filter = 'N:gam'; Update-MMTuiVisible $s; $s.Visible.Name | Should -Be 'MMGamma'
            $s.Filter = 'd:fake'; Update-MMTuiVisible $s; $s.Visible.Count | Should -Be 4
            $s.Filter = 'd:'; Update-MMTuiVisible $s; $s.Visible.Count | Should -Be 4
            $s.Filter = ''; $s.View = 2; Update-MMTuiVisible $s
            $s.Visible.Name | Should -Be 'MMAlpha'
            $s.View = 0
            foreach ($i in 0..3) { $s.Sort = $i; $s.View = 0; Update-MMTuiVisible $s; $s.Visible.Count | Should -Be 4 }
        }
    }

    It 'With -IfChanged, works the rows out again only when what they depend on changed' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s
            Update-MMTuiVisible $s
            $first = $s.Visible
            Update-MMTuiVisible $s -IfChanged
            [object]::ReferenceEquals($s.Visible, $first) | Should -BeTrue    # nothing changed: kept
            $s.Filter = 'gam'; Update-MMTuiVisible $s -IfChanged
            $s.Visible.Name | Should -Be 'MMGamma'
            $s.Filter = ''; Update-MMTuiVisible $s -IfChanged
            $s.Visible.Count | Should -Be 4
            # A status change (through Update-MMTuiStatus) is noticed, for the Updates view.
            $s.View = [array]::IndexOf($s.Views, 'Updates'); Update-MMTuiVisible $s -IfChanged
            $s.Visible.Count | Should -Be 0
            $s.Gallery['mmalpha'] = [pscustomobject]@{ RequestedName = 'MMAlpha'; Version = '9.0.0'; ModuleVersion = [version]'9.0.0'; PrereleaseLabel = ''; Status = 'Found' }
            Update-MMTuiStatus $s
            Update-MMTuiVisible $s -IfChanged
            $s.Visible.Name | Should -Be 'MMAlpha'
            # So is a rescan.
            $s.View = 0; Update-MMTuiVisible $s
            $before = $s.Visible
            Update-MMTuiRows $s; Update-MMTuiVisible $s -IfChanged
            [object]::ReferenceEquals($s.Visible, $before) | Should -BeFalse
        }
    }

    It 'Cycles the scope with C through the scopes that have modules, showing the modules in each' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s
            # The fake modules are all in one scope, so give them some: MMAlpha has versions in two.
            ($s.Rows | Where-Object Name -EQ 'MMAlpha').Info.Scope = 'CurrentUser, AllUsers'
            ($s.Rows | Where-Object Name -EQ 'MMGamma').Info.Scope = 'AllUsers'
            foreach ($r in $s.Rows | Where-Object Name -NotIn 'MMAlpha', 'MMGamma') { $r.Info.Scope = 'CurrentUser' }
            Update-MMTuiVisible $s
            $all = $s.Visible.Count
            $expected = @('AllUsers', 'CurrentUser')    # System and Other have no modules, so are skipped

            $c = [ConsoleKeyInfo]::new('c', [ConsoleKey]::C, $false, $false, $false)
            $seen = foreach ($i in 1..$expected.Count) {
                Invoke-MMTuiKey $s $c; Update-MMTuiVisible $s
                $scope = $s.Scopes[$s.InScope]
                $s.Visible.Count | Should -BeGreaterThan 0
                foreach ($r in $s.Visible) { @($r.Info.Scope -split ', ') | Should -Contain $scope }
                $scope
            }
            $seen | Should -Be $expected
            # Two modules each way: MMAlpha is in both.
            $s.InScope = 1; Update-MMTuiVisible $s
            $s.Visible.Name | Should -Be @('MMAlpha', 'MMGamma')
            $s.InScope = [array]::IndexOf($s.Scopes, 'CurrentUser')
            Invoke-MMTuiKey $s $c; Update-MMTuiVisible $s    # and back to All
            $s.InScope | Should -Be 0
            $s.Visible.Count | Should -Be $all
            (Get-MMTuiFrame $s 140 20) | Should -Match 'scope: All'
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

        It 'Sorts the members of an expanded family by the sort, as well as the top level' {
            InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
                $s = New-MMTuiState -Options $Options
                Update-MMTuiRows $s
                $s.Expanded['mmroll'] = $true
                $members = { $i = [array]::IndexOf(@($s.Visible.Name), 'MMRoll'); @($s.Visible[($i + 1)..($i + 2)]) }

                Update-MMTuiVisible $s
                (& $members).Name | Should -Be @('MMRoll.Core', 'MMRoll.Extra')    # by name

                # MMRoll.Core has 3 versions installed; give MMRoll.Extra more, so it sorts first.
                ($s.Rows | Where-Object Name -EQ 'MMRoll.Extra').Info.VersionCount = 5
                $s.Sort = [array]::IndexOf($s.Sorts, 'Versions'); Update-MMTuiVisible $s
                $sorted = & $members
                $sorted.Name | Should -Be @('MMRoll.Extra', 'MMRoll.Core')
                $sorted[0].Last | Should -BeFalse
                $sorted[1].Last | Should -BeTrue
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
