BeforeDiscovery {
    # A real PSSession to test with, where available: PowerShell 7 on Windows can open one to a
    # Windows PowerShell process without WinRM being set up.
    $canUseWindowsPowerShell = $IsWindows -and $PSVersionTable.PSEdition -eq 'Core' -and
        (Get-Command New-PSSession).Parameters.ContainsKey('UseWindowsPowerShell')
    # The other edition on this computer, for -Edition: Windows PowerShell from PowerShell 7, or the reverse.
    $otherEdition = if ($PSVersionTable.PSEdition -eq 'Core') { 'Desktop' } else { 'Core' }
    $canUseOtherEdition = ($PSVersionTable.PSEdition -eq 'Desktop' -or $IsWindows) -and $(
        if ($otherEdition -eq 'Desktop') { Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') }
        else { [bool](Get-Command -Name pwsh -CommandType Application -ErrorAction SilentlyContinue) })
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
    Set-FakeGalleryCache

    # A real remote runspace: another PowerShell process, reached through remoting. It's pointed
    # at the fake module tree and given the same fake repository results, so nothing touches the
    # network or the real modules.
    function New-TestRemote {
        $remote = InModuleScope ModuleManager {
            $process = [System.Management.Automation.Runspaces.PowerShellProcessInstance]::new()
            Initialize-MMRemote -Runspace ([runspacefactory]::CreateOutOfProcessRunspace($null, $process)) -Name 'testhost'
        }
        InModuleScope ModuleManager -Parameters @{ Remote = $remote; ModulePath = $env:PSModulePath } {
            $null = Invoke-MMRemote -Remote $Remote -ArgumentList $ModulePath -ScriptBlock {
                param($ModulePath)
                $env:PSModulePath = $ModulePath
                $script:MMRepositories = @('PSGallery')
                $script:MMGalleryCache = @{}
                $now = [datetime]::UtcNow
                foreach ($f in @(@('MMAlpha', $true, 'Found', '2.0.0'), @('MMBeta', $false, 'NotFound', $null), @('MMDependent', $false, 'Found', '1.0.0'), @('MMGamma', $false, 'Found', '2.5.0'))) {
                    $version = $null
                    if ($f[3]) { $version = [version]$f[3] }
                    $script:MMGalleryCache[(Get-MMCacheKey $f[0] 'PSGallery' $f[1])] = [pscustomobject]@{
                        RequestedName = $f[0]; Name = $f[0]; Repository = 'PSGallery'; Prerelease = $f[1]; Status = $f[2]
                        Version = $f[3]; ModuleVersion = $version; PrereleaseLabel = $null; PublishedDate = $now
                        Dependencies = @(); Error = $null; CachedAt = $now
                    }
                }
            }
        }
        $remote
    }
    $script:Remote = New-TestRemote

    function New-RemoteState {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions; Remote = $script:Remote } {
            $s = New-MMTuiState -Options $Options
            $s.Remote = $Remote
            Update-MMTuiRows $s
            Update-MMTuiVisible $s
            $s.ListHeight = 20
            $s
        }
    }

}

AfterAll {
    InModuleScope ModuleManager -Parameters @{ Remote = $script:Remote } { Disconnect-MMRemote $Remote }
    Clear-MMTestEnvironment
}

Describe 'Managing modules on a remote computer' {

    It 'Scans the remote computer, checks its repositories, and says which computer it is' {
        $s = New-RemoteState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            @($S.Rows | ForEach-Object { $_.Name }) | Should -Be @('MMAlpha', 'MMBeta', 'MMDependent', 'MMGamma')
            $alpha = $S.Rows | Where-Object Name -EQ 'MMAlpha'
            $alpha.Info.VersionCount | Should -Be 4
            @($alpha.Info.Installations)[0].ModuleVersion | Should -Be ([version]'2.0.0')

            Start-MMTuiLookup $S
            $S.Job.Total | Should -Be 4
            # The remote runspace runs one command at a time, so actions wait for the check (R doesn't).
            Test-MMTuiBusy $S | Should -BeTrue
            $S.Message | Should -Be 'Wait for the repository check on testhost to finish first.'
            Test-MMTuiBusy $S -AllowLookup | Should -BeFalse
            $deadline = [datetime]::UtcNow.AddSeconds(60)
            while ($S.Job -and [datetime]::UtcNow -lt $deadline) { $null = Receive-MMTuiLookup $S; Start-Sleep -Milliseconds 50 }
            $S.Job | Should -BeNullOrEmpty
            ($S.Rows | Where-Object Name -EQ 'MMAlpha').Status | Should -Be 'UpdateAvailable'
            ($S.Rows | Where-Object Name -EQ 'MMGamma').Status | Should -Be 'LocalNewer'
            $S.Message | Should -Match '^Update check complete: 1 update'

            $title = ((Get-MMTuiFrame $S 120 20) -split "`r`n")[0] -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $title | Should -Match '^ ModuleManager on testhost  4 modules'
        }
    }

    It 'Uninstalls on the remote computer, with its output in the pane, and rescans' {
        try {
            $s = New-RemoteState
            InModuleScope ModuleManager -Parameters @{ S = $s } {
                $alpha = $S.Rows | Where-Object Name -EQ 'MMAlpha'
                $old = @($alpha.Info.Installations) | Where-Object Version -EQ '0.9'
                $S.Mode = 'details'; $S.Detail = $alpha; $S.DSelected[$old.ModuleBase] = $true
                Request-MMTuiUninstallVersion $S
                $S.Confirm.Prompt | Should -Be 'Uninstall MMAlpha 0.9 ?'
                Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('y', [ConsoleKey]::Y, $false, $false, $false))
                $S.Task.OwnsRunspace | Should -BeFalse
                $deadline = [datetime]::UtcNow.AddSeconds(60)
                while ($S.Task -and [datetime]::UtcNow -lt $deadline) { $null = Receive-MMTuiTask $S; Start-Sleep -Milliseconds 50 }

                Test-Path $old.ModuleBase | Should -BeFalse
                @($S.Log | ForEach-Object { $_.Text }) -join "`n" | Should -Match 'Removed MMAlpha 0\.9'
                $S.Message | Should -Match 'done\.$'
                ($S.Rows | Where-Object Name -EQ 'MMAlpha').Info.VersionCount | Should -Be 3
                $S.Remote.Runspace.RunspaceStateInfo.State | Should -Be 'Opened'
            }
        }
        finally { Reset-FakeModules }
    }

    It 'Shows styled lines, warnings, errors and progress from a remote action' {
        $s = New-RemoteState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Invoke-MMTuiAction $S 'Remote action' -Data @{ N = 2 } -Action {
                param($Data, $Options)
                Write-MMTuiOutput "  Updated  N=$($Data.N) filter=$($Options.Name -join ',')" 'Green'
                Write-Warning 'careful'
                Write-Error 'it broke'
                Write-Verbose 'detail' -Verbose
                foreach ($i in 1..$Data.N) { Write-Progress -Activity 'Remote' -Status "$i of $($Data.N)" -PercentComplete (50 * $i); Start-Sleep -Milliseconds 300 }
            }
            $sawProgress = $null
            $deadline = [datetime]::UtcNow.AddSeconds(60)
            while ($S.Task -and [datetime]::UtcNow -lt $deadline) {
                $null = Receive-MMTuiTask $S
                if ($S.Progress) { $sawProgress = $S.Progress.Status }
                Start-Sleep -Milliseconds 20
            }
            $lines = @($S.Log | ForEach-Object { "$($_.Style)|$($_.Text)" })
            $lines | Should -Contain "Green|  Updated  N=2 filter=$($S.Options.Name -join ',')"
            $lines | Should -Contain 'Yellow|WARNING: careful'
            $lines | Should -Contain 'Red|ERROR: it broke'
            $lines | Should -Contain 'Dim|detail'
            $sawProgress | Should -Match '^\d of 2$'
        }
    }

    It 'Checks repository trust on the remote computer before updating' {
        $s = New-RemoteState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Get-MMUntrustedRepository { 'LocalOnly' }    # only this computer's copy is mocked
            ($S.Rows | Where-Object Name -EQ 'MMAlpha').Status = 'UpdateAvailable'
            ($S.Rows | Where-Object Name -EQ 'MMAlpha').Latest = '2.0.0'
            ($S.Rows | Where-Object Name -EQ 'MMAlpha').Result = [pscustomobject]@{ Repository = 'PSGallery' }
            Request-MMTuiUpdate $S @($S.Rows | Where-Object Name -EQ 'MMAlpha')
            $S.Confirm.Prompt | Should -Be 'Update 1 module(s): MMAlpha 2.0.0-beta1 -> 2.0.0 ?'
            Should -Invoke Get-MMUntrustedRepository -Times 0 -Exactly
        }
    }

    It "Doesn't offer to unload a version that's loaded remotely" {
        $s = New-RemoteState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Get-MMLoadedAssemblyPath { }
            $alpha = $S.Rows | Where-Object Name -EQ 'MMAlpha'
            (@($alpha.Info.Installations) | Where-Object Version -EQ '1.0.0').IsLoaded = $true
            $S.Rows | ForEach-Object { $_.Selected = $false }
            $alpha.Selected = $true
            Request-MMTuiUninstall $S
            $S.Confirm.Prompt | Should -Be "Uninstall MMAlpha (4 version(s)) ? Skips 1 loaded version(s) that can't be unloaded."
            $S.Confirm.Data.Blocked[0] | Should -Match "ModuleManager's session on testhost is using it"
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('n', [ConsoleKey]::N, $false, $false, $false))

            Request-MMTuiRemoveOld $S @($alpha)
            $S.Confirm.Prompt | Should -Match "Skips 1 loaded version\(s\) that can't be unloaded\.$"
            Should -Invoke Get-MMLoadedAssemblyPath -Times 0 -Exactly
        }
    }

    It 'Reports failures from the remote computer' {
        $s = New-RemoteState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            { Invoke-MMRemote -Remote $S.Remote -ScriptBlock { throw 'remote boom' } } | Should -Throw 'remote boom'

            $command = Start-MMRemoteCommand -Remote $S.Remote -ScriptBlock { throw 'lookup broke' }
            $S.Job = [pscustomobject]@{ Remote = $true; Command = $command; Total = 4; Done = 0 }
            $deadline = [datetime]::UtcNow.AddSeconds(60)
            while ($S.Job -and [datetime]::UtcNow -lt $deadline) { $null = Receive-MMTuiLookup $S; Start-Sleep -Milliseconds 50 }
            $S.Message | Should -Be 'The repository check on testhost failed: lookup broke'
        }
    }

    It 'Stops a repository check that is still running' {
        $s = New-RemoteState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            $command = Start-MMRemoteCommand -Remote $S.Remote -ScriptBlock { Start-Sleep -Seconds 60 }
            $S.Job = [pscustomobject]@{ Remote = $true; Command = $command; Total = 4; Done = 0 }
            $started = [datetime]::UtcNow
            Stop-MMTuiLookup $S
            $S.Job | Should -BeNullOrEmpty
            ([datetime]::UtcNow - $started).TotalSeconds | Should -BeLessThan 30
            # And the runspace is free again for the next command.
            @(Invoke-MMRemote -Remote $S.Remote -ScriptBlock { 'free' }) | Should -Be @('free')
        }
    }

    It 'Says when a rescan fails' {
        $s = New-RemoteState
        InModuleScope ModuleManager -Parameters @{ S = $s } {
            Mock Update-MMTuiRows { throw 'connection lost' }
            Invoke-MMTuiKey $S ([ConsoleKeyInfo]::new('r', [ConsoleKey]::R, $false, $false, $false))
            $S.Message | Should -Be 'Could not rescan: connection lost'

            Invoke-MMTuiAction $S 'Quick' -Data @{} -Action { 'done' }
            $deadline = [datetime]::UtcNow.AddSeconds(60)
            while ($S.Task -and [datetime]::UtcNow -lt $deadline) { $null = Receive-MMTuiTask $S; Start-Sleep -Milliseconds 50 }
            $S.Message | Should -Be 'Quick - finished, but the rescan failed: connection lost'
        }
    }
}

Describe 'Connecting to a remote computer' {

    It 'Sends the whole module' {
        InModuleScope ModuleManager {
            $source = Get-MMModuleSource
            $source | Should -Match 'function Show-ModuleManager'
            $source | Should -Match 'function Invoke-MMRemote'
            $source | Should -Match 'MMLookupScript'
        }
    }

    It 'Says when ModuleManager cannot start on the remote computer' {
        InModuleScope ModuleManager {
            $process = [System.Management.Automation.Runspaces.PowerShellProcessInstance]::new()
            $runspace = [runspacefactory]::CreateOutOfProcessRunspace($null, $process)
            $runspace.Dispose()
            { Initialize-MMRemote -Runspace $runspace -Name 'gone' } | Should -Throw 'Could not start ModuleManager on gone:*'
        }
    }

    It 'Says when it cannot connect' {
        InModuleScope ModuleManager {
            Mock New-PSSession { throw 'The WinRM client cannot process the request.' }
            { Connect-MMRemote -ComputerName 'nohost' } | Should -Throw 'Could not connect to nohost: The WinRM client cannot process the request.'
        }
    }

    It 'Connects through an existing PSSession, leaving the session as it is' -Skip:(-not $canUseWindowsPowerShell) {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            InModuleScope ModuleManager -Parameters @{ Session = $session } {
                $remote = Connect-MMRemote -Session $Session
                try {
                    $remote.Name | Should -Be $Session.ComputerName
                    [string](Invoke-MMRemote -Remote $remote -ScriptBlock { $PSVersionTable.PSEdition }) | Should -Be 'Desktop'
                    $remote.Runspace | Should -Not -Be $Session.Runspace
                }
                finally { Disconnect-MMRemote $remote }
                $Session.State | Should -Be 'Opened'
            }
        }
        finally { Remove-PSSession $session }
    }

    It 'Connects by computer name, closing the session it opened to get there' -Skip:(-not $canUseWindowsPowerShell) {
        $script:session = New-PSSession -UseWindowsPowerShell
        InModuleScope ModuleManager -Parameters @{ Session = $script:session } {
            $script:testSession = $Session
            Mock New-PSSession { $script:testSession }
            $remote = Connect-MMRemote -ComputerName 'server01' -ConfigurationName 'PowerShell.7' -Credential ([pscredential]::new('user', (ConvertTo-SecureString 'x' -AsPlainText -Force)))
            try {
                $remote.Name | Should -Be 'server01'
                Should -Invoke New-PSSession -Times 1 -Exactly -ParameterFilter { $ComputerName -eq 'server01' -and $Credential.UserName -eq 'user' -and $ConfigurationName -eq 'PowerShell.7' }
                $Session.State | Should -Not -Be 'Opened'
                [string](Invoke-MMRemote -Remote $remote -ScriptBlock { 'still connected' }) | Should -Be 'still connected'
            }
            finally { Disconnect-MMRemote $remote }
        }
    }

    It 'Runs the terminal UI against the remote computer, and disconnects on exit' {
        InModuleScope ModuleManager -Parameters @{ Remote = $script:Remote } {
            $script:testRemote = $Remote
            $script:written = [System.Collections.Generic.List[string]]::new()
            $script:keys = [System.Collections.Generic.Queue[object]]::new()
            $script:keys.Enqueue([ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false))
            Mock Test-MMInteractiveConsole { $true }
            Mock Write-MMConsole { $script:written.Add($Text) }
            Mock Get-MMConsoleSize { @{ Width = 120; Height = 20 } }
            Mock Read-MMTuiKey { $script:keys.Dequeue() }
            Mock Start-Sleep { }
            Mock Write-Progress { }
            Mock Connect-MMRemote { $script:testRemote }
            Mock Disconnect-MMRemote { }

            Show-ModuleManager -ComputerName 'testhost' -ConfigurationName 'PowerShell.7' -NoUpdateCheck

            Should -Invoke Connect-MMRemote -Times 1 -Exactly -ParameterFilter { $ComputerName -eq 'testhost' -and $ConfigurationName -eq 'PowerShell.7' }
            Should -Invoke Disconnect-MMRemote -Times 1 -Exactly
            $plain = ($script:written -join '') -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain | Should -Match 'ModuleManager on testhost'
            $plain | Should -Match 'MMAlpha'
        }
    }

    It 'Explains that it needs a console of its own' {
        Mock -ModuleName ModuleManager Test-MMInteractiveConsole { $false }
        { Show-ModuleManager } | Should -Throw '*does not work inside Enter-PSSession*-ComputerName or -Session*'
    }
}

Describe 'Managing the other PowerShell edition' {

    It 'Connects to the other edition, says which it is, and stops its process on disconnect' -Skip:(-not $canUseOtherEdition) -ForEach @(@{ OtherEdition = $otherEdition }) {
        InModuleScope ModuleManager -Parameters @{ Edition = $OtherEdition } {
            $remote = Connect-MMEdition -Edition $Edition
            try {
                $processId = $remote.Process.Id
                $remote.Process.HasExited | Should -BeFalse
                if ($Edition -eq 'Desktop') { $remote.Name | Should -Match '^Windows PowerShell 5\.1' }
                else { $remote.Name | Should -Match '^PowerShell \d' }
                Invoke-MMRemote -Remote $remote -ScriptBlock { $PSVersionTable.PSEdition } | Should -Be $Edition
                # It has the module paths a new process of that edition gets, not this session's:
                # Windows PowerShell mustn't see PowerShell 7's folders as its own.
                $paths = @(Invoke-MMRemote -Remote $remote -ScriptBlock { $env:PSModulePath -split [IO.Path]::PathSeparator })
                if ($Edition -eq 'Desktop') { @($paths -match '\\PowerShell\\|\\microsoft\.powershell_') | Should -BeNullOrEmpty }
            }
            finally { Disconnect-MMRemote $remote }
            $deadline = [datetime]::UtcNow.AddSeconds(5)
            while ((Get-Process -Id $processId -ErrorAction SilentlyContinue) -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
            Get-Process -Id $processId -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    It 'Says when this is already that edition' {
        InModuleScope ModuleManager {
            if ($script:MMIsWindows) {
                { Connect-MMEdition -Edition $PSVersionTable.PSEdition } | Should -Throw '*run modman without -Edition*'
            }
            else {
                { Connect-MMEdition -Edition 'Desktop' } | Should -Throw '*only available on Windows*'
            }
        }
    }

    It 'Runs the terminal UI against the other edition, and disconnects on exit' {
        InModuleScope ModuleManager -Parameters @{ Remote = $script:Remote } {
            $script:testRemote = $Remote
            $script:written = [System.Collections.Generic.List[string]]::new()
            $script:keys = [System.Collections.Generic.Queue[object]]::new()
            $script:keys.Enqueue([ConsoleKeyInfo]::new('q', [ConsoleKey]::Q, $false, $false, $false))
            Mock Test-MMInteractiveConsole { $true }
            Mock Write-MMConsole { $script:written.Add($Text) }
            Mock Get-MMConsoleSize { @{ Width = 120; Height = 20 } }
            Mock Read-MMTuiKey { $script:keys.Dequeue() }
            Mock Start-Sleep { }
            Mock Write-Progress { }
            Mock Connect-MMEdition { $script:testRemote }
            Mock Connect-MMRemote { }
            Mock Disconnect-MMRemote { }

            Show-ModuleManager -Edition Desktop -NoUpdateCheck

            Should -Invoke Connect-MMEdition -Times 1 -Exactly -ParameterFilter { $Edition -eq 'Desktop' }
            Should -Invoke Connect-MMRemote -Times 0 -Exactly
            Should -Invoke Disconnect-MMRemote -Times 1 -Exactly
            $plain = ($script:written -join '') -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", ''
            $plain | Should -Match 'MMAlpha'
        }
    }
}
