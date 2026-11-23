BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Invoke-MMTuiAction and Receive-MMTuiTask' {

    It 'Runs the action in the background and collects its output, progress and result' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s; Update-MMTuiVisible $s
            $s.Rows[0].Selected = $true
            $script:MMLoadedModule = $null
            $pathBefore = $env:PSModulePath

            Invoke-MMTuiAction $s 'Testing' -Data @{ Count = 2 } -Action {
                param($Data, $Options)
                Write-Host "Count $($Data.Count), filter $($Options.Name -join ',')" -ForegroundColor Green
                foreach ($i in 1..$Data.Count) {
                    Write-Progress -Activity 'Testing' -Status "$i of $($Data.Count)" -PercentComplete (50 * $i)
                    Start-Sleep -Milliseconds 300
                }
                Write-Warning 'careful'
                Write-Error 'it broke'
                Write-Host "Modules: $(@(Get-MMInstalledVersion | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ',')"
                Write-Host "Loaded passed in: $(@(Get-MMLoadedModule | Where-Object { $_.Name -eq 'ModuleManager' }).Count)"
                Write-Host "PSModulePath: $env:PSModulePath"
            } -OnComplete {
                param($State, $Data)
                $State.Completed = $Data.Count
                foreach ($r in $State.Rows) { $r.Selected = $false }
            }

            $s.Task | Should -Not -BeNullOrEmpty
            $s.LogOpen | Should -BeTrue
            $sawProgress = $null
            $deadline = [datetime]::UtcNow.AddSeconds(60)
            while ($s.Task -and [datetime]::UtcNow -lt $deadline) {
                $null = Receive-MMTuiTask $s
                if ($s.Progress) { $sawProgress = $s.Progress }
                Start-Sleep -Milliseconds 50
            }

            $s.Task | Should -BeNullOrEmpty
            $sawProgress.Status | Should -Match '^\d of 2$'
            $s.Completed | Should -Be 2
            @($s.Rows | Where-Object Selected).Count | Should -Be 0

            $text = @($s.Log | ForEach-Object { $_.Text })
            $text[0] | Should -Be 'Testing'
            $text | Should -Contain "Count 2, filter $($Options.Name -join ',')"
            ($s.Log | Where-Object Text -Like 'Count 2*').Style | Should -Be 'Green'
            $text | Should -Contain 'WARNING: careful'
            ($s.Log | Where-Object Text -EQ 'ERROR: it broke').Style | Should -Be 'Red'
            # Opening a runspace in Windows PowerShell adds the default module folders to the
            # (process-wide) PSModulePath; the action, and this session afterwards, must still use ours.
            $text | Should -Contain "PSModulePath: $pathBefore"
            $env:PSModulePath | Should -Be $pathBefore
            $text | Should -Contain 'Modules: MMAlpha,MMBeta,MMDependent,MMGamma'
            # The UI session's loaded modules (including ModuleManager itself) were passed in.
            $text | Should -Contain 'Loaded passed in: 1'
            $text[-1] | Should -Match '^Finished in \d+:\d\d with 1 error\(s\)\.$'
            $s.Message | Should -Match 'Testing - finished with 1 error'
        }
    }

    It 'Shows verbose messages in the output pane only when the UI was started with -Verbose: <Verbose>' -ForEach @(
        @{ Verbose = $true }
        @{ Verbose = $false }
    ) {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions; Verbose = $Verbose } {
            $o = $Options.Clone()
            $o.Verbose = $Verbose
            $s = New-MMTuiState -Options $o
            Invoke-MMTuiAction $s 'Talking' -Data @{ Word = 'hello' } -Action {
                param($Data, $Options)
                Write-Verbose "said $($Data.Word)"
                Write-Host 'done talking'
            }
            $deadline = [datetime]::UtcNow.AddSeconds(60)
            while ($s.Task -and [datetime]::UtcNow -lt $deadline) { $null = Receive-MMTuiTask $s; Start-Sleep -Milliseconds 50 }

            $text = @($s.Log | ForEach-Object { $_.Text })
            $text | Should -Contain 'done talking'
            if ($Verbose) { ($s.Log | Where-Object Text -EQ 'said hello').Style | Should -Be 'Dim' }
            else { $text | Should -Not -Contain 'said hello' }
        }
    }

    It 'In WhatIf mode, says what an operation would change in the output pane, and changes nothing' {
        $base = Join-Path $script:UserRoot 'MMAlpha\1.0.0'
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions; Base = $base } {
            $o = $Options.Clone()
            $o.WhatIf = $true
            $s = New-MMTuiState -Options $o
            Invoke-MMTuiAction $s 'Uninstalling' -Data @{ Base = $Base } -Action {
                param($Data)
                Uninstall-ManagedModule -ModuleBase $Data.Base -Confirm:$false
                Write-Host "Mode after: $script:MMTuiWhatIf"
            }
            $deadline = [datetime]::UtcNow.AddSeconds(60)
            while ($s.Task -and [datetime]::UtcNow -lt $deadline) { $null = Receive-MMTuiTask $s; Start-Sleep -Milliseconds 50 }

            $line = $s.Log | Where-Object Text -Like '*What if: Uninstall module version - MMAlpha 1.0.0*'
            $line | Should -Not -BeNullOrEmpty
            $line.Style | Should -Be 'Yellow'
            # Still on while the action runs; only this session's copy of the flag matters here.
            @($s.Log | ForEach-Object { $_.Text }) | Should -Contain 'Mode after: True'
            $script:MMTuiWhatIf | Should -BeFalse
        }
        Test-Path -LiteralPath $base | Should -BeTrue
    }

    It 'Reports an action that fails to start, and refuses to start a second one while busy' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s; Update-MMTuiVisible $s
            Invoke-MMTuiAction $s 'Throwing' -Data @{} -Action { throw 'stopped early' }
            Invoke-MMTuiAction $s 'Second' -Data @{} -Action { 'never runs' }
            $s.Message | Should -Match "Wait for 'Throwing'"
            $deadline = [datetime]::UtcNow.AddSeconds(60)
            while ($s.Task -and [datetime]::UtcNow -lt $deadline) { $null = Receive-MMTuiTask $s; Start-Sleep -Milliseconds 50 }
            @($s.Log | Where-Object Style -EQ 'Red' | ForEach-Object { $_.Text }) -join "`n" | Should -Match 'stopped early'
            $s.Log[0].Text | Should -Be 'Throwing'
        }
    }
}

Describe 'ConvertTo-MMTuiLogEntry' {

    It 'Maps <Name> to text and a style' -ForEach @(
        @{ Name = 'an ANSI-coloured string'; Record = "$([char]27)[92mUpdated$([char]27)[0m"; Text = 'Updated'; Style = 'Green' }
        @{ Name = 'a bright red ANSI string'; Record = "$([char]27)[1;91mFailed$([char]27)[0m"; Text = 'Failed'; Style = 'Red' }
        @{ Name = 'plain output'; Record = 'hello'; Text = 'hello'; Style = $null }
        @{ Name = 'a number'; Record = 42; Text = '42'; Style = $null }
    ) {
        InModuleScope ModuleManager -Parameters @{ Record = $Record; Text = $Text; Style = $Style } {
            $e = ConvertTo-MMTuiLogEntry $Record
            $e.Text | Should -Be $Text
            $e.Style | Should -Be $Style
        }
    }

    It 'Uses the colour of a Write-Host message from Windows PowerShell' {
        InModuleScope ModuleManager {
            $message = [System.Management.Automation.HostInformationMessage]@{ Message = 'Done'; ForegroundColor = 'DarkYellow' }
            $record = [System.Management.Automation.InformationRecord]::new($message, 'test')
            $e = ConvertTo-MMTuiLogEntry $record
            $e.Text | Should -Be 'Done'
            $e.Style | Should -Be 'Yellow'
        }
    }

    It 'Prefixes warnings and errors' {
        InModuleScope ModuleManager {
            (ConvertTo-MMTuiLogEntry ([System.Management.Automation.WarningRecord]::new('w'))).Text | Should -Be 'WARNING: w'
            $err = [System.Management.Automation.ErrorRecord]::new([Exception]::new('e'), 'id', 'NotSpecified', $null)
            $e = ConvertTo-MMTuiLogEntry $err
            $e.Text | Should -Be 'ERROR: e'
            $e.Style | Should -Be 'Red'
        }
    }
}
