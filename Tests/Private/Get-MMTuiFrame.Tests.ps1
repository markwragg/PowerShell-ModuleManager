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

    It 'Shows module families, the repository check, and scrolls to keep the cursor in view' {
        Add-FakeFamily
        try {
            InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
                $s = New-MMTuiState -Options $Options
                Update-MMTuiRows $s
                foreach ($n in 'MMRoll.Core', 'MMRoll.Extra') { ($s.Rows | Where-Object Name -EQ $n).Status = 'UpdateAvailable' }
                ($s.Rows | Where-Object Name -EQ 'MMAlpha').Info.IsLoaded = $true
                Update-MMTuiVisible $s
                $s.Job = [pscustomobject]@{ Done = 3; Total = 9 }
                $plain = (Get-MMTuiFrame $s 110 20) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
                $plain | Should -Match 'MMRoll \(\+2\)'
                $plain | Should -Match '2 updates'
                $plain | Should -Match 'Checking repositories 3/9'
                $plain | Should -Match 'MMAlpha \*'

                $s.Expanded['mmroll'] = $true
                Update-MMTuiVisible $s
                $plain = (Get-MMTuiFrame $s 110 20) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
                $plain | Should -Match "$($script:MMGlyph.LastBranch) MMRoll\.Extra"

                # A short screen: moving to the end scrolls down, and back to the top scrolls up.
                Set-MMTuiCursor $s ($s.Visible.Count - 1)
                $null = Get-MMTuiFrame $s 110 8
                $s.Top | Should -BeGreaterThan 0
                Set-MMTuiCursor $s 0
                $null = Get-MMTuiFrame $s 110 8
                $s.Top | Should -Be 0
            }
        }
        finally { Reset-FakeModules }
    }

    It 'Shows the share of modules on their latest version once the check is done, if it fits' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s; Update-MMTuiVisible $s
            function TitleBar([int]$Width) { (((Get-MMTuiFrame $s $Width 15) -split "`r`n")[0]) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", '' }
            $status = @{ MMAlpha = 'UpdateAvailable'; MMBeta = 'NotInRepository'; MMDependent = 'UpToDate'; MMGamma = 'LocalNewer' }
            foreach ($r in $s.Rows) { $r.Status = $status[$r.Name] }

            # 2 of the 3 found are latest (newer than the repository counts); MMBeta isn't counted.
            TitleBar 120 | Should -Match ' 4 modules  \|  1 updates  \|  66% latest  \|  view: '

            # Not while checking, nor when there isn't room.
            $s.Job = [pscustomobject]@{ Done = 3; Total = 4 }
            TitleBar 120 | Should -Not -Match 'latest'
            $s.Job = $null
            TitleBar 60 | Should -Not -Match 'latest'

            # Nothing found, nothing to show.
            foreach ($r in $s.Rows) { $r.Status = 'Checking' }
            TitleBar 120 | Should -Not -Match 'latest'

            # Remotely, it follows the computer name and counts.
            foreach ($r in $s.Rows) { $r.Status = 'UpToDate' }
            $s.Remote = @{ Name = 'Server01' }
            TitleBar 120 | Should -Match 'ModuleManager on Server01  4 modules  \|  0 updates  \|  100% latest  \|  view: '
        }
    }

    It 'Says it is scanning before the first scan has finished' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            $s.Scanning = $true
            $plain = (Get-MMTuiFrame $s 100 15) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain | Should -Match 'Scanning installed modules\.\.\.'
            $plain | Should -Not -Match 'No modules match'
            $s.Remote = @{ Name = 'Server01' }
            $plain = (Get-MMTuiFrame $s 100 15) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain | Should -Match 'Scanning installed modules on Server01\.\.\.'
        }
    }

    It 'Says when nothing matches, and shows the confirmation prompt' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s
            $s.Filter = 'no such module'
            Update-MMTuiVisible $s
            $s.Mode = 'confirm'
            $s.Confirm = @{ Prompt = 'Uninstall everything?'; ReturnMode = 'list' }
            $plain = (Get-MMTuiFrame $s 100 15) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain | Should -Match 'No modules match'
            $plain | Should -Match 'Uninstall everything\? \[y/N\]'
        }
    }

    It 'Shows the details of a module, with selected and loaded versions' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s
            $row = $s.Rows | Where-Object Name -EQ 'MMAlpha'
            $row.Latest = '2.0.0'
            $row.Result = [pscustomobject]@{ Repository = 'PSGallery' }
            $installs = @($row.Info.Installations)
            $installs[1].IsLoaded = $true
            $s.Detail = $row
            $s.Mode = 'confirm'
            $s.Confirm = @{ Prompt = 'Uninstall MMAlpha 1.1.0?'; ReturnMode = 'details' }
            $s.DSelected[$installs[1].ModuleBase] = $true
            $s.DCursor = 3
            $plain = (Get-MMTuiFrame $s 120 9) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain | Should -Match 'latest in PSGallery: 2\.0\.0'
            $plain | Should -Match '\(manual\)'
            $s.DTop | Should -BeGreaterThan 0
            $s.DCursor = 0
            $plain = (Get-MMTuiFrame $s 120 30) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain | Should -Match '\[x\] 1\.1\.0'
            $plain | Should -Match 'yes'
            $s.DTop | Should -Be 0
        }
    }

    It 'Says on the help bar when U, X, M and O will act on the selection' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s; Update-MMTuiVisible $s
            function HelpBar { (((Get-MMTuiFrame $s 400 15) -split "`r`n")[-1]) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", '' }

            $bar = HelpBar
            $bar | Should -Match ' U update  X uninstall  M move scope  O remove old  '

            # A selected version: only X and M act on it.
            $alpha = $s.Rows | Where-Object Name -EQ 'MMAlpha'
            $s.DSelected[@($alpha.Info.Installations)[1].ModuleBase] = $true
            HelpBar | Should -Match ' U update  X uninstall selected  M move selected  O remove old  '

            # A selected module: all three do.
            $alpha.Selected = $true
            HelpBar | Should -Match ' U update selected  X uninstall selected  M move selected  O remove old from selected  '

            # The details view: X and M follow the version selection.
            $s.Mode = 'details'; $s.Detail = $alpha
            HelpBar | Should -Match ' X uninstall selected  M move selected '
            $s.DSelected = @{}
            HelpBar | Should -Match ' X uninstall  M move scope  O remove old '
        }
    }
}
