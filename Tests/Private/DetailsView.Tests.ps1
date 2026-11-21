BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    Reset-FakeModules
    Add-FakeFamily
    New-FakeModule $script:UserRoot 'MMLinked' '1.0.0' -Repository PSGallery -ProjectUri 'https://github.com/example/MMLinked' | Out-Null
    New-FakeModule $script:UserRoot 'MMNeedy' '1.0.0' -Repository PSGallery -Dependency 'MMMissing|[1.0.0, )' | Out-Null
    # Copied in by hand: no install record, and only the newest manifest is read in full.
    New-FakeModule $script:UserRoot 'MMHand' '1.0.0' | Out-Null
    New-FakeModule $script:UserRoot 'MMHand' '2.0.0' -ManifestText "ProjectUri = 'https://example.com/hand'" | Out-Null

    function Get-PlainFrame([hashtable]$State, [int]$Width = 120, [int]$Height = 30) {
        $frame = InModuleScope ModuleManager -Parameters @{ s = $State; w = $Width; h = $Height } { Get-MMTuiFrame $s $w $h }
        $frame -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", '' -replace "$([char]27)\]8;;[^$([char]27)]*$([char]27)\\", ''
    }
    function New-DetailState([string]$Name) {
        InModuleScope ModuleManager -Parameters @{ Options = $TuiOptions; Name = $Name } {
            $s = New-MMTuiState -Options $Options
            Update-MMTuiRows $s; Update-MMTuiVisible $s
            $s.Detail = $s.Rows | Where-Object Name -EQ $Name
            $s.Mode = 'details'
            $s
        }
    }
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Web pages' {

    It 'Reads the project page from the install record, or else the manifest' {
        InModuleScope ModuleManager {
            $linked = @(Get-MMInstalledVersion -Name MMLinked)
            $linked[0].ProjectUri | Should -Be 'https://github.com/example/MMLinked'
            $hand = @(Get-MMInstalledVersion -Name MMHand | Sort-Object ModuleVersion)
            $hand[1].ProjectUri | Should -Be 'https://example.com/hand'
            (Group-MMInstallation -Installation $hand).ProjectUri | Should -Be 'https://example.com/hand'
        }
    }

    It 'Only treats http and https addresses as web pages (<Uri>)' -ForEach @(
        @{ Uri = 'https://github.com/a/b'; Expected = 'https://github.com/a/b' }
        @{ Uri = ' http://example.com/x y '; Expected = 'http://example.com/x%20y' }
        @{ Uri = 'file:///C:/Windows/System32/calc.exe'; Expected = $null }
        @{ Uri = 'C:\Windows\System32\calc.exe'; Expected = $null }
        @{ Uri = 'javascript:alert(1)'; Expected = $null }
        @{ Uri = 'calc.exe'; Expected = $null }
        @{ Uri = ''; Expected = $null }
    ) {
        InModuleScope ModuleManager -Parameters $_ { ConvertTo-MMWebUri $Uri | Should -Be $Expected }
    }

    It 'Refuses to open anything but a web page' {
        InModuleScope ModuleManager {
            Mock Start-Process { }
            { Open-MMWebPage -Uri 'C:\Windows\System32\calc.exe' } | Should -Throw '*not a web address*'
            Should -Invoke Start-Process -Times 0
        }
    }

    It 'Knows the PowerShell Gallery page of <Name> from <Repository> <Source>' -ForEach @(
        @{ Name = 'Az.Storage'; Repository = 'PSGallery'; Source = $null; Expected = 'https://www.powershellgallery.com/packages/Az.Storage' }
        @{ Name = 'Pester'; Repository = 'Gallery2'; Source = 'https://www.powershellgallery.com/api/v2'; Expected = 'https://www.powershellgallery.com/packages/Pester' }
        @{ Name = 'Internal'; Repository = 'Corp'; Source = 'https://nuget.example.com/v2'; Expected = $null }
    ) {
        InModuleScope ModuleManager -Parameters $_ { Get-MMPackagePageUri -Name $Name -Repository $Repository -SourceLocation $Source | Should -Be $Expected }
    }

    It 'Writes a terminal hyperlink only where the terminal supports it, without changing the width' {
        InModuleScope ModuleManager {
            $segments = @(@(' Project: ', 'Dim'), @('https://example.com/x', 'Link', 'https://example.com/x'))
            try {
                $script:MMTuiHyperlink = $false
                $plain = Format-MMTuiLine $segments 40
                $plain | Should -Not -Match "$([char]27)\]8"
                $script:MMTuiHyperlink = $true
                $linked = Format-MMTuiLine $segments 40
                $linked | Should -Match ([regex]::Escape("$([char]27)]8;;https://example.com/x$([char]27)\"))
                ($linked -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", '' -replace "$([char]27)\]8;;[^$([char]27)]*$([char]27)\\", '').Length | Should -Be 40
            }
            finally { $script:MMTuiHyperlink = $false }
        }
    }

    It 'Shows the project and gallery pages, and opens them with P or a click' {
        $s = New-DetailState 'MMLinked'
        $plain = Get-PlainFrame $s
        $plain | Should -Match 'Project: https://github\.com/example/MMLinked   Gallery: https://www\.powershellgallery\.com/packages/MMLinked'
        $plain | Should -Match ' P project page '

        InModuleScope ModuleManager -Parameters @{ s = $s } {
            Mock Open-MMWebPage { }
            Invoke-MMTuiKey -State $s -Key (ConvertTo-MMTuiKeyInfo 'P')
            Should -Invoke Open-MMWebPage -Times 1 -ParameterFilter { $Uri -eq 'https://github.com/example/MMLinked' }
            $s.Message | Should -Match 'Opened https://github\.com/example/MMLinked'

            $gallery = $s.Layout.Links | Where-Object Uri -Match 'powershellgallery'
            Invoke-MMTuiMouse $s ([pscustomobject]@{ Button = 'Left'; X = $gallery.Start + 2; Y = $gallery.Y })
            Should -Invoke Open-MMWebPage -Times 1 -ParameterFilter { $Uri -eq 'https://www.powershellgallery.com/packages/MMLinked' }
            $s.Mode | Should -Be 'details'

            Mock Open-MMWebPage { throw 'no browser' }
            Invoke-MMTuiKey -State $s -Key (ConvertTo-MMTuiKeyInfo 'P')
            $s.Message | Should -Match 'Could not open .*no browser'
        }
    }

    It 'Has no links line or P key for a module without pages' {
        $s = New-DetailState 'MMBeta'
        $plain = Get-PlainFrame $s
        $plain | Should -Not -Match 'Project:|Gallery:'
        $plain | Should -Not -Match ' P (project|gallery) page '
    }
}

Describe 'Version sizes' {

    It 'Formats <Bytes> bytes as <Expected>' -ForEach @(
        @{ Bytes = 512; Expected = '512 B' }
        @{ Bytes = 2048; Expected = '2 KB' }
        @{ Bytes = 14784921; Expected = '14.1 MB' }
        @{ Bytes = 1342177280; Expected = '1.25 GB' }
        @{ Bytes = $null; Expected = '' }
    ) {
        InModuleScope ModuleManager -Parameters $_ { Format-MMSize $Bytes | Should -Be $Expected }
    }

    It 'Sizes each version once, and shows it with the total' {
        $s = New-DetailState 'MMAlpha'
        Get-PlainFrame $s | Should -Not -Match 'version\(s\) installed, '
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            Update-MMTuiDetailSize $s | Should -BeTrue
            Update-MMTuiDetailSize $s | Should -BeFalse
            foreach ($i in @($s.Detail.Info.Installations)) { $s.Sizes[$i.ModuleBase] | Should -BeGreaterThan 0 }
            # A folder that can't be read shows ?, and leaves the total out.
            $s.Sizes[@($s.Detail.Info.Installations)[0].ModuleBase] = $null
        }
        $plain = Get-PlainFrame $s
        $plain | Should -Match '\d+ B  '
        $plain | Should -Match '  \?  '
        $plain | Should -Not -Match 'version\(s\) installed, '
        InModuleScope ModuleManager -Parameters @{ s = $s } { $s.Sizes = @{}; $null = Update-MMTuiDetailSize $s }
        Get-PlainFrame $s | Should -Match '4 version\(s\) installed, \d+ (B|KB)'
    }

    It 'Sizes versions on the other computer, once its runspace is free' {
        $s = New-DetailState 'MMAlpha'
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            Mock Invoke-MMRemote { foreach ($p in $ArgumentList[0]) { [pscustomobject]@{ Path = $p; Bytes = 1234 } } }
            $s.Remote = @{ Name = 'SERVER1' }
            $s.Job = @{ Remote = $true }
            Update-MMTuiDetailSize $s | Should -BeFalse
            Should -Invoke Invoke-MMRemote -Times 0
            $s.Job = $null
            Update-MMTuiDetailSize $s | Should -BeTrue
            Should -Invoke Invoke-MMRemote -Times 1
            @($s.Sizes.Values | Sort-Object -Unique) | Should -Be @(1234)
        }
    }

    It 'Does not ask the other computer again when sizing fails there' {
        $s = New-DetailState 'MMAlpha'
        InModuleScope ModuleManager -Parameters @{ s = $s } {
            Mock Invoke-MMRemote { throw 'connection lost' }
            $s.Remote = @{ Name = 'SERVER1' }
            Update-MMTuiDetailSize $s | Should -BeTrue
            Update-MMTuiDetailSize $s | Should -BeFalse
            Should -Invoke Invoke-MMRemote -Times 1
        }
    }
}

Describe 'Dependency panel' {

    It 'Formats the range <Range> as <Expected>' -ForEach @(
        @{ Range = '[1.0.0]'; Expected = '1.0.0' }
        @{ Range = '[1.0.0, )'; Expected = '>= 1.0.0' }
        @{ Range = '1.0'; Expected = '>= 1.0' }
        @{ Range = '[1.0, 2.0)'; Expected = '>= 1.0, < 2.0' }
        @{ Range = '(, 2.0]'; Expected = '<= 2.0' }
        @{ Range = ''; Expected = '' }
    ) {
        InModuleScope ModuleManager -Parameters $_ { Format-MMVersionRange $Range | Should -Be $Expected }
    }

    It 'Shows what the version under the cursor depends on, and what needs it' {
        $s = New-DetailState 'MMRoll'
        $plain = Get-PlainFrame $s
        $plain | Should -Match ' 2\.0\.0 '
        $plain | Should -Match 'Depends on:  MMRoll\.Core 2\.0\.0, MMRoll\.Extra 1\.0\.0'
        $plain | Should -Match 'Required by: nothing installed'
        $s.DCursor = 1
        Get-PlainFrame $s | Should -Match 'Depends on:  MMRoll\.Core 1\.0\.0, MMRoll\.Extra 1\.0\.0'

        $s = New-DetailState 'MMRoll.Extra'
        Get-PlainFrame $s | Should -Match 'Depends on:  MMRoll\.Core >= 1\.0\.0 \(3\.0\.0\)'
        Get-PlainFrame $s | Should -Match 'Required by: MMRoll 2\.0\.0 / 1\.0\.0'

        # Each version of the core module is needed by the modules whose ranges it's in.
        $s = New-DetailState 'MMRoll.Core'
        $expected = @('MMRoll\.Extra 1\.0\.0', 'MMRoll 2\.0\.0, MMRoll\.Extra 1\.0\.0', 'MMRoll 1\.0\.0, MMRoll\.Extra 1\.0\.0')
        for ($i = 0; $i -lt 3; $i++) {
            $s.DCursor = $i
            $plain = Get-PlainFrame $s
            $plain | Should -Match "Required by: $($expected[$i]) "
            $plain | Should -Match 'Depends on:  nothing'
        }
    }

    It 'Says when a dependency is not found, or not known' {
        Get-PlainFrame (New-DetailState 'MMNeedy') | Should -Match 'Depends on:  MMMissing >= 1\.0\.0 \(not found\)'
        $s = New-DetailState 'MMHand'
        Get-PlainFrame $s | Should -Match 'Depends on:  nothing'
        $s.DCursor = 1
        Get-PlainFrame $s | Should -Match 'Depends on:  not known'
    }

    It 'Wraps a long list over the lines it is given, ending with "and N more"' {
        InModuleScope ModuleManager {
            $items = @(foreach ($i in 1..30) { , @(, @("Module$i 1.0.0", $null)) })
            $lines = @(Format-MMTuiWrappedList -Label ' Required by: ' -Items $items -Width 60 -MaxLines 2)
            $lines.Count | Should -Be 2
            $plain = @($lines | ForEach-Object { $_ -replace "$([char]27)\[[0-9;?]*[a-zA-Z]", '' })
            $plain | ForEach-Object { $_.Length | Should -Be 60 }
            $plain[0] | Should -Match '^ Required by: Module1 1\.0\.0, Module2 1\.0\.0'
            $plain[1] | Should -Match '^              Module\d+ 1\.0\.0, .* and \d+ more\s*$'
            @(Format-MMTuiWrappedList -Label ' x: ' -Items $items[0..1] -Width 60 -MaxLines 3).Count | Should -Be 1
        }
    }

    It 'Fits the details view into the frame (<Width>x<Height>)' -ForEach @(
        @{ Width = 120; Height = 30 }
        @{ Width = 80; Height = 12 }
        @{ Width = 60; Height = 8 }
        @{ Width = 40; Height = 6 }
    ) {
        $s = New-DetailState 'MMRoll.Core'
        InModuleScope ModuleManager -Parameters @{ s = $s } { $null = Update-MMTuiDetailSize $s; $script:MMTuiHyperlink = $true }
        try {
            $lines = @((Get-PlainFrame $s $Width $Height) -split "`r`n")
            $lines.Count | Should -Be $Height
            $lines | ForEach-Object { $_.Length | Should -Be $Width }
        }
        finally { InModuleScope ModuleManager { $script:MMTuiHyperlink = $false } }
    }

    It 'Leaves the panel room when there are many versions, and keeps the cursor on screen' {
        $s = New-DetailState 'MMRoll.Core'
        $s.DCursor = 2
        $plain = Get-PlainFrame $s 120 12
        $s.Layout.DetailRows | Should -BeGreaterThan 0
        $s.DCursor | Should -BeLessThan ($s.DTop + $s.Layout.DetailRows)
        $plain | Should -Match 'Required by: MMRoll 1\.0\.0'
    }
}

Describe 'Unlisted modules and versions' {

    It "Shows the gallery's warning when the whole module is unlisted" {
        $s = New-DetailState 'MMHand'
        $s.Detail.Status = 'Unlisted'
        $s.Detail.Result = [pscustomobject]@{ Repository = 'PSGallery'; Status = 'Unlisted'; UnlistedVersions = @('2.0.0', '1.0.0') }
        $plain = Get-PlainFrame $s 160 30
        $plain | Should -Match ([regex]::Escape("! The owner has unlisted this package. This could mean that the module is deprecated or shouldn't be used anymore."))
        # The panel doesn't repeat it for the version under the cursor.
        $plain | Should -Not -Match 'unlisted this version'
    }

    It 'Marks unlisted versions, and warns about the one under the cursor' {
        $s = New-DetailState 'MMHand'
        $s.Detail.Status = 'UpToDate'
        $s.Detail.Result = [pscustomobject]@{ Repository = 'PSGallery'; Status = 'Found'; UnlistedVersions = @('1.0.0') }
        $s.DCursor = 0
        $plain = Get-PlainFrame $s 160 30
        $plain | Should -Match '1\.0\.0 unlisted'
        $plain | Should -Not -Match '2\.0\.0 unlisted'
        $plain | Should -Not -Match 'The owner has unlisted'
        $s.DCursor = 1
        $plain = Get-PlainFrame $s 160 30
        $plain | Should -Match ([regex]::Escape('Unlisted:    The owner has unlisted this version.'))
        @($plain -split "`r`n").Count | Should -Be 30
    }

    It 'Reports VersionUnlisted when the newest installed version is unlisted and there is nothing newer (<Case>)' -ForEach @(
        @{ Case = 'latest listed is older'; Latest = '2.1.0'; Unlisted = @('2.1.1'); Expected = 'VersionUnlisted' }
        @{ Case = 'same as latest'; Latest = '2.1.1'; Unlisted = @('2.1.1'); Expected = 'VersionUnlisted' }
        @{ Case = 'an update is available'; Latest = '3.0.0'; Unlisted = @('2.1.1'); Expected = 'UpdateAvailable' }
        @{ Case = 'only an older version is unlisted'; Latest = '2.1.1'; Unlisted = @('2.0.0'); Expected = 'UpToDate' }
        @{ Case = 'not checked'; Latest = '2.1.0'; Unlisted = $null; Expected = 'LocalNewer' }
    ) {
        InModuleScope ModuleManager -Parameters $_ {
            $module = [pscustomobject]@{ Version = '2.1.1'; ModuleVersion = [version]'2.1.1'; Prerelease = $null }
            $result = [pscustomobject]@{ Status = 'Found'; ModuleVersion = [version]$Latest; PrereleaseLabel = $null; UnlistedVersions = $Unlisted }
            Get-MMUpdateStatus -Module $module -Result $result | Should -Be $Expected
        }
    }
}
