# Module-level state and settings. Kept in this one file (rather than at the top of the files that use
# them) because the build combines every Public/Private file into a single .psm1, and only script-level
# code in Public/Private survives that.

Set-StrictMode -Version 2.0

# Version sorting: matches runs of digits in prerelease labels so they can be zero-padded.
$script:MMDigitRun = [regex]::new('\d+')

# Module scanning
$script:MMIsWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or ((Test-Path -Path 'variable:IsWindows') -and $IsWindows)

# Patterns applied only to small windows of manifest text (see Find-MMManifestKey).
$script:MMRegex = @{
    Assignment    = [regex]::new('^(\w+)\s*=')
    StringValue   = [regex]::new('^\w+\s*=\s*(?:''((?:[^'']|'''')*)''|"([^"]*)")')
    RequiredBlock = [regex]::new('(?s)^\w+\s*=\s*@\((.*?)\)\s*(?:\r?\n|$)')
    ModuleNameKey = [regex]::new('(?i)ModuleName\s*=\s*[''"]([^''"]+)[''"]')
    HashLiteral   = [regex]::new('(?s)@\{.*?\}')
    QuotedString  = [regex]::new('[''"]([^''"]+)[''"]')
    HashEntry     = [regex]::new('(?i)\b(ModuleName|ModuleVersion|RequiredVersion|MaximumVersion)\s*=\s*[''"]([^''"]+)[''"]')
    # PSGetModuleInfo.xml dependencies: PSResourceGet (Name + NuGet VersionRange) and PowerShellGet (dictionaries).
    XmlObjTag     = [regex]::new('<Obj\b[^>]*?(/?)>|</Obj>')
    # A range already written elsewhere in the file is a reference to it: <Ref N="VersionRange" RefId="13" />.
    XmlRangeDep   = [regex]::new('(?s)<S N="Name">([^<]+)</S>\s*(?:<Nil N="VersionRange"\s*/>|<Ref N="VersionRange" RefId="(\d+)"\s*/>|<Obj N="VersionRange"[^>]*>.*?<ToString>([^<]*)</ToString>)')
    XmlRangeObj   = [regex]::new('(?s)<Obj N="VersionRange" RefId="(\d+)"[^>]*>.*?<ToString>([^<]*)</ToString>')
    XmlDictionary = [regex]::new('(?s)<DCT>(.*?)</DCT>')
    XmlDictEntry  = [regex]::new('<S N="Key">([^<]+)</S>\s*<S N="Value">([^<]*)</S>')
}

$script:MMScanCache = @{}

# Modules loaded in the session, when that isn't this one: the terminal UI runs operations in a
# background runspace and passes the UI session's loaded modules here (see Get-MMLoadedModule).
$script:MMLoadedModule = $null

# Added to a terminal UI confirmation when the operation will run as administrator (see Start-MMTuiElevatedAction).
$script:MMElevationNote = 'Runs as administrator: Windows asks first.'

# Terminal UI operation output: ANSI colour codes (from Write-Host in PowerShell 7) and the colour
# each maps to.
$script:MMAnsiSequence = [regex]::new('\x1b\[[0-9;?]*[A-Za-z]')
$script:MMAnsiColour = [regex]::new('\x1b\[(?:[0-9;]*;)?(3[0-7]|9[0-7])m')

# Parsed version ranges (see ConvertFrom-MMVersionRange).
$script:MMRangeCache = @{}

# Repository lookups. Results are cached for MMCacheLifetime; backend and repositories are detected on first use.
$script:MMGalleryCache = @{}
$script:MMCacheLifetime = [timespan]::FromMinutes(30)
$script:MMBackend = $null
$script:MMRepositories = $null

# Runs inside a background runspace, so it must be fully self-contained.
$script:MMLookupScript = {
    param([string[]]$Names, [string]$Repository, [bool]$Prerelease, [string]$Backend, [hashtable]$Installed)

    foreach ($n in $Names) {
        $found = $null
        $message = $null
        try {
            if ($Backend -eq 'PSResourceGet') {
                $found = Microsoft.PowerShell.PSResourceGet\Find-PSResource -Name $n -Repository $Repository `
                    -Prerelease:$Prerelease -ErrorAction Stop |
                    Sort-Object -Property Version -Descending | Select-Object -First 1
            }
            else {
                # PowerShellGet 1.x (as shipped with Windows PowerShell) has no -AllowPrerelease, so
                # only pass it when it's wanted, and say so when it can't be.
                $find = @{ Name = $n; Repository = $Repository; ErrorAction = 'Stop' }
                if ($Prerelease) {
                    if (-not (Get-Command -Name PowerShellGet\Find-Module).Parameters.ContainsKey('AllowPrerelease')) {
                        throw "This version of PowerShellGet can't find prerelease versions. Install PowerShellGet 2 or Microsoft.PowerShell.PSResourceGet."
                    }
                    $find.AllowPrerelease = $true
                }
                $found = PowerShellGet\Find-Module @find | Select-Object -First 1
            }
        }
        catch { $message = $_.Exception.Message }
        # PowerShellGet 1.x (as shipped with Windows PowerShell) asks to install the NuGet provider
        # if it's missing, which fails where nothing can answer. Say what to do instead.
        if ($message -match 'NuGet provider') {
            $message = 'PowerShellGet needs the NuGet package provider. Install it with ''Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force'', or install Microsoft.PowerShell.PSResourceGet.'
        }

        if ($found) {
            $version = $null
            $pre = $null
            if ($Backend -eq 'PSResourceGet') {
                $version = $found.Version
                $pre = $found.Prerelease
            }
            else {
                $parts = ([string]$found.Version).Split('-', 2)
                $text = $parts[0]
                if ($text -notmatch '\.') { $text = "$text.0" }
                $version = [version]$text
                if ($parts.Count -gt 1) { $pre = $parts[1] }
            }
            if ([string]::IsNullOrEmpty($pre)) { $pre = $null }
            $display = [string]$version
            if ($pre) { $display = "$display-$pre" }

            # Dependencies of the latest version, as 'Name|NuGet range' strings (plain data, so they
            # cross the runspace boundary cleanly).
            $deps = @(foreach ($d in @($found.Dependencies)) {
                    if (-not $d) { continue }
                    if ($Backend -eq 'PSResourceGet') { "$($d.Name)|$($d.VersionRange)" }
                    else {
                        # PowerShellGet gives a hashtable per dependency, with only the keys that apply.
                        $v = @{}
                        foreach ($k in 'Name', 'RequiredVersion', 'MinimumVersion', 'MaximumVersion') {
                            if ($d -is [System.Collections.IDictionary]) { $v[$k] = $d[$k] }
                            elseif ($d.PSObject.Properties[$k]) { $v[$k] = $d.$k }
                        }
                        $range = ''
                        if ($v.RequiredVersion) { $range = "[$($v.RequiredVersion)]" }
                        elseif ($v.MinimumVersion -and $v.MaximumVersion) { $range = "[$($v.MinimumVersion), $($v.MaximumVersion)]" }
                        elseif ($v.MinimumVersion) { $range = "[$($v.MinimumVersion), )" }
                        elseif ($v.MaximumVersion) { $range = "(, $($v.MaximumVersion)]" }
                        "$($v.Name)|$range"
                    }
                })

            [pscustomobject]@{
                RequestedName   = $n
                Name            = $found.Name
                Repository      = $Repository
                Prerelease      = $Prerelease
                Status          = 'Found'
                Version         = $display
                ModuleVersion   = $version
                PrereleaseLabel = $pre
                PublishedDate   = $found.PublishedDate
                Dependencies    = $deps
                Error           = $null
            }
        }
        else {
            $status = 'NotFound'
            if ($message -and $message -notmatch 'could not be found|not found|No match|Unable to find') { $status = 'Error' }

            # Unlisted packages (withdrawn by their publisher) are hidden from searches by name, but
            # can still be found by exact version. Look for the installed version to tell them apart.
            $installedVersion = $null
            if ($Installed) { $installedVersion = [string]$Installed[$n] }
            if ($status -eq 'NotFound' -and $installedVersion) {
                $exact = $null
                try {
                    if ($Backend -eq 'PSResourceGet') {
                        $exact = Microsoft.PowerShell.PSResourceGet\Find-PSResource -Name $n -Version $installedVersion `
                            -Repository $Repository -Prerelease:($installedVersion -match '-') -ErrorAction Stop |
                            Select-Object -First 1
                    }
                    else {
                        $find = @{ Name = $n; RequiredVersion = $installedVersion; Repository = $Repository; ErrorAction = 'Stop' }
                        if ($installedVersion -match '-' -and
                            (Get-Command -Name PowerShellGet\Find-Module).Parameters.ContainsKey('AllowPrerelease')) {
                            $find.AllowPrerelease = $true
                        }
                        $exact = PowerShellGet\Find-Module @find | Select-Object -First 1
                    }
                }
                catch { $exact = $null }
                if ($exact) { $status = 'Unlisted'; $message = $null }
            }

            [pscustomobject]@{
                RequestedName   = $n
                Name            = $n
                Repository      = $Repository
                Prerelease      = $Prerelease
                Status          = $status
                Version         = $null
                ModuleVersion   = $null
                PrereleaseLabel = $null
                PublishedDate   = $null
                Dependencies    = @()
                Error           = $message
            }
        }
    }
}

# Terminal UI (Show-ModuleManager) styles and status display
$script:MMStyle = @{
    Reset     = "$([char]27)[0m"
    Title     = "$([char]27)[48;5;24m$([char]27)[97m"
    TitleBold = "$([char]27)[1m"
    Header    = "$([char]27)[1m$([char]27)[4m"
    Cursor    = "$([char]27)[48;5;238m$([char]27)[97m"
    HelpBar   = "$([char]27)[48;5;236m$([char]27)[37m"
    Key       = "$([char]27)[1m$([char]27)[96m"
    Dim       = "$([char]27)[90m"
    Selected  = "$([char]27)[1m$([char]27)[96m"
    Yellow    = "$([char]27)[93m"
    Green     = "$([char]27)[92m"
    Red       = "$([char]27)[91m"
    Cyan      = "$([char]27)[96m"
    Magenta   = "$([char]27)[95m"
    Bold      = "$([char]27)[1m"
}

# Module family tree markers. Built from code points so the source stays ASCII (Windows PowerShell 5.1
# misreads UTF-8 files without a BOM), and chosen from characters common console fonts have.
$script:MMGlyph = @{
    Collapsed  = [string][char]0x25BA   # right-pointing pointer
    Expanded   = [string][char]0x25BC   # down-pointing triangle
    Branch     = [string][char]0x251C   # box drawing: vertical and right
    LastBranch = [string][char]0x2514   # box drawing: up and right
}

$script:MMStatusDisplay = @{
    UpdateAvailable = @('Update available', 'Yellow')
    UpToDate        = @('Up to date', 'Green')
    LocalNewer      = @('Newer than repo', 'Cyan')
    NotInRepository = @('Not in repo', 'Dim')
    Unlisted        = @('Unlisted', 'Magenta')
    Error          = @('Lookup failed', 'Red')
    Checking        = @('Checking...', 'Dim')
    Unknown         = @('-', 'Dim')
}

$script:MMStatusSortOrder = @{
    UpdateAvailable = 0; Error = 1; Unlisted = 2; LocalNewer = 3; UpToDate = 4; NotInRepository = 5; Checking = 6; Unknown = 7
}
