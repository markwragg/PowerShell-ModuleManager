BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Invoke-MMTuiKey' {

    It 'Handles key presses that change state' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            $s.Height = 30
            Update-MMTuiRows $s; Update-MMTuiVisible $s
            function Key($char, $key) { [ConsoleKeyInfo]::new($char, $key, $false, $false, $false) }
            Invoke-MMTuiKey $s (Key ' ' ([ConsoleKey]::Spacebar)); Update-MMTuiVisible $s
            @($s.Rows | Where-Object Selected).Count | Should -Be 1
            $s.Cursor | Should -Be 1
            Invoke-MMTuiKey $s (Key ([char]27) ([ConsoleKey]::Escape))
            @($s.Rows | Where-Object Selected).Count | Should -Be 0
            Invoke-MMTuiKey $s (Key '/' ([ConsoleKey]::Oem2))
            $s.Mode | Should -Be 'filter'
            Invoke-MMTuiKey $s (Key 'b' ([ConsoleKey]::B)); Update-MMTuiVisible $s
            $s.Visible.Name | Should -Be 'MMBeta'
            Invoke-MMTuiKey $s (Key ([char]13) ([ConsoleKey]::Enter))
            $s.Mode | Should -Be 'list'
            Invoke-MMTuiKey $s (Key ([char]13) ([ConsoleKey]::Enter))
            $s.Mode | Should -Be 'details'
            $s.Detail.Name | Should -Be 'MMBeta'
            Invoke-MMTuiKey $s (Key 'x' ([ConsoleKey]::X))
            $s.Mode | Should -Be 'confirm'
            Invoke-MMTuiKey $s (Key 'n' ([ConsoleKey]::N))
            $s.Mode | Should -Be 'details'
            $s.Message | Should -Be 'Cancelled.'
            Invoke-MMTuiKey $s (Key ([char]27) ([ConsoleKey]::Escape))
            $s.Mode | Should -Be 'list'
            Invoke-MMTuiKey $s (Key 'q' ([ConsoleKey]::Q))
            $s.Quit | Should -BeTrue
        }
    }

    It 'Opens, scrolls and closes the output pane' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s; Update-MMTuiVisible $s
            function Key($char, $key) { [ConsoleKeyInfo]::new($char, $key, $false, $false, $false) }
            Invoke-MMTuiKey $s (Key 'l' ([ConsoleKey]::L))
            $s.LogOpen | Should -BeFalse
            $s.Message | Should -Match 'No output yet'

            $s.Log.Add(@{ Text = 'Title'; Style = $null })
            Invoke-MMTuiKey $s (Key 'l' ([ConsoleKey]::L))
            $s.LogOpen | Should -BeTrue
            $s.LogBody = 6
            Invoke-MMTuiKey $s (Key '[' ([ConsoleKey]::Oem4))
            $s.LogScroll | Should -Be 5
            Invoke-MMTuiKey $s (Key ']' ([ConsoleKey]::Oem6))
            $s.LogScroll | Should -Be 0

            # Esc closes the pane before it clears the selection.
            $s.Rows[0].Selected = $true
            Invoke-MMTuiKey $s (Key ([char]27) ([ConsoleKey]::Escape))
            $s.LogOpen | Should -BeFalse
            $s.Rows[0].Selected | Should -BeTrue
        }
    }

    It 'Blocks new actions and quitting while an operation runs' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s; Update-MMTuiVisible $s
            function Key($char, $key, $ctrl = $false) { [ConsoleKeyInfo]::new($char, $key, $false, $false, $ctrl) }
            $s.Task = @{ Title = 'Updating 1 module(s)'; Started = [datetime]::UtcNow; PowerShell = $null }

            foreach ($k in @((Key 'x' ([ConsoleKey]::X)), (Key 'o' ([ConsoleKey]::O)), (Key 'r' ([ConsoleKey]::R)))) {
                Invoke-MMTuiKey $s $k
                $s.Mode | Should -Be 'list'
                $s.Message | Should -Match "Wait for 'Updating 1 module\(s\)' to finish"
            }
            Invoke-MMTuiKey $s (Key 'q' ([ConsoleKey]::Q))
            $s.Quit | Should -BeFalse
            $s.Message | Should -Match 'before quitting'

            Invoke-MMTuiKey $s (Key ([char]3) ([ConsoleKey]::C) $true)
            $s.Mode | Should -Be 'confirm'
            $s.Confirm.Prompt | Should -Match '^Stop'
            Mock Stop-MMTuiTask { } -ModuleName ModuleManager
            Invoke-MMTuiKey $s (Key 'y' ([ConsoleKey]::Y))
            $s.Quit | Should -BeTrue
        }
    }
}
