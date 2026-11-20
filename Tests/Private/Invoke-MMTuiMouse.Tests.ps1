BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'ConvertFrom-MMTuiMouseSequence' {

    It 'Reads <Text> as <Button> at <X>,<Y>' -ForEach @(
        @{ Text = '[<0;10;5M'; Button = 'Left'; X = 9; Y = 4 }
        @{ Text = '[<2;1;1M'; Button = 'Right'; X = 0; Y = 0 }
        @{ Text = '[<1;3;4M'; Button = 'Middle'; X = 2; Y = 3 }
        @{ Text = '[<64;20;7M'; Button = 'WheelUp'; X = 19; Y = 6 }
        @{ Text = '[<65;20;7M'; Button = 'WheelDown'; X = 19; Y = 6 }
        @{ Text = '[<16;10;5M'; Button = 'Left'; X = 9; Y = 4 }
        @{ Text = '[<0;10;5m'; Button = 'None'; X = 9; Y = 4 }
        @{ Text = '[<32;10;5M'; Button = 'None'; X = 9; Y = 4 }
        # The older format: 32 + button, then 33 + column and row
        @{ Text = "[M $([char](33 + 85))$([char](33 + 4))"; Button = 'Left'; X = 85; Y = 4 }
        @{ Text = "[M`"$([char](33 + 2))$([char](33 + 3))"; Button = 'Right'; X = 2; Y = 3 }
        @{ Text = "[M`$!!"; Button = 'Left'; X = 0; Y = 0 }    # 4 is Shift
        @{ Text = "[M#xy"; Button = 'None'; X = 87; Y = 88 }  # release
        @{ Text = "[M``!!"; Button = 'WheelUp'; X = 0; Y = 0 }
        @{ Text = "[Ma!!"; Button = 'WheelDown'; X = 0; Y = 0 }
    ) {
        InModuleScope ModuleManager -Parameters $_ {
            $m = ConvertFrom-MMTuiMouseSequence $Text
            $m.Button | Should -Be $Button
            $m.X | Should -Be $X
            $m.Y | Should -Be $Y
        }
    }

    It 'Returns nothing for text that is not a mouse report (<Text>)' -ForEach @(
        @{ Text = '' }
        @{ Text = '[A' }
        @{ Text = '[<0;10M' }
        @{ Text = 'q' }
    ) {
        InModuleScope ModuleManager -Parameters $_ { ConvertFrom-MMTuiMouseSequence $Text | Should -BeNullOrEmpty }
    }
}

Describe 'ConvertTo-MMTuiKeyInfo' {

    It 'Returns the key press for <Name>' -ForEach @(
        @{ Name = 'Space'; Key = 'Spacebar'; Char = ' ' }
        @{ Name = 'Enter'; Key = 'Enter'; Char = "`r" }
        @{ Name = 'Esc'; Key = 'Escape'; Char = [string][char]27 }
        @{ Name = '/'; Key = 'Oem2'; Char = '/' }
        @{ Name = 'U'; Key = 'U'; Char = 'u' }
        @{ Name = 'y'; Key = 'Y'; Char = 'y' }
    ) {
        InModuleScope ModuleManager -Parameters $_ {
            $k = ConvertTo-MMTuiKeyInfo $Name
            $k.Key | Should -Be $Key
            [string]$k.KeyChar | Should -BeExactly $Char
        }
    }

    It 'Returns nothing for Up/Dn' {
        InModuleScope ModuleManager { ConvertTo-MMTuiKeyInfo 'Up/Dn' | Should -BeNullOrEmpty }
    }
}

Describe 'Read-MMTuiInput' {

    It 'Returns keys read while looking for a mouse report first, in order' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            $a = [ConsoleKeyInfo]::new('a', [ConsoleKey]::A, $false, $false, $false)
            $b = [ConsoleKeyInfo]::new('b', [ConsoleKey]::B, $false, $false, $false)
            $s.PendingKeys.Enqueue($a); $s.PendingKeys.Enqueue($b)
            (Read-MMTuiInput $s).KeyChar | Should -Be 'a'
            (Read-MMTuiInput $s).KeyChar | Should -Be 'b'
        }
    }
}

Describe 'Invoke-MMTuiMouse' {

    BeforeAll {
        # A list state drawn at 120x25: the title is row 0, the column headers row 1, and modules
        # from row 2 (MMAlpha, MMBeta, MMDependent, MMGamma).
        function New-TestState([int]$Height = 25) {
            InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions; Height = $Height } {
                $s = New-MMTuiState -Options $Options
                Update-MMTuiRows $s; Update-MMTuiVisible $s
                $null = Get-MMTuiFrame $s 120 $Height
                $s
            }
        }
    }

    It 'Moves the cursor to a clicked row, and opens the details on a double-click' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            function Click($x, $y) { Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $x; Y = $y }) }
            Click 20 4
            $s.Cursor | Should -Be 2
            $s.CurrentName | Should -Be 'MMDependent'
            $s.Mode | Should -Be 'list'
            Click 20 3
            $s.Cursor | Should -Be 1
            $s.Mode | Should -Be 'list'
            Click 25 3
            $s.Mode | Should -Be 'details'
            $s.Detail.Name | Should -Be 'MMBeta'

            # Below the last module, and other buttons, do nothing.
            $s.Mode = 'list'
            Click 20 10
            $s.Cursor | Should -Be 1
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Right'; X = 20; Y = 2 })
            $s.Cursor | Should -Be 1
        }
    }

    It 'Does not treat clicks on different rows, or too far apart, as a double-click' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            function Click($x, $y) { Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $x; Y = $y }) }
            Click 20 2
            $s.LastClick.Time = [datetime]::UtcNow.AddSeconds(-1)
            Click 20 2
            $s.Mode | Should -Be 'list'
        }
    }

    It 'Selects and deselects a row with its [ ] box, without moving down' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            function Click($x, $y) { Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $x; Y = $y }) }
            Click 2 3
            ($s.Rows | Where-Object Selected).Name | Should -Be 'MMBeta'
            $s.Cursor | Should -Be 1
            Click 2 3
            @($s.Rows | Where-Object Selected).Count | Should -Be 0
            $s.Mode | Should -Be 'list'
        }
    }

    It 'Sorts by the clicked column header' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            function Click($x, $y) { Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $x; Y = $y }) }
            $plain = (((Get-MMTuiFrame $s 120 25) -split "`r`n")[1]) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            Click ($plain.IndexOf('Status') + 2) 1
            $s.Sorts[$s.Sort] | Should -Be 'Status'
            Click ($plain.IndexOf('Scope')) 1
            $s.Sorts[$s.Sort] | Should -Be 'Scope'
            Click ($plain.IndexOf('#')) 1
            $s.Sorts[$s.Sort] | Should -Be 'Versions'
            Click ($plain.IndexOf('Name')) 1
            $s.Sorts[$s.Sort] | Should -Be 'Name'
            Click ($plain.IndexOf('Installed')) 1
            $s.Sorts[$s.Sort] | Should -Be 'Name'
        }
    }

    It 'Cycles the view and sort clicked in the title bar, only in the list' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            function Click($x) { Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $x; Y = 0 }) }
            $plain = (((Get-MMTuiFrame $s 120 25) -split "`r`n")[0]) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            Click ($plain.IndexOf('view:') + 7)
            $s.View | Should -Be 1
            Click ($plain.IndexOf('sort:'))
            $s.Sort | Should -Be 1
            # The | before them, and the module count, aren't clickable.
            Click ($plain.IndexOf('view:') - 3)
            Click 20
            $s.View | Should -Be 1
            $s.Sort | Should -Be 1

            $s.Detail = $s.Visible[0]
            $s.Mode = 'details'
            $null = Get-MMTuiFrame $s 120 25
            Click ($plain.IndexOf('sort:'))
            $s.Sort | Should -Be 1
            $s.Mode | Should -Be 'details'
        }
    }

    It 'Puts view: and sort: in the right place with a remote name and the % latest (<Case>)' -ForEach @(
        @{ Case = 'remote'; Remote = $true }
        @{ Case = 'local'; Remote = $false }
    ) {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ s = $s; Remote = $Remote } {
            if ($Remote) { $s.Remote = @{ Name = 'Server01' } }
            $s.Rows[0].Status = 'UpToDate'
            $plain = (((Get-MMTuiFrame $s 200 25) -split "`r`n")[0]) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain | Should -Match 'latest'
            foreach ($hit in $s.Layout.Title) {
                $plain.Substring($hit.Start, 5) | Should -BeIn @('view:', 'sort:')
            }
            $s.Layout.Title.Count | Should -Be 2
        }
    }

    It 'Presses the key clicked in the help bar' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            # Wide enough for the whole help bar
            $plain = (((Get-MMTuiFrame $s 200 25) -split "`r`n")[-1]) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            # On the key, and on what it does
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $plain.IndexOf(' V view') + 1; Y = 24 })
            $s.View | Should -Be 1
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $plain.IndexOf(' V view') + 5; Y = 24 })
            $s.View | Should -Be 2
            # Up/Dn isn't a key to press
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = 2; Y = 24 })
            $s.Mode | Should -Be 'list'
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $plain.IndexOf(' / filter') + 1; Y = 24 })
            $s.Mode | Should -Be 'filter'
        }
    }

    It 'Answers a confirmation only when an answer is clicked' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            $script:answer = $null
            Request-MMTuiConfirm $s 'Go?' -Choices 'yf' -Action { param($State, $Data, $Choice) $script:answer = $Choice }
            $frame = @((Get-MMTuiFrame $s 200 25) -split "`r`n") -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain = $frame[-2]
            $plain | Should -Match '^ Go\? \[y/f/N\]'
            # Elsewhere on the screen, or between the answers: ignored
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = 20; Y = 2 })
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $plain.IndexOf('/'); Y = 23 })
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $frame[-1].IndexOf(' V view') + 1; Y = 24 })
            $s.Mode | Should -Be 'confirm'
            $s.View | Should -Be 0
            $s.Cursor | Should -Be 0
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $plain.IndexOf('f'); Y = 23 })
            $s.Mode | Should -Be 'list'
            $script:answer | Should -Be 'f'

            Request-MMTuiConfirm $s 'Go?' -Action { param($State) $script:answer = 'yes' }
            $null = Get-MMTuiFrame $s 200 25
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $plain.IndexOf('['); Y = 23 }) # the [ before y
            $s.Mode | Should -Be 'confirm'
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $plain.IndexOf('[') + 3; Y = 23 }) # N
            $s.Message | Should -Be 'Cancelled.'
            $script:answer | Should -Be 'f'
        }
    }

    It 'Applies the filter being typed before handling a click' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            $s.Mode = 'filter'; $s.Filter = 'MM'
            Update-MMTuiVisible $s
            $null = Get-MMTuiFrame $s 120 25
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = 20; Y = 3 })
            $s.Mode | Should -Be 'list'
            $s.Filter | Should -Be 'MM'
            $s.Cursor | Should -Be 1
        }
    }

    It 'Scrolls the list with the wheel, keeping the cursor on screen' {
        # 7 rows high leaves room for 3 of the 4 modules, so scrolling down by 3 stops at the last screenful.
        $s = New-TestState -Height 7
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            $s.Layout.ListRows | Should -Be 3
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'WheelDown'; X = 20; Y = 3 })
            $s.Top | Should -Be 1
            $s.Cursor | Should -Be 1
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'WheelUp'; X = 20; Y = 3 })
            $s.Top | Should -Be 0
            $s.Cursor | Should -Be 1
        }
    }

    It 'Scrolls the output pane when the pointer is over it' {
        $s = New-TestState -Height 30
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            $s.Log.Add(@{ Text = 'Title'; Style = $null })
            for ($i = 0; $i -lt 40; $i++) { $s.Log.Add(@{ Text = "line $i"; Style = $null }) }
            $s.LogOpen = $true
            $null = Get-MMTuiFrame $s 120 30
            $s.Layout.LogRows | Should -BeGreaterThan 0
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'WheelUp'; X = 20; Y = $s.Layout.LogTop + 2 })
            $s.LogScroll | Should -Be 3
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'WheelDown'; X = 20; Y = $s.Layout.LogTop + 2 })
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'WheelDown'; X = 20; Y = $s.Layout.LogTop + 2 })
            $s.LogScroll | Should -Be 0
        }
    }

    It 'Moves to, selects and scrolls through versions in the details view' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            $s.Detail = $s.Visible[0]
            $s.Mode = 'details'
            $null = Get-MMTuiFrame $s 120 25
            $count = @($s.Detail.Info.Installations).Count
            $count | Should -BeGreaterThan 2
            $top = $s.Layout.DetailTop
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = 20; Y = $top + 2 })
            $s.DCursor | Should -Be 2
            $s.DSelected.Count | Should -Be 0
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = 2; Y = $top + 1 })
            $s.DCursor | Should -Be 1
            $s.DSelected.ContainsKey($s.Detail.Info.Installations[1].ModuleBase) | Should -BeTrue
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = 20; Y = $top + $count })
            $s.DCursor | Should -Be 1
            $s.Mode | Should -Be 'details'

            $null = Get-MMTuiFrame $s 120 9
            $s.Layout.DetailRows | Should -BeLessThan $count
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'WheelDown'; X = 20; Y = $top })
            $s.DTop | Should -Be ($count - $s.Layout.DetailRows)
            $s.DCursor | Should -BeGreaterOrEqual $s.DTop
        }
    }

    It 'Goes back from the details with a right-click, and ignores it elsewhere' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            function RightClick { Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Right'; X = 20; Y = 3 }) }
            # In the list it would be Esc, which clears the selection: it does nothing instead.
            $s.Rows[0].Selected = $true
            RightClick
            $s.Rows[0].Selected | Should -BeTrue
            $s.Mode | Should -Be 'list'

            $s.Detail = $s.Visible[0]
            $s.Mode = 'details'
            $null = Get-MMTuiFrame $s 120 25
            RightClick
            $s.Mode | Should -Be 'list'
            $s.Rows[0].Selected | Should -BeTrue

            # It doesn't answer (or cancel) a confirmation.
            $s.Mode = 'details'
            Request-MMTuiConfirm $s 'Go?' -Action { }
            $null = Get-MMTuiFrame $s 120 25
            RightClick
            $s.Mode | Should -Be 'confirm'
        }
    }

    Context 'Module families' {

        BeforeAll {
            Reset-FakeModules
            Add-FakeFamily
        }

        AfterAll { Reset-FakeModules }

        It 'Expands and collapses a family from its arrow' {
            $s = New-TestState
            InModuleScope ModuleManager -Parameters @{ s = $s } {
                $index = [array]::IndexOf(@($s.Visible.Name), 'MMRoll')
                $y = $s.Layout.ListTop + $index
                Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = 4; Y = $y })
                Update-MMTuiVisible $s
                $s.Visible.Name | Should -Contain 'MMRoll.Core'
                $s.Mode | Should -Be 'list'
                $null = Get-MMTuiFrame $s 120 25
                Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = 5; Y = $y })
                Update-MMTuiVisible $s
                $s.Visible.Name | Should -Not -Contain 'MMRoll.Core'
                $s.Mode | Should -Be 'list'
            }
        }
    }
}
