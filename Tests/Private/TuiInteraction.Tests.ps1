BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    # Load it while PSModulePath is still the real one, so Install-PackageProvider can be mocked.
    Import-Module PackageManagement -Global -ErrorAction SilentlyContinue
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
    BeforeEach { Set-FakeModulePath }


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
                    # A click on the Status column header (at 100 wide, from column 83)
                    [pscustomobject]@{ Button = 'Left'; X = 85; Y = 1 }
                    [ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false)
                )) { $script:keys.Enqueue($k) }
            Mock Test-MMInteractiveConsole { $true }
            Mock Write-MMConsole { $script:written.Add($Text) }
            Mock Get-MMConsoleSize { @{ Width = 100; Height = 20 } }
            Mock Read-MMTuiInput { $script:keys.Dequeue() }
            Mock Enable-MMTuiMouse { 'VT' }
            Mock Disable-MMTuiMouse { }
            Mock Start-Sleep { }
            Mock Write-Progress { }

            Show-ModuleManager -NoUpdateCheck:$NoUpdateCheck

            $script:keys.Count | Should -Be 0
            $plain = ($script:written -join '') -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain | Should -Match 'ModuleManager'
            $plain | Should -Match 'MMAlpha'
            $plain | Should -Match 'view: Updates'
            $plain | Should -Match 'sort: Status'
            Should -Invoke Disable-MMTuiMouse -Times 1 -ParameterFilter { $Mode -eq 'VT' }
            if ($NoUpdateCheck) { $plain | Should -Match 'Update check skipped' }
            $script:written[0] | Should -Match '\[\?1049h'        # entered the alternate screen
            $script:written[-1] | Should -Match '\[\?1049l'       # and left it
        }
    }
}

Describe 'Terminal UI keys' {
    BeforeEach { Set-FakeModulePath }


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

    It 'Says why lookups failed when the update check finishes' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            function New-Result($Name, $Status, $Message) {
                [pscustomobject]@{ RequestedName = $Name; Name = $Name; Repository = 'PSGallery'; Prerelease = $false; Status = $Status
                    Version = $null; ModuleVersion = $null; PrereleaseLabel = $null; PublishedDate = $null; Dependencies = @(); Error = $Message; CachedAt = [datetime]::UtcNow }
            }
            foreach ($case in @(
                    @{ Errors = @('no provider', 'no provider'); Expected = '2 lookup\(s\) failed: no provider$' }
                    @{ Errors = @('timed out', 'no provider'); Expected = '2 lookup\(s\) failed, for example: no provider$' }
                )) {
                $s = New-MMTuiState -Options $Options
                Update-MMTuiRows $s
                $job = [pscustomobject]@{ Tasks = @(); Results = [System.Collections.Generic.List[object]]::new(); Pool = $null; Total = 2; Done = 0 }
                $job.Results.Add((New-Result 'MMAlpha' 'Error' $case.Errors[0]))
                $job.Results.Add((New-Result 'MMGamma' 'Error' $case.Errors[1]))
                foreach ($r in $job.Results) { $s.Gallery[$r.RequestedName.ToLowerInvariant()] = $r }
                $s.Job = $job
                $null = Receive-MMTuiLookup $s
                $s.Message | Should -Match $case.Expected
                $s.MessageStyle | Should -Be 'Yellow'
            }
        }
    }

    It 'Offers to install the NuGet provider when lookups failed for want of it, once' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $script:message = "PowerShellGet needs the NuGet package provider. Install it with 'Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force', or install Microsoft.PowerShell.PSResourceGet."
            function Start-FailedCheck($S, [string]$Message = $script:message) {
                $job = [pscustomobject]@{ Tasks = @(); Results = [System.Collections.Generic.List[object]]::new(); Pool = $null; Total = 2; Done = 0 }
                foreach ($n in 'MMAlpha', 'MMGamma') {
                    $r = [pscustomobject]@{ RequestedName = $n; Name = $n; Repository = 'PSGallery'; Prerelease = $false; Status = 'Error'
                        Version = $null; ModuleVersion = $null; PrereleaseLabel = $null; PublishedDate = $null; Dependencies = @(); Error = $Message; CachedAt = [datetime]::UtcNow }
                    $job.Results.Add($r)
                    $S.Gallery[$n.ToLowerInvariant()] = $r
                }
                $S.Job = $job
                $null = Receive-MMTuiLookup $S
            }
            Mock Invoke-MMTuiAction {
                $State.Log.Clear()
                & $Action $Data $State.Options
                if ($OnComplete) { & $OnComplete $State $Data }
            }
            Mock Install-PackageProvider { [pscustomobject]@{ Name = 'NuGet'; Version = [version]'2.8.5.208' } }
            Mock Write-MMTuiOutput { }
            Mock Start-MMTuiLookup { }

            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s
            Start-FailedCheck $s
            $s.Mode | Should -Be 'confirm'
            $s.Confirm.Prompt | Should -Be 'PowerShellGet needs the NuGet provider to check 2 module(s) for updates. Install it for the current user now?'
            Invoke-MMTuiKey $s ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            Should -Invoke Install-PackageProvider -Times 1 -Exactly -ParameterFilter { $Name -eq 'NuGet' -and $Scope -eq 'CurrentUser' -and $Force -and $MinimumVersion -eq '2.8.5.201' }
            Should -Invoke Write-MMTuiOutput -Times 1 -Exactly -ParameterFilter { $Text -eq '  Installed  NuGet provider 2.8.5.208' }
            Should -Invoke Start-MMTuiLookup -Times 1 -Exactly -ParameterFilter { $Refresh }

            # Not again in the same session, even if the check fails the same way.
            Start-FailedCheck $s
            $s.Mode | Should -Be 'list'
            $s.Message | Should -Match 'needs the NuGet package provider'

            # Not for other failures, nor while typing a filter or while an action runs.
            foreach ($case in @(@{ Message = 'timed out' }, @{ Mode = 'filter' }, @{ Task = @{ Title = 'Busy' } })) {
                $s = New-MMTuiState -Options $Options
                Update-MMTuiRows $s
                if ($case.ContainsKey('Mode')) { $s.Mode = $case.Mode }
                if ($case.ContainsKey('Task')) { $s.Task = $case.Task }
                if ($case.ContainsKey('Message')) { Start-FailedCheck $s $case.Message } else { Start-FailedCheck $s }
                $s.Mode | Should -Not -Be 'confirm'
            }
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
        Set-FakeModulePath
        # Run each action here rather than in a background runspace, so its code is covered.
        Mock -ModuleName ModuleManager Invoke-MMTuiAction {
            $State.Log.Clear()
            & $Action $Data $State.Options
            if ($OnComplete) { & $OnComplete $State $Data }
        }
        Mock -ModuleName ModuleManager Write-MMTuiOutput { }
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
            Should -Invoke Write-MMTuiOutput -ParameterFilter { $Text -match 'Updated  MMGamma 3\.0\.0  \(dependency of MMAlpha\)' }
            Should -Invoke Write-MMTuiOutput -Times 1 -Exactly -ParameterFilter { $Text -match 'Failed   MMOther failed' }
            Should -Invoke Write-MMTuiOutput -ParameterFilter { $Text -eq '2 updated (1 as dependencies), 1 failed.' }
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
            Should -Invoke Write-MMTuiOutput -Times 1 -Exactly -ParameterFilter { $Text -like '  Failed *' }
            Should -Invoke Write-MMTuiOutput -Times 1 -Exactly -ParameterFilter { $Text -eq '  Failed   Failed to update MMAlpha: Unable to connect to the remote server' }
            Should -Invoke Write-MMTuiOutput -Times 1 -Exactly -ParameterFilter { $Text -eq '0 updated, 1 failed.' }
        }
    }

    It 'Lists only the first few modules in the update prompt' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Get-MMUntrustedRepository { }
            $rows = foreach ($i in 1..6) { [pscustomobject]@{ Name = "MM$i"; Status = 'UpdateAvailable'; Latest = '2.0'; Info = @{ Version = '1.0'; Installations = @() }; Result = $null } }
            Request-MMTuiUpdate $S $rows
            $S.Confirm.Prompt | Should -Match 'MM4 1\.0 -> 2\.0 and 2 more \? o also removes old versions\.$'
            $S.Confirm.Data.Trust | Should -BeFalse
        }
    }

    It 'Removes the old versions of the updated modules, and their dependencies, with o' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Get-MMUntrustedRepository { }
            Mock Uninstall-OldModuleVersion { }
            Mock Update-ManagedModule {
                [pscustomobject]@{ Name = 'MMAlpha'; Version = '2.0.0'; UpdatedAsDependencyOf = $null }
                [pscustomobject]@{ Name = 'MMGamma'; Version = '3.0.0'; UpdatedAsDependencyOf = 'MMAlpha' }
            }
            ($S.Rows | Where-Object Name -EQ 'MMAlpha').Selected = $true
            Request-MMTuiUpdate $S (Get-MMTuiTarget $S)
            $S.Confirm.Choices | Should -Be 'yo'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('o', [ConsoleKey]::O, $false, $false, $false))

            Should -Invoke Update-ManagedModule -Times 1 -Exactly -ParameterFilter { $Name -eq 'MMAlpha' -and $PassThru -and -not $RemoveOldVersions }
            Should -Invoke Uninstall-OldModuleVersion -Times 1 -Exactly -ParameterFilter {
                $Name.Count -eq 2 -and $Name -contains 'MMAlpha' -and $Name -contains 'MMGamma' -and $Keep -eq 1 -and $Verbose
            }
            @($S.Rows | Where-Object Selected).Count | Should -Be 0
        }
    }

    It "Doesn't remove old versions with y, or when nothing was updated" {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Get-MMUntrustedRepository { }
            Mock Uninstall-OldModuleVersion { }
            Mock Update-ManagedModule { [pscustomobject]@{ Name = 'MMAlpha'; Version = '2.0.0'; UpdatedAsDependencyOf = $null } }
            $alpha = @($S.Rows | Where-Object Name -EQ 'MMAlpha')
            Request-MMTuiUpdate $S $alpha
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            Should -Invoke Update-ManagedModule -Times 1 -Exactly
            Should -Invoke Uninstall-OldModuleVersion -Times 0 -Exactly

            # A failed update keeps its old versions.
            Mock Update-ManagedModule { Write-Error -Message 'Failed to update MMAlpha: boom' -ErrorId 'ModuleManager.UpdateFailed' }
            Request-MMTuiUpdate $S $alpha
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('o', [ConsoleKey]::O, $false, $false, $false))
            Should -Invoke Uninstall-OldModuleVersion -Times 0 -Exactly
            Should -Invoke Write-MMTuiOutput -Times 1 -Exactly -ParameterFilter { $Text -eq '0 updated, 1 failed.' }
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

    It 'Moves the targeted modules to the other scope' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Test-MMIsAdmin { $true }
            Mock Move-ManagedModule { }
            foreach ($n in 'MMAlpha', 'MMGamma') { ($S.Rows | Where-Object Name -EQ $n).Selected = $true }
            ($S.Rows | Where-Object Name -EQ 'MMGamma').Info.Installations[0].Scope = 'AllUsers'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('m', [ConsoleKey]::M, $false, $false, $false))
            $S.Confirm.Prompt | Should -Be 'Move 2 modules (5 versions) to: a AllUsers, c CurrentUser ?'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('c', [ConsoleKey]::C, $false, $false, $false))
            Should -Invoke Move-ManagedModule -Times 1 -ParameterFilter { $ModuleBase.Count -eq 5 -and $Destination -eq 'CurrentUser' }
            @($S.Rows | Where-Object Selected).Count | Should -Be 0
        }
    }

    It 'Moves the version under the cursor in the details view, offering the other scope' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Test-MMIsAdmin { $true }
            Mock Move-ManagedModule { }
            # The fake modules are in the temp folder, which is only under the user's profile on
            # Windows, so say which scope they're in.
            foreach ($r in $S.Rows) { foreach ($i in @($r.Info.Installations)) { $i.Scope = 'CurrentUser' } }
            $S.Detail = $S.Rows | Where-Object Name -EQ 'MMAlpha'
            $S.Mode = 'details'
            $S.DCursor = 1
            $target = @($S.Detail.Info.Installations)[1]
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('m', [ConsoleKey]::M, $false, $false, $false))
            $S.Confirm.Prompt | Should -Be "Move MMAlpha $($target.Version) to AllUsers ?"
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            Should -Invoke Move-ManagedModule -Times 1 -ParameterFilter { "$ModuleBase" -eq $target.ModuleBase -and $Destination -eq 'AllUsers' }

            # A version installed for all users is offered CurrentUser.
            $S.Mode = 'details'
            $target.Scope = 'AllUsers'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('m', [ConsoleKey]::M, $false, $false, $false))
            $S.Confirm.Prompt | Should -Be "Move MMAlpha $($target.Version) to CurrentUser ?"
        }
    }

    It 'Says moving needs root, and skips versions that cannot be moved' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Move-ManagedModule { }
            foreach ($r in $S.Rows) { foreach ($i in @($r.Info.Installations)) { $i.Scope = 'CurrentUser' } }   # as above
            $S.Cursor = [array]::IndexOf(@($S.Visible | ForEach-Object { $_.Name }), 'MMGamma')

            # Outside Windows there's no administrator prompt to ask with.
            Mock Test-MMIsAdmin { $false }
            Mock Test-MMIsWindows { $false }
            Request-MMTuiMove $S
            $S.Mode | Should -Not -Be 'confirm'
            $S.Message | Should -Match 'needs root'

            Mock Test-MMIsAdmin { $true }
            $gamma = ($S.Rows | Where-Object Name -EQ 'MMGamma').Info.Installations[0]
            $gamma.Scope = 'System'
            Request-MMTuiMove $S
            $S.Message | Should -Match "Can't move MMGamma .*ships with PowerShell"

            $S.Cursor = [array]::IndexOf(@($S.Visible | ForEach-Object { $_.Name }), 'MMAlpha')
            @($S.Rows | Where-Object Name -EQ 'MMAlpha').Info.Installations[0].IsLoaded = $true
            Request-MMTuiMove $S
            $S.Confirm.Prompt | Should -Match "Skips 1 version\(s\) that can't be moved\.$"
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            Should -Invoke Move-ManagedModule -Times 1 -ParameterFilter { $ModuleBase.Count -eq 3 }
            Should -Invoke Write-MMTuiOutput -ParameterFilter { $Text -match 'Skipped  MMAlpha .*loaded in this session' }
        }
    }

    It 'Runs operations on modules installed for all users as administrator, on Windows without elevation' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Move-ManagedModule { }
            Mock Uninstall-ManagedModule { }
            Mock Uninstall-OldModuleVersion { }
            Mock Update-ManagedModule { }
            Mock Get-MMUntrustedRepository { }
            Mock Test-MMIsAdmin { $false }
            Mock Test-MMIsWindows { $true }
            foreach ($r in $S.Rows) { foreach ($i in @($r.Info.Installations)) { $i.Scope = 'CurrentUser' } }
            $alpha = $S.Rows | Where-Object Name -EQ 'MMAlpha'
            $y = [ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false)
            $S.Cursor = [array]::IndexOf(@($S.Visible | ForEach-Object { $_.Name }), 'MMAlpha')

            # Moves are always to or from AllUsers.
            Request-MMTuiMove $S
            $S.Confirm.Prompt | Should -BeLike '* Runs as administrator: Windows asks first.'
            Invoke-MMTuiKey $S $y
            Should -Invoke Invoke-MMTuiAction -Times 1 -ParameterFilter { $Elevated }

            # Others only when they change modules installed for all users.
            Request-MMTuiUninstall $S
            $S.Confirm.Prompt | Should -Not -Match 'administrator'
            Invoke-MMTuiKey $S $y
            Should -Invoke Invoke-MMTuiAction -Times 1 -ParameterFilter { $Title -like 'Uninstalling*' -and -not $Elevated }

            @($alpha.Info.Installations)[1].Scope = 'AllUsers'
            Request-MMTuiUninstall $S
            $S.Confirm.Prompt | Should -BeLike '* Runs as administrator: Windows asks first.'
            Invoke-MMTuiKey $S $y
            Should -Invoke Invoke-MMTuiAction -Times 1 -ParameterFilter { $Title -like 'Uninstalling*' -and $Elevated }

            Request-MMTuiRemoveOld $S @($alpha)
            $S.Confirm.Prompt | Should -BeLike '* Runs as administrator: Windows asks first.'
            Invoke-MMTuiKey $S $y
            Should -Invoke Invoke-MMTuiAction -Times 1 -ParameterFilter { $Title -like 'Removing old*' -and $Elevated }

            # Updates install into the newest version's scope.
            $alpha.Status = 'UpdateAvailable'
            $alpha.Latest = '9.0.0'
            @($alpha.Info.Installations)[1].Scope = 'CurrentUser'
            Request-MMTuiUpdate $S @($alpha)
            $S.Confirm.Prompt | Should -Not -Match 'administrator'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('o', [ConsoleKey]::O, $false, $false, $false))
            Should -Invoke Invoke-MMTuiAction -Times 1 -Exactly -ParameterFilter { $Title -like 'Updating*' -and -not $Elevated }

            # Removing old versions afterwards also covers the versions installed now, so it can
            # need administrator rights when the update doesn't.
            @($alpha.Info.Installations)[1].Scope = 'AllUsers'
            Request-MMTuiUpdate $S @($alpha)
            $S.Confirm.Prompt | Should -BeLike '* ? o also removes old versions. o runs as administrator: Windows asks first.'
            Invoke-MMTuiKey $S $y
            Should -Invoke Invoke-MMTuiAction -Times 2 -Exactly -ParameterFilter { $Title -like 'Updating*' -and -not $Elevated }
            Request-MMTuiUpdate $S @($alpha)
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('o', [ConsoleKey]::O, $false, $false, $false))
            Should -Invoke Invoke-MMTuiAction -Times 1 -Exactly -ParameterFilter { $Title -eq 'Updating 1 module(s) and removing old versions' -and $Elevated }

            @($alpha.Info.Installations)[0].Scope = 'AllUsers'
            Request-MMTuiUpdate $S @($alpha)
            $S.Confirm.Prompt | Should -BeLike '* ? o also removes old versions. Runs as administrator: Windows asks first.'
            Invoke-MMTuiKey $S $y
            Should -Invoke Invoke-MMTuiAction -Times 1 -ParameterFilter { $Title -like 'Updating*' -and $Elevated }

            # Already elevated, or remotely, nothing more is needed.
            Mock Test-MMIsAdmin { $true }
            Request-MMTuiRemoveOld $S @($alpha)
            $S.Confirm.Prompt | Should -Not -Match 'administrator'
            Mock Test-MMIsAdmin { $false }
            Test-MMTuiNeedsElevation @{ Remote = @{} } -Always | Should -BeFalse
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

    It 'Keeps versions selected across modules, and uninstalls them together' {
        Add-FakeFamily
        try {
            $s = New-TestState -NoLookup
            InModuleScope ModuleManager -Parameters @{ S = $s } {
                Mock Uninstall-ManagedModule { }
                function Press([char]$Char, [ConsoleKey]$Key) { Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new($Char, $Key, $false, $false, $false)); Update-MMTuiVisible $S }
                function Open([string]$Name) {
                    Set-MMTuiCursor $S ([array]::IndexOf(@($S.Visible | ForEach-Object { $_.Name }), $Name))
                    Press ([char]13) Enter
                }
                $alpha = $S.Rows | Where-Object Name -EQ 'MMAlpha'
                $core = $S.Rows | Where-Object Name -EQ 'MMRoll.Core'

                # Two old versions of MMAlpha, then back to the list and one of MMRoll.Core (a family member).
                Open 'MMAlpha'
                Press ([char]0) DownArrow; Press ' ' Spacebar; Press ' ' Spacebar
                Press ([char]27) Escape
                $S.Mode | Should -Be 'list'
                $S.DSelected.Count | Should -Be 2
                $S.Expanded['mmroll'] = $true; Update-MMTuiVisible $S
                Open 'MMRoll.Core'
                Press ' ' Spacebar
                $S.DSelected.Count | Should -Be 3
                Press ([char]27) Escape

                $plain = (Get-MMTuiFrame $S 140 30) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
                $plain | Should -Match '\|  3 version\(s\) selected'
                $plain | Should -Match '\[-\]\s+MMAlpha'
                $S.Expanded.Remove('mmroll'); Update-MMTuiVisible $S
                $plain = (Get-MMTuiFrame $S 140 30) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
                $plain | Should -Match '\[-\]\s*\S+ MMRoll \(\+2\)'    # a collapsed family with a member's version selected

                # X in the details view of a third module removes all three.
                Open 'MMGamma'
                Press 'x' X
                $S.Confirm.Prompt | Should -Be 'Uninstall 3 versions of 2 modules ?'
                $expected = @(@($alpha.Info.Installations)[1, 2] + @($core.Info.Installations)[0] | ForEach-Object { $_.ModuleBase })
                Press 'y' Y
                Should -Invoke Uninstall-ManagedModule -Times 1 -Exactly -ParameterFilter {
                    @(Compare-Object $ModuleBase $expected).Count -eq 0
                }
                $S.DSelected.Count | Should -Be 0
            }
        }
        finally { Reset-FakeModules; Set-FakeGalleryCache }
    }

    It 'Uninstalls selected modules and selected versions together from the list, and Esc clears both' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Uninstall-ManagedModule { }
            $alpha = $S.Rows | Where-Object Name -EQ 'MMAlpha'
            ($S.Rows | Where-Object Name -EQ 'MMGamma').Selected = $true
            $S.DSelected[@($alpha.Info.Installations)[3].ModuleBase] = $true

            Request-MMTuiUninstall $S
            $S.Confirm.Prompt | Should -Be 'Uninstall 2 versions of 2 modules ?'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('n', [ConsoleKey]::N, $false, $false, $false))

            # The version and the whole module are both selected: it's only removed once.
            $alpha.Selected = $true
            Request-MMTuiUninstall $S
            $S.Confirm.Prompt | Should -Be 'Uninstall 2 modules (5 versions) ?'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('n', [ConsoleKey]::N, $false, $false, $false))

            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new([char]27, [ConsoleKey]::Escape, $false, $false, $false))
            @($S.Rows | Where-Object Selected).Count | Should -Be 0
            $S.DSelected.Count | Should -Be 0
        }
    }

    It 'Forgets selected versions that are no longer installed after a rescan' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            $alpha = $S.Rows | Where-Object Name -EQ 'MMAlpha'
            $S.DSelected[@($alpha.Info.Installations)[1].ModuleBase] = $true
            $S.DSelected['C:\gone\MMOld\1.0'] = $true
            Update-MMTuiRows $S
            @($S.DSelected.Keys) | Should -Be @(@($alpha.Info.Installations)[1].ModuleBase)
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

Describe 'Uninstalling loaded modules' {
    BeforeEach {
        Set-FakeModulePath
        Mock -ModuleName ModuleManager Invoke-MMTuiAction {
            $State.Log.Clear()
            & $Action $Data $State.Options
            if ($OnComplete) { & $OnComplete $State $Data }
        }
        Mock -ModuleName ModuleManager Write-MMTuiOutput { }
        Mock -ModuleName ModuleManager Uninstall-ManagedModule { }
        Mock -ModuleName ModuleManager Uninstall-OldModuleVersion { }
        Mock -ModuleName ModuleManager Remove-MMSessionModule { }
        Mock -ModuleName ModuleManager Get-MMLoadedAssemblyPath { }
    }

    It 'Offers to unload a loaded version: y skips it, f unloads and uninstalls it' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            $alpha = $S.Rows | Where-Object Name -EQ 'MMAlpha'
            $loaded = @($alpha.Info.Installations) | Where-Object Version -EQ '1.0.0'
            $loaded.IsLoaded = $true
            Set-MMTuiCursor $S ([array]::IndexOf(@($S.Visible | ForEach-Object { $_.Name }), 'MMAlpha'))

            Request-MMTuiUninstall $S
            $S.Confirm.Prompt | Should -Be 'Uninstall MMAlpha (4 version(s)) ? MMAlpha 1.0.0 is loaded: y skips it, f unloads it first.'
            $plain = (Get-MMTuiFrame $S 160 20) -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain | Should -Match '\[y/f/N\]'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            Should -Invoke Uninstall-ManagedModule -Times 1 -Exactly -ParameterFilter { $ModuleBase.Count -eq 3 -and $ModuleBase -notcontains $loaded.ModuleBase }
            Should -Invoke Remove-MMSessionModule -Times 0 -Exactly
            Should -Invoke Write-MMTuiOutput -Times 1 -Exactly -ParameterFilter { $Text -like '  Skipped  MMAlpha 1.0.0: it is loaded*press f*' }

            Request-MMTuiUninstall $S
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('f', [ConsoleKey]::F, $false, $false, $false))
            Should -Invoke Remove-MMSessionModule -Times 1 -Exactly -ParameterFilter { $ModuleBase -eq $loaded.ModuleBase }
            Should -Invoke Uninstall-ManagedModule -Times 1 -Exactly -ParameterFilter { $ModuleBase.Count -eq 4 }
        }
    }

    It "Skips a loaded version that can't be unloaded, and says why" {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            $alpha = $S.Rows | Where-Object Name -EQ 'MMAlpha'
            $loaded = @($alpha.Info.Installations) | Where-Object Version -EQ '1.0.0'
            $loaded.IsLoaded = $true
            $script:dll = Join-Path $loaded.ModuleBase 'MMAlpha.dll'
            Mock Get-MMLoadedAssemblyPath { $script:dll }
            Set-MMTuiCursor $S ([array]::IndexOf(@($S.Visible | ForEach-Object { $_.Name }), 'MMAlpha'))

            Request-MMTuiUninstall $S
            $S.Confirm.Prompt | Should -Be "Uninstall MMAlpha (4 version(s)) ? Skips 1 loaded version(s) that can't be unloaded."
            $S.Confirm.Choices | Should -Be 'y'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('f', [ConsoleKey]::F, $false, $false, $false))
            $S.Message | Should -Be 'Cancelled.'
            Request-MMTuiUninstall $S
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            Should -Invoke Uninstall-ManagedModule -Times 1 -Exactly -ParameterFilter { $ModuleBase.Count -eq 3 }
            Should -Invoke Write-MMTuiOutput -Times 1 -Exactly -ParameterFilter { $Text -like '  Skipped  MMAlpha 1.0.0: it is loaded in this session and it has .NET assemblies loaded*new session.' }

            # Only that version, from the details view: there's nothing it can do.
            $S.Mode = 'details'; $S.Detail = $alpha; $S.DSelected = @{ $loaded.ModuleBase = $true }
            Request-MMTuiUninstallVersion $S
            $S.Mode | Should -Be 'details'
            $S.Message | Should -Match "^Can't uninstall MMAlpha 1\.0\.0: .*\.NET assemblies"
        }
    }

    It 'Only offers f when every version is loaded' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            $gamma = $S.Rows | Where-Object Name -EQ 'MMGamma'
            @($gamma.Info.Installations)[0].IsLoaded = $true
            $S.Mode = 'details'; $S.Detail = $gamma; $S.DCursor = 0
            Request-MMTuiUninstallVersion $S
            $S.Confirm.Prompt | Should -Be 'Uninstall MMGamma (1 version(s)) ? MMGamma 3.0.0 is loaded: f unloads it first.'
            $S.Confirm.Choices | Should -Be 'f'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            $S.Message | Should -Be 'Cancelled.'
            Should -Invoke Uninstall-ManagedModule -Times 0 -Exactly
        }
    }

    It 'Offers to unload loaded old versions when removing old versions' {
        $s = New-TestState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            $alpha = $S.Rows | Where-Object Name -EQ 'MMAlpha'
            foreach ($v in '1.0.0', '1.1.0', '0.9') { (@($alpha.Info.Installations) | Where-Object Version -EQ $v).IsLoaded = $true }
            $newest = @($alpha.Info.Installations)[0]
            $newest.IsLoaded = $true    # the newest is kept, so it doesn't matter that it's loaded
            Request-MMTuiRemoveOld $S @($alpha)
            $S.Confirm.Prompt | Should -Be 'Remove 3 old version(s) of 1 module(s), keeping the newest? MMAlpha 1.1.0, MMAlpha 1.0.0 and 1 more is loaded: y skips it, f unloads it first.'
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('f', [ConsoleKey]::F, $false, $false, $false))
            Should -Invoke Remove-MMSessionModule -Times 1 -Exactly -ParameterFilter { $ModuleBase.Count -eq 3 -and $ModuleBase -notcontains $newest.ModuleBase }
            Should -Invoke Uninstall-OldModuleVersion -Times 1 -Exactly

            $script:dll = Join-Path (@($alpha.Info.Installations) | Where-Object Version -EQ '1.0.0').ModuleBase 'x.dll'
            Mock Get-MMLoadedAssemblyPath { $script:dll }
            Request-MMTuiRemoveOld $S @($alpha)
            $S.Confirm.Prompt | Should -Match "Skips 1 loaded version\(s\) that can't be unloaded\.$"
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
            Should -Invoke Remove-MMSessionModule -Times 1 -Exactly    # not again
            Should -Invoke Write-MMTuiOutput -Times 1 -Exactly -ParameterFilter { $Text -like '  Skipped  MMAlpha 1.0.0: *Remove it from a new session.' }
        }
    }
}

Describe 'Unloading modules' {
    BeforeEach { Set-FakeModulePath }


    It 'Says why <Name> cannot be unloaded' -ForEach @(
        @{ Name = 'ModuleManager'; Expected = 'running this UI' }
        @{ Name = 'Microsoft.PowerShell.PSResourceGet'; Expected = 'install and remove modules' }
        @{ Name = 'PowerShellGet'; Expected = 'install and remove modules' }
        @{ Name = 'MMBinary'; Expected = '.NET assemblies' }
    ) {
        InModuleScope ModuleManager -Parameters $_ {
            $base = Join-Path ([IO.Path]::GetTempPath()) "$Name/1.0.0"
            $i = [pscustomobject]@{ Name = $Name; ModuleBase = $base }
            Get-MMUnloadBlocker -Installation $i -AssemblyPath @('C:\elsewhere\x.dll', (Join-Path $base 'lib/MMBinary.dll')) | Should -Match ([regex]::Escape($Expected))
        }
    }

    It 'Allows a script module to be unloaded' {
        InModuleScope ModuleManager {
            Get-MMUnloadBlocker -Installation ([pscustomobject]@{ Name = 'MMScript'; ModuleBase = 'C:\nowhere\MMScript\1.0' }) | Should -BeNullOrEmpty
            @(Get-MMLoadedAssemblyPath).Count | Should -BeGreaterThan 0
        }
    }

    It 'Unloads the modules loaded from the given folders' {
        $base = Join-Path (Join-Path $UserRoot 'MMGamma') '3.0.0'
        Import-Module (Join-Path $base 'MMGamma.psd1') -Global
        try {
            InModuleScope ModuleManager -Parameters @{ Base = $base } {
                @(Remove-MMSessionModule -ModuleBase $Base -Confirm:$false).Count | Should -Be 0
            }
            Get-Module MMGamma | Should -BeNullOrEmpty
        }
        finally { Remove-Module MMGamma -ErrorAction SilentlyContinue }
    }

    It "Reports a module it couldn't unload" {
        $base = Join-Path (Join-Path $UserRoot 'MMGamma') '3.0.0'
        Import-Module (Join-Path $base 'MMGamma.psd1') -Global
        try {
            InModuleScope ModuleManager -Parameters @{ Base = $base } {
                Mock Remove-Module { throw 'in use' }
                $notes = @(Remove-MMSessionModule -ModuleBase $Base -Confirm:$false)
                $notes | Should -HaveCount 1
                $notes[0] | Should -Match '^Could not unload MMGamma 3\.0\.0: in use$'
            }
        }
        finally { Remove-Module MMGamma -ErrorAction SilentlyContinue }
    }
}

Describe 'Background operations' {
    BeforeEach { Set-FakeModulePath }


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
    BeforeEach { Set-FakeModulePath }


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
