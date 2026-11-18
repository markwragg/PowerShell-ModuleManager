BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Get-MMTuiFrame' {

    It 'Renders full frames at exact width with no style names leaking into text (<Width>x<Height>, <Mode>)' -ForEach @(
        @{ Width = 120; Height = 25; Mode = 'list' }
        @{ Width = 70; Height = 12; Mode = 'list' }
        @{ Width = 120; Height = 25; Mode = 'details' }
        @{ Width = 50; Height = 10; Mode = 'filter' }
    ) {
        $params = $_ + @{ Options = $TuiOptions }
        InModuleScope ModuleManager -Parameters $params {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s; Update-MMTuiVisible $s
            $s.Rows[0].Selected = $true
            $s.Mode = $Mode
            $s.Detail = $s.Rows[0]
            $frame = Get-MMTuiFrame $s $Width $Height
            $plain = @(($frame -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", '') -split "`r`n")
            $plain.Count | Should -Be $Height
            $plain | ForEach-Object { $_.Length | Should -Be $Width }
            $frame | Should -Not -MatchExactly 'Header|Magenta|Selected|Dim\b'
            if ($Mode -ne 'details') { $plain -join "`n" | Should -Match 'MMAlpha' }
        }
    }

    It 'Fits the output pane into the frame (<Width>x<Height>, <Mode>, running: <Running>)' -ForEach @(
        @{ Width = 120; Height = 30; Mode = 'list'; Running = $true }
        @{ Width = 70; Height = 14; Mode = 'list'; Running = $false }
        @{ Width = 120; Height = 30; Mode = 'details'; Running = $true }
        @{ Width = 50; Height = 10; Mode = 'list'; Running = $true }
    ) {
        $params = $_ + @{ Options = $TuiOptions }
        InModuleScope ModuleManager -Parameters $params {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s; Update-MMTuiVisible $s
            $s.Mode = $Mode
            $s.Detail = $s.Rows[0]
            $s.LogOpen = $true
            $s.Log.Add(@{ Text = 'Updating 2 module(s)'; Style = 'Cyan' })
            foreach ($i in 1..30) { $s.Log.Add(@{ Text = "Line $i " + ('x' * 150); Style = $null }) }
            $s.Log.Add(@{ Text = 'ERROR: last line'; Style = 'Red' })
            if ($Running) {
                $s.Task = @{ Title = 'Updating 2 module(s)'; Started = [datetime]::UtcNow }
                $s.Progress = @{ Activity = 'Updating modules'; Status = '1 of 2: MMAlpha'; Percent = 50 }
            }
            $frame = Get-MMTuiFrame $s $Width $Height
            $plain = @(($frame -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", '') -split "`r`n")
            $plain.Count | Should -Be $Height
            $plain | ForEach-Object { $_.Length | Should -Be $Width }
            $frame | Should -Not -MatchExactly 'Header|Magenta|Selected|Dim\b|HelpBar'
            if ($Height -ge 14) {
                $text = $plain -join "`n"
                $text | Should -Match 'Output: Updating 2 module\(s\)'
                $text | Should -Match 'ERROR: last line'
                $s.ListHeight | Should -BeGreaterOrEqual 5
                if ($Running) { $text | Should -Match '50%  1 of 2: MMAlpha' }
            }
        }
    }

    It 'Scrolls the output pane back through earlier output' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s; Update-MMTuiVisible $s
            $s.LogOpen = $true
            $s.Log.Add(@{ Text = 'Title'; Style = $null })
            foreach ($i in 1..40) { $s.Log.Add(@{ Text = "Line $i"; Style = $null }) }
            $s.LogScroll = 1000
            $plain = (Get-MMTuiFrame $s 80 30) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain | Should -Match 'Line 1\s'
            $plain | Should -Not -Match 'Line 40'
            $s.LogScroll | Should -Be (40 - $s.LogBody)
        }
    }
}
