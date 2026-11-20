BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Running terminal UI actions as administrator' -Skip:([Environment]::OSVersion.Platform -ne 'Win32NT') {
    # The elevated process is started without -Verb RunAs here, so nothing asks for administrator
    # rights, but everything else is as it would be.
    BeforeAll {
        # Starts the process as Start-Process would, but not elevated (Start-Process itself is mocked).
        InModuleScope ModuleManager {
            function script:Start-TestProcess([string]$FilePath, [string]$ArgumentList) {
                $info = [Diagnostics.ProcessStartInfo]::new($FilePath, $ArgumentList)
                $info.UseShellExecute = $false
                $info.CreateNoWindow = $true
                [Diagnostics.Process]::Start($info)
            }
        }
    }

    BeforeEach { Set-FakeModulePath }

    It 'Runs the action in another PowerShell process and relays its output and progress' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $script:MMLoadedModule = $null
            Mock Start-MMTuiLocalAction { $script:relay = $Data }
            $task = @{}
            Start-MMTuiElevatedAction -Task $task -Options $Options -Data @{ Count = 2 } -Action {
                param($Data, $Options)
                Write-Host "Count $($Data.Count), filter $($Options.Name -join ',')" -ForegroundColor Green
                foreach ($i in 1..$Data.Count) { Write-Progress -Activity 'Testing' -Status "$i of $($Data.Count)" -PercentComplete (50 * $i) }
                Write-Warning 'careful'
                Write-Error 'it broke'
                Write-MMTuiOutput "PID $PID" 'Cyan'
                Write-Host "Modules: $(@(Get-MMInstalledVersion | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ',')"
                Write-Host "Loaded passed in: $(@(Get-MMLoadedModule | Where-Object { $_.Name -eq 'ModuleManager' }).Count)"
            }
            $relay = $script:relay
            Test-Path -LiteralPath (Join-Path $relay.Directory 'request.xml') | Should -BeTrue
            $relay.ArgumentList | Should -Match '-EncodedCommand '

            Mock Start-Process { Start-TestProcess $FilePath $ArgumentList }
            Mock Write-Progress { }
            $lines = @(Wait-MMElevatedAction -Directory $relay.Directory -FilePath $relay.FilePath -ArgumentList $relay.ArgumentList 6>&1 |
                    ForEach-Object { ConvertTo-MMTuiLogEntry $_ })
            Should -Invoke Start-Process -Times 1 -ParameterFilter { $Verb -eq 'RunAs' }
            $text = @($lines | ForEach-Object { $_.Text })
            $text | Should -Contain "Count 2, filter $($Options.Name -join ',')"
            ($lines | Where-Object Text -Like 'Count 2*').Style | Should -Be 'Green'
            $text | Should -Contain 'WARNING: careful'
            ($lines | Where-Object Text -EQ 'ERROR: it broke').Style | Should -Be 'Red'
            # The fake modules: the process uses this session's PSModulePath.
            $text | Should -Contain 'Modules: MMAlpha,MMBeta,MMDependent,MMGamma'
            $text | Should -Contain 'Loaded passed in: 1'
            $other = $lines | Where-Object Text -Like 'PID *'
            $other.Style | Should -Be 'Cyan'
            $other.Text | Should -Not -Be "PID $PID"
            Should -Invoke Write-Progress -ParameterFilter { $Activity -eq 'Testing' -and $Status -eq '2 of 2' -and $PercentComplete -eq 100 }
            Test-Path -LiteralPath $relay.Directory | Should -BeFalse
        }
    }

    It 'Says so when administrator rights are refused, or the process cannot start' {
        InModuleScope ModuleManager {
            $dir = Join-Path ([IO.Path]::GetTempPath()) "MMElevated_$([guid]::NewGuid().ToString('N'))"
            $null = New-Item -ItemType Directory -Path $dir
            Mock Start-Process { throw [InvalidOperationException]::new('wrapped', [ComponentModel.Win32Exception]::new(1223)) }
            $e = Wait-MMElevatedAction -Directory $dir -FilePath 'x' -ArgumentList '' 6>&1 | Select-Object -Last 1 | ForEach-Object { ConvertTo-MMTuiLogEntry $_ }
            $e.Text | Should -Be "ERROR: Administrator rights weren't given, so nothing was changed."
            $e.Style | Should -Be 'Red'
            Test-Path -LiteralPath $dir | Should -BeFalse

            Mock Start-Process { throw 'no such file' }
            $e = Wait-MMElevatedAction -Directory $dir -FilePath 'x' -ArgumentList '' 6>&1 | Select-Object -Last 1 | ForEach-Object { ConvertTo-MMTuiLogEntry $_ }
            $e.Text | Should -Be "ERROR: Couldn't start PowerShell as administrator: no such file"
        }
    }

    It 'Says so when the elevated process ends without finishing' {
        InModuleScope ModuleManager {
            $dir = Join-Path ([IO.Path]::GetTempPath()) "MMElevated_$([guid]::NewGuid().ToString('N'))"
            $null = New-Item -ItemType Directory -Path $dir
            $exe = (Get-Process -Id $PID).Path
            Mock Start-Process { Start-TestProcess $FilePath '-NoProfile -Command exit 3' }
            $e = Wait-MMElevatedAction -Directory $dir -FilePath $exe -ArgumentList '' 6>&1 | Select-Object -Last 1 | ForEach-Object { ConvertTo-MMTuiLogEntry $_ }
            $e.Text | Should -Be 'ERROR: PowerShell running as administrator ended unexpectedly (exit code 3).'
            Test-Path -LiteralPath $dir | Should -BeFalse
        }
    }

    It 'Runs nothing when administrator rights were given as another user' {
        InModuleScope ModuleManager {
            $dir = Join-Path ([IO.Path]::GetTempPath()) "MMElevated_$([guid]::NewGuid().ToString('N'))"
            $null = New-Item -ItemType Directory -Path $dir
            Export-Clixml -LiteralPath (Join-Path $dir 'request.xml') -InputObject @{
                UserSid = 'S-1-5-21-0-0-0-500'; UserName = 'PC\me'; Action = 'Write-Host ran'
            }
            Invoke-MMElevatedAction -Directory $dir
            Test-Path -LiteralPath (Join-Path $dir 'done') | Should -BeTrue
            $line = @(Import-Clixml -LiteralPath (Join-Path $dir '0.xml'))[0][0]
            $line.Text | Should -Match '^ERROR: Administrator rights were given as .+, not PC\\me, so nothing was changed'
            $line.Style | Should -Be 'Red'
            Remove-Item -LiteralPath $dir -Recurse -Force
        }
    }

    It 'Stops the action when asked, and removes the folder' {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions } {
            $dir = Join-Path ([IO.Path]::GetTempPath()) "MMElevated_$([guid]::NewGuid().ToString('N'))"
            $null = New-Item -ItemType Directory -Path $dir
            Export-Clixml -LiteralPath (Join-Path $dir 'request.xml') -Depth 6 -InputObject @{
                UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value; UserName = 'me'
                Action = { Start-Sleep -Seconds 60 }.ToString(); Data = @{}; Options = $Options
                Loaded = @(); Gallery = @{}; PSModulePath = $env:PSModulePath
            }
            $null = New-Item -ItemType File -Path (Join-Path $dir 'stop')
            $elapsed = Measure-Command { Invoke-MMElevatedAction -Directory $dir }
            $elapsed.TotalSeconds | Should -BeLessThan 30
            Test-Path -LiteralPath $dir | Should -BeFalse
            $script:MMLoadedModule = $null
        }
    }
}
