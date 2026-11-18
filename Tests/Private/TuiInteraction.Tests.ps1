BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
    Set-FakeGalleryCache

    # A terminal UI state with repository results applied (from the fake cache, so no network).
    function New-TestState([switch]$NoLookup) {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions; NoLookup = [bool]$NoLookup } {
            Mock Write-Progress { }
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s
            if (-not $NoLookup) {
                Start-MMTuiLookup $s
                while ($s.Job) { $null = Receive-MMTuiLookup $s }
            }
            Update-MMTuiVisible $s
            $s.ListHeight = 20
            $s
        }
    }
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Show-ModuleManager' {

    It 'Refuses to run without an interactive console' {
        Mock -ModuleName ModuleManager Test-MMInteractiveConsole { $false }
        { Show-ModuleManager } | Should -Throw '*interactive console*'
    }

    It 'Draws the screen, handles keys and restores the console on exit (<Case>)' -ForEach @(
        @{ Case = 'checking repositories'; NoUpdateCheck = $false }
        @{ Case = 'with -NoUpdateCheck'; NoUpdateCheck = $true }
    ) {
        InModuleScope ModuleManager -Parameters $_ {
            $script:written = [System.Collections.Generic.List[string]]::new()
            $script:keys = [System.Collections.Generic.Queue[object]]::new()
            foreach ($k in @(
                    $null
                    [ConsoleKeyInfo]::new([char]0, [ConsoleKey]::DownArrow, $false, $false, $false)
                    [ConsoleKeyInfo]::new('v', [ConsoleKey]::V, $false, $false, $false)
                    [ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
                )) { $script:keys.Enqueue($k) }
            Mock Test-MMInteractiveConsole { $true }
            Mock Write-MMConsole { $script:written.Add($Text) }
            Mock Get-MMConsoleSize { @{ Width = 100; Height = 20 } }
            Mock Read-MMTuiKey { $script:keys.Dequeue() }
            Mock Start-Sleep { }
            Mock Write-Progress { }

            Show-ModuleManager -NoUpdateCheck:$NoUpdateCheck

            $script:keys.Count | Should -Be 0
            $plain = ($script:written -join '') -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain | Should -Match 'ModuleManager'
            $plain | Should -Match 'MMAlpha'
            $plain | Should -Match 'view: Updates'
            if ($NoUpdateCheck) { $plain | Should -Match 'Update check skipped' }
            $script:written[0] | Should -Match '\[\?1049h'        # entered the alternate screen
            $script:written[-1] | Should -Match '\[\?1049l'       # and left it
        }
    }
}

Describe 'Terminal UI keys' {

    BeforeAll {
        function Key([char]$Char, [ConsoleKey]$ConsoleKey, [switch]$Ctrl) { [ConsoleKeyInfo]::new($Char, $ConsoleKey, $false, $false, [bool]$Ctrl) }
    }

    It 'Moves through the list' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s; Key = ${function:Key} } {
            $last = $S.Visible.Count - 1
            Invoke-MMTuiKey $S (& $Key ([char]0) End); $S.Cursor | Should -Be $last
            Invoke-MMTuiKey $S (& $Key ([char]0) Home); $S.Cursor | Should -Be 0
            Invoke-MMTuiKey $S (& $Key ([char]0) DownArrow); $S.Cursor | Should -Be 1
            Invoke-MMTuiKey $S (& $Key ([char]0) UpArrow); $S.Cursor | Should -Be 0
            Invoke-MMTuiKey $S (& $Key 'j' J); $S.Cursor | Should -Be 1
            Invoke-MMTuiKey $S (& $Key 'k' K); $S.Cursor | Should -Be 0
            Invoke-MMTuiKey $S (& $Key ([char]0) PageDown); $S.Cursor | Should -Be $last
            Invoke-MMTuiKey $S (& $Key ([char]0) PageUp); $S.Cursor | Should -Be 0
            $S.CurrentName | Should -Be $S.Visible[0].Name
        }
    }

    It 'Filters, cycles the view and sort, and toggles grouping' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s; Key = ${function:Key} } {
            Invoke-MMTuiKey $S (& $Key '/' Oem2)
            foreach ($ch in 'gamx'.ToCharArray()) { Invoke-MMTuiKey $S (& $Key $ch ([ConsoleKey]::A)) }
            Invoke-MMTuiKey $S (& $Key ([char]8) Backspace)
            $S.Filter | Should -Be 'gam'
            Invoke-MMTuiKey $S (& $Key ([char]27) Escape)
            $S.Filter | Should -Be ''
            $S.Mode | Should -Be 'list'
            Invoke-MMTuiKey $S (& $Key '/' Oem2); Invoke-MMTuiKey $S (& $Key 'b' B); Invoke-MMTuiKey $S (& $Key ([char]13) Enter)
            $S.Mode | Should -Be 'list'
            Invoke-MMTuiKey $S (& $Key ([char]27) Escape)   # Esc with no selection clears the filter
            $S.Filter | Should -Be ''

            Invoke-MMTuiKey $S (& $Key 'v' V); $S.View | Should -Be 1
            Invoke-MMTuiKey $S (& $Key 's' S); $S.Sort | Should -Be 1
            Invoke-MMTuiKey $S (& $Key 'g' G); $S.Group | Should -BeFalse; $S.Message | Should -Match 'separately'
            Invoke-MMTuiKey $S (& $Key 'g' G); $S.Group | Should -BeTrue; $S.Message | Should -Match 'Grouping'
        }
    }

    It 'Selects every module with an update, then clears the selection' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s; Key = ${function:Key} } {
            Invoke-MMTuiKey $S (& $Key 'a' A)
            @($S.Rows | Where-Object Selected | ForEach-Object { $_.Name }) | Should -Be @('MMAlpha')
            $S.Message | Should -Match 'Selected 1 module'
            Invoke-MMTuiKey $S (& $Key 'a' A)
            @($S.Rows | Where-Object Selected).Count | Should -Be 0

            foreach ($r in $S.Rows) { $r.Status = 'UpToDate' }
            Invoke-MMTuiKey $S (& $Key 'a' A); $S.Message | Should -Match 'No updates available'
            $S.Job = @{ }
            Invoke-MMTuiKey $S (& $Key 'a' A); $S.Message | Should -Match 'Still checking'
            Invoke-MMTuiKey $S (& $Key 'u' U); $S.Message | Should -Match 'try again in a moment'
            $S.Job = $null
            Invoke-MMTuiKey $S (& $Key 'u' U); $S.Message | Should -Match 'Nothing to update'
        }
    }

    It 'Rescans and checks the repositories again with R' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s; Key = ${function:Key} } {
            Mock Start-MMGalleryLookup { [pscustomobject]@{ Tasks = @(); Results = [System.Collections.Generic.List[object]]::new(); Pool = $null; Total = 0; Done = 0 } }
            Invoke-MMTuiKey $S (& $Key 'r' R)
            Should -Invoke Start-MMGalleryLookup -Times 1 -ParameterFilter { $Refresh }
            $S.Message | Should -Match 'Rescanned'
        }
    }

    It 'Opens the details view and uses its keys' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s; Key = ${function:Key} } {
            Mock Invoke-MMTuiAction { }
            Mock Get-MMUntrustedRepository { }
            $S.Cursor = [array]::IndexOf(@($S.Visible | ForEach-Object { $_.Name }), 'MMAlpha')
            Invoke-MMTuiKey $S (& $Key ([char]13) Enter)
            $S.Mode | Should -Be 'details'
            $count = $S.Detail.Info.VersionCount

            Invoke-MMTuiKey $S (& $Key ([char]0) End); $S.DCursor | Should -Be ($count - 1)
            Invoke-MMTuiKey $S (& $Key ([char]0) Home); $S.DCursor | Should -Be 0
            Invoke-MMTuiKey $S (& $Key ([char]0) DownArrow); $S.DCursor | Should -Be 1
            Invoke-MMTuiKey $S (& $Key ([char]0) UpArrow); $S.DCursor | Should -Be 0
            Invoke-MMTuiKey $S (& $Key 'j' J); Invoke-MMTuiKey $S (& $Key 'k' K); $S.DCursor | Should -Be 0
            Invoke-MMTuiKey $S (& $Key ' ' Spacebar); $S.DSelected.Count | Should -Be 1
            Invoke-MMTuiKey $S (& $Key ([char]0) UpArrow); Invoke-MMTuiKey $S (& $Key ' ' Spacebar); $S.DSelected.Count | Should -Be 0

            foreach ($k in @((& $Key ([char]0) Delete), (& $Key 'x' X), (& $Key 'o' O), (& $Key 'u' U))) {
                Invoke-MMTuiKey $S $k
                $S.Mode | Should -Be 'confirm'
                Invoke-MMTuiKey $S (& $Key 'n' N)
                $S.Mode | Should -Be 'details'
            }
            Invoke-MMTuiKey $S (& $Key 'q' Q); $S.Mode | Should -Be 'list'
            Invoke-MMTuiKey $S (& $Key ([char]0) RightArrow); $S.Mode | Should -Be 'details'
            Invoke-MMTuiKey $S (& $Key ([char]8) Backspace); $S.Mode | Should -Be 'list'
            Invoke-MMTuiKey $S (& $Key ([char]0) Delete); $S.Mode | Should -Be 'confirm'
            Invoke-MMTuiKey $S (& $Key 'n' N)
        }
    }

    It 'Expands and collapses module families' {
        Add-FakeFamily
        try {
            $s = New-TestState -NoLookup
            InModuleScope ModuleManager -Parameters @{ S = $s; Key = ${function:Key} } {
                Set-MMTuiCursor $S ([array]::IndexOf(@($S.Visible | ForEach-Object { $_.Name }), 'MMRoll'))
                $count = $S.Visible.Count
                Invoke-MMTuiKey $S (& $Key ([char]0) RightArrow); Update-MMTuiVisible $S
                $S.Visible.Count | Should -Be ($count + 2)
                Invoke-MMTuiKey $S (& $Key ([char]0) DownArrow)          # onto a member
                $S.Visible[$S.Cursor].Indent | Should -BeGreaterThan 0
                Invoke-MMTuiKey $S (& $Key ([char]0) LeftArrow); Update-MMTuiVisible $S
                $S.Visible.Count | Should -Be $count
                $S.Visible[$S.Cursor].Name | Should -Be 'MMRoll'
                Invoke-MMTuiKey $S (& $Key ([char]0) LeftArrow)          # already collapsed: nothing to do
                $S.Group = $false
                Invoke-MMTuiKey $S (& $Key ([char]0) LeftArrow)
                $S.Visible.Count | Should -Be $count
            }
        }
        finally { Reset-FakeModules; Set-FakeGalleryCache }
    }
}

Describe 'Terminal UI actions' {

    BeforeEach {
        # Run each action here rather than in a background runspace, so its code is covered.
        Mock -ModuleName ModuleManager Invoke-MMTuiAction {
            $State.Log.Clear()
            & $Action $Data $State.Options
            if ($OnComplete) { & $OnComplete $State $Data }
        }
        Mock -ModuleName ModuleManager Write-Host { }
    }

    It 'Updates the selected modules and reports each result' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Get-MMUntrustedRepository { 'PSGallery' }
            Mock Update-ManagedModule {
                [pscustomobject]@{ Name = 'MMAlpha'; Version = '2.0.0'; UpdatedAsDependencyOf = $null }
                [pscustomobject]@{ Name = 'MMGamma'; Version = '3.0.0'; UpdatedAsDependencyOf = 'MMAlpha' }
                Write-Error 'MMOther failed'
                Write-Error 'MMOther failed'
            }
            ($S.Rows | Where-Object Name -EQ 'MMAlpha').Selected = $true
            Request-MMTuiUpdate $S (Get-MMTuiTarget $S)
            $S.Mode | Should -Be 'confirm'
            $S.Confirm.Prompt | Should -Match 'Update 1 module\(s\): MMAlpha 2\.0\.0-beta1 -> 2\.0\.0 - from untrusted repository PSGallery'
            $S.Confirm.Data.Trust | Should -BeTrue
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))

            Should -Invoke Update-ManagedModule -Times 1 -ParameterFilter { $Name -eq 'MMAlpha' -and $TrustRepository -and $PassThru }
            Should -Invoke Write-Host -ParameterFilter { $Object -match 'Updated  MMGamma 3\.0\.0  \(dependency of MMAlpha\)' }
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -match 'Failed   MMOther failed' }
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '2 updated (1 as dependencies), 1 failed.' }
            @($S.Rows | Where-Object Selected).Count | Should -Be 0
        }
    }

    It "Reports the module's own errors, not the caught errors behind them" {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Get-MMUntrustedRepository { }
            Mock Update-ManagedModule {
                Write-Error 'Unable to connect to the remote server'
                Write-Error -Message 'Failed to update MMAlpha: Unable to connect to the remote server' -ErrorId 'ModuleManager.UpdateFailed'
            }
            Request-MMTuiUpdate $S @($S.Rows | Where-Object Name -EQ 'MMAlpha')
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like '  Failed *' }
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq '  Failed   Failed to update MMAlpha: Unable to connect to the remote server' }
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq '0 updated, 1 failed.' }
        }
    }

    It 'Lists only the first few modules in the update prompt' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Get-MMUntrustedRepository { }
            $rows = foreach ($i in 1..6) { [pscustomobject]@{ Name = "MM$i"; Status = 'UpdateAvailable'; Latest = '2.0'; Info = @{ Version = '1.0' }; Result = $null } }
            Request-MMTuiUpdate $S $rows
            $S.Confirm.Prompt | Should -Match 'MM4 1\.0 -> 2\.0 and 2 more \?$'
            $S.Confirm.Data.Trust | Should -BeFalse
        }
    }

    It 'Uninstalls the targeted modules' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Uninstall-ManagedModule { }
            foreach ($n in 'MMAlpha', 'MMGamma') { ($S.Rows | Where-Object Name -EQ $n).Selected = $true }
            Request-MMTuiUninstall $S
            $S.Confirm.Prompt | Should -Be 'Uninstall 2 modules (5 versions) ?'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            Should -Invoke Uninstall-ManagedModule -Times 1 -ParameterFilter { $ModuleBase.Count -eq 5 }
            @($S.Rows | Where-Object Selected).Count | Should -Be 0

            $S.Cursor = [array]::IndexOf(@($S.Visible | ForEach-Object { $_.Name }), 'MMGamma')
            Request-MMTuiUninstall $S
            $S.Confirm.Prompt | Should -Be 'Uninstall MMGamma (1 version(s)) ?'
        }
    }

    It 'Uninstalls the versions selected in the details view' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Uninstall-ManagedModule { }
            $S.Detail = $S.Rows | Where-Object Name -EQ 'MMAlpha'
            $S.Mode = 'details'
            $installs = @($S.Detail.Info.Installations)
            $S.DSelected[$installs[1].ModuleBase] = $true
            $S.DSelected[$installs[2].ModuleBase] = $true
            Request-MMTuiUninstallVersion $S
            $S.Confirm.Prompt | Should -Be "Uninstall MMAlpha $($installs[1].Version), $($installs[2].Version) ?"
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            Should -Invoke Uninstall-ManagedModule -Times 1 -ParameterFilter { $ModuleBase.Count -eq 2 }
        }
    }

    It 'Removes old versions, or says there are none' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Uninstall-OldModuleVersion { }
            Request-MMTuiRemoveOld $S @($S.Rows | Where-Object Name -EQ 'MMGamma')
            $S.Message | Should -Match 'only one version'
            ($S.Rows | Where-Object Name -EQ 'MMAlpha').Selected = $true
            Request-MMTuiRemoveOld $S @($S.Rows | Where-Object Name -EQ 'MMAlpha')
            $S.Confirm.Prompt | Should -Be 'Remove 3 old version(s) of 1 module(s), keeping the newest?'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            Should -Invoke Uninstall-OldModuleVersion -Times 1 -ParameterFilter { $Name -eq 'MMAlpha' -and $Keep -eq 1 }
            @($S.Rows | Where-Object Selected).Count | Should -Be 0
        }
    }

    It 'Returns to the list when the module in the details view is gone' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            $S.Detail = [pscustomobject]@{ Name = 'MMGone' }
            $S.Mode = 'details'
            Sync-MMTuiDetail $S
            $S.Mode | Should -Be 'list'
            $S.Detail | Should -BeNullOrEmpty
            $S.Detail = $S.Rows | Where-Object Name -EQ 'MMAlpha'
            $S.DCursor = 99
            Sync-MMTuiDetail $S
            $S.DCursor | Should -Be ($S.Detail.Info.VersionCount - 1)
        }
    }
}

Describe 'Background operations' {

    It 'Shows progress, notices when it completes, and reports a failure inside the runspace' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Invoke-MMTuiAction $S 'Progressing' -Data @{} -Action {
                Write-Progress -Activity 'Outer' -Status 'half' -PercentComplete 50
                Write-Progress -Activity 'Inner' -Id 2 -ParentId 1 -Status 'child'
                Start-Sleep -Milliseconds 300
                Write-Progress -Activity 'Outer' -Completed
                Start-Sleep -Milliseconds 300
                throw [System.Management.Automation.MethodInvocationException]::new('outer', [Exception]::new('inner failure'))
            }
            $sawProgress = $false
            $deadline = [datetime]::UtcNow.AddSeconds(60)
            while ($S.Task -and [datetime]::UtcNow -lt $deadline) {
                $null = Receive-MMTuiTask $S
                if ($S.Progress -and $S.Progress.Status -eq 'half') { $sawProgress = $true }
                Start-Sleep -Milliseconds 50
            }
            $sawProgress | Should -BeTrue
            $S.Progress | Should -BeNullOrEmpty
            Receive-MMTuiTask $S | Should -BeFalse   # nothing running
            @($S.Log | Where-Object Style -EQ 'Red').Count | Should -BeGreaterThan 0
        }
    }

    It 'Stops a running operation' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Invoke-MMTuiAction $S 'Sleeping' -Data @{} -Action { Start-Sleep -Seconds 60 }
            $S.Task | Should -Not -BeNullOrEmpty
            Stop-MMTuiTask $S
            $S.Task | Should -BeNullOrEmpty
            { Stop-MMTuiTask $S } | Should -Not -Throw
        }
    }
}

Describe 'Terminal UI helpers' {

    It 'Maps colour names and ANSI codes to styles' {
        InModuleScope ModuleManager {
            ConvertTo-MMTuiStyle -Colour 'DarkGreen' | Should -Be 'Green'
            ConvertTo-MMTuiStyle -Colour 'Cyan' | Should -Be 'Cyan'
            ConvertTo-MMTuiStyle -Colour 'Magenta' | Should -Be 'Magenta'
            ConvertTo-MMTuiStyle -Colour 'DarkGray' | Should -Be 'Dim'
            ConvertTo-MMTuiStyle -Colour 'Blue' | Should -BeNullOrEmpty
            ConvertTo-MMTuiStyle -Ansi 90 | Should -Be 'Dim'
            ConvertTo-MMTuiStyle -Ansi 35 | Should -Be 'Magenta'
            ConvertTo-MMTuiStyle -Ansi 34 | Should -BeNullOrEmpty
        }
    }

    It 'Converts verbose, debug and other output for the output pane' {
        InModuleScope ModuleManager {
            (ConvertTo-MMTuiLogEntry ([System.Management.Automation.VerboseRecord]::new('v'))).Style | Should -Be 'Dim'
            (ConvertTo-MMTuiLogEntry ([System.Management.Automation.DebugRecord]::new('d'))).Text | Should -Be 'DEBUG: d'
            (ConvertTo-MMTuiLogEntry ([System.Management.Automation.InformationRecord]::new('plain', 'src'))).Text | Should -Be 'plain'
            (ConvertTo-MMTuiLogEntry ([pscustomobject]@{ A = 1 })).Text | Should -Match 'A'
            (ConvertTo-MMTuiLogEntry $null).Text | Should -Be ''
        }
    }

    It 'Formats elapsed times' {
        InModuleScope ModuleManager {
            Format-MMElapsed ([timespan]::FromSeconds(75)) | Should -Be '1:15'
            Format-MMElapsed ([timespan]::FromMinutes(125)) | Should -Be '2:05:00'
        }
    }
}
