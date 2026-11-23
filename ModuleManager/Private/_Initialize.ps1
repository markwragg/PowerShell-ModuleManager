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

# Show-ModuleManager -WhatIf: set in the terminal UI's session, and in an operation's runspace while
# it runs, so operations only say what they would change (see Test-MMShouldProcess).
$script:MMTuiWhatIf = $false

# Terminal UI operation output: ANSI colour codes (from Write-Host in PowerShell 7) and the colour
# each maps to.
$script:MMAnsiSequence = [regex]::new('\x1b\[[0-9;?]*[A-Za-z]')
$script:MMAnsiColour = [regex]::new('\x1b\[(?:[0-9;]*;)?(3[0-7]|9[0-7])m')

# Parsed version ranges (see ConvertFrom-MMVersionRange).
$script:MMRangeCache = @{}

# Key presses for the key names in the terminal UI's help bar (see ConvertTo-MMTuiKeyInfo).
$script:MMTuiKeyCache = @{}

# Repository lookups. Results are cached for MMCacheLifetime; backend and repositories are detected on first use.
$script:MMGalleryCache = @{}
$script:MMCacheLifetime = [timespan]::FromMinutes(30)
$script:MMBackend = $null
$script:MMRepositories = $null
# Each repository's NuGet v2 API address, or $null where it must be looked up with the package manager.
$script:MMRepositoryApi = @{}

# Runs inside a background runspace, so it must be fully self-contained.
$script:MMLookupScript = {
    param([string[]]$Names, [string]$Repository, [bool]$Prerelease, [string]$Backend, [hashtable]$Installed,
        [string]$ApiUrl, [System.Threading.SemaphoreSlim]$Lock, [hashtable]$InstalledVersions)

    # The runspaces share the console's host, so progress (Invoke-RestMethod's download progress,
    # PowerShellGet's) would be drawn on the console, over the terminal UI. Lookup progress is
    # reported from the results instead (see Wait-MMGalleryLookup).
    $ProgressPreference = 'SilentlyContinue'

    # PowerShellGet goes through PackageManagement, which fails at random when several runspaces use it
    # at once ("A parameter cannot be found that matches parameter name 'Provider'"), so its commands take
    # turns, holding $Lock. Waiting in short steps keeps the lookup stoppable.
    function Invoke-MMLocked([System.Threading.SemaphoreSlim]$Lock, [string]$Backend, [scriptblock]$Command) {
        <#
        .SYNOPSIS
            Runs a PowerShellGet command holding the lookup lock, so only one runs at a time.
        #>
        if (-not $Lock -or $Backend -ne 'PowerShellGet') { return & $Command }
        while (-not $Lock.Wait(200)) { }
        try { & $Command } finally { [void]$Lock.Release() }
    }

    # A NuGet v2 feed (such as the PowerShell Gallery) is queried directly: one request for the whole
    # batch is many times faster than a package manager command per module. If the request fails, the
    # package manager is used instead.
    $api = $null
    if ($ApiUrl) {
        try {
            # Windows PowerShell may not offer TLS 1.2, which the PowerShell Gallery requires.
            $protocols = [Net.ServicePointManager]::SecurityProtocol
            if ([int]$protocols -ne 0 -and -not ($protocols -band [Net.SecurityProtocolType]::Tls12)) {
                [Net.ServicePointManager]::SecurityProtocol = $protocols -bor [Net.SecurityProtocolType]::Tls12
            }
            $latest = 'IsLatestVersion'
            if ($Prerelease) { $latest = 'IsAbsoluteLatestVersion' }
            $ids = @(foreach ($n in $Names) { "Id eq '$($n.Replace("'", "''"))'" }) -join ' or '
            $query = "`$filter=$([uri]::EscapeDataString("$latest and ($ids)"))&`$select=Id,Version,Published,Dependencies"
            $response = @(Invoke-RestMethod -Uri "$ApiUrl/Packages()?$query" -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop)
            $byId = @{}
            foreach ($entry in $response) {
                if ($null -eq $entry) { continue }
                # Anything but feed entries (such as a proxy's web page) means this isn't a v2 feed.
                if ($entry -isnot [System.Xml.XmlElement] -or -not $entry.properties) { throw 'The repository did not return a NuGet v2 feed.' }
                $byId[([string]$entry.properties.Id).ToLowerInvariant()] = $entry.properties
            }
            $api = $byId
        }
        catch { $api = $null }
    }

    # Which installed versions the publisher has unlisted: the feed still returns them when asked by
    # exact version, published on 1900-01-01. One request per batch of versions: the PowerShell
    # Gallery answers 400 (Bad Request) to more than about 22 (Id and version) pairs in one filter,
    # whatever its length, so batches are at most 20, and kept short enough for URL length limits
    # too. $null for a module means it wasn't checked (not a v2 feed, or the
    # request failed); the package managers can't tell, short of a command per version.
    $unlisted = @{}
    if ($null -ne $api -and $InstalledVersions) {
        # The feed's NormalizedVersion: at least three parts, the fourth only if it isn't 0.
        $normalize = {
            param([string]$Text)
            $p = $Text.Split('+')[0].Split('-', 2)
            $numeric = $p[0]; if ($numeric -notmatch '\.') { $numeric = "$numeric.0" }
            $v = $null
            if (-not [version]::TryParse($numeric, [ref]$v)) { return $null }
            $out = "$($v.Major).$($v.Minor).$([Math]::Max(0, $v.Build))"
            if ($v.Revision -gt 0) { $out += ".$($v.Revision)" }
            if ($p.Count -gt 1 -and $p[1]) { $out += "-$($p[1])" }
            $out.ToLowerInvariant()
        }
        $clauses = [System.Collections.Generic.List[object]]::new()
        $failed = @{}
        foreach ($n in $Names) {
            foreach ($text in @($InstalledVersions[$n])) {
                if (-not $text) { continue }
                $norm = & $normalize ([string]$text)
                if (-not $norm) { continue }
                $clauses.Add(@{ Name = $n; Version = [string]$text; Key = "$($n.ToLowerInvariant())|$norm"
                        Filter = "(Id eq '$($n.Replace("'", "''"))' and NormalizedVersion eq '$($norm.Replace("'", "''"))')" })
            }
        }
        $byKey = @{}
        foreach ($c in $clauses) { $byKey[$c.Key] = $c }
        $start = 0
        while ($start -lt $clauses.Count) {
            $chunk = [System.Collections.Generic.List[object]]::new()
            $length = 0
            while ($start -lt $clauses.Count -and $chunk.Count -lt 20 -and ($chunk.Count -eq 0 -or $length + $clauses[$start].Filter.Length -lt 1500)) {
                $chunk.Add($clauses[$start]); $length += $clauses[$start].Filter.Length + 4; $start++
            }
            try {
                $filter = [uri]::EscapeDataString((@($chunk | ForEach-Object { $_.Filter }) -join ' or '))
                $response = @(Invoke-RestMethod -Uri "$ApiUrl/Packages()?`$filter=$filter&`$select=Id,NormalizedVersion,Published" -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop)
                foreach ($c in $chunk) { if (-not $unlisted.ContainsKey($c.Name)) { $unlisted[$c.Name] = [System.Collections.Generic.List[string]]::new() } }
                foreach ($entry in $response) {
                    if ($entry -isnot [System.Xml.XmlElement] -or -not $entry.properties) { continue }
                    $text = $entry.properties.Published
                    if ($text -is [System.Xml.XmlElement]) { $text = $text.InnerText }
                    if ([string]$text -notmatch '^1900-01-01') { continue }
                    $c = $byKey["$(([string]$entry.properties.Id).ToLowerInvariant())|$(([string]$entry.properties.NormalizedVersion).ToLowerInvariant())"]
                    if ($c) { $unlisted[$c.Name].Add($c.Version) }
                }
            }
            catch {
                # Not known for these modules; the rest of the lookup isn't affected.
                foreach ($c in $chunk) { $failed[$c.Name] = $true }
            }
        }
        foreach ($n in @($failed.Keys)) { $unlisted[$n] = $null }
    }

    foreach ($n in $Names) {
        $found = $null
        $message = $null
        $source = $Backend
        $unlistedVersions = $null
        if ($unlisted.ContainsKey($n) -and $null -ne $unlisted[$n]) { $unlistedVersions = [string[]]$unlisted[$n].ToArray() }
        if ($null -ne $api) {
            $source = 'Api'
            $found = $api[$n.ToLowerInvariant()]
        }
        else {
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
                    $found = Invoke-MMLocked $Lock $Backend { PowerShellGet\Find-Module @find | Select-Object -First 1 }
                }
            }
            catch { $message = $_.Exception.Message }
        }
        # PowerShellGet 1.x (as shipped with Windows PowerShell) asks to install the NuGet provider
        # if it's missing, which fails where nothing can answer. Say what to do instead.
        if ($message -match 'NuGet provider') {
            $message = 'PowerShellGet needs the NuGet package provider. Install it with ''Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force'', or install Microsoft.PowerShell.PSResourceGet.'
        }

        if ($found) {
            $version = $null
            $pre = $null
            if ($source -eq 'Api') {
                $name = [string]$found.Id
                # Typed values come as elements (<d:Published m:type="Edm.DateTime">), others as text.
                $text = $found.Published
                if ($text -is [System.Xml.XmlElement]) { $text = $text.InnerText }
                $published = $null
                try { $published = [datetime]::Parse([string]$text, [cultureinfo]::InvariantCulture) } catch { $published = $null }
            }
            else {
                $name = $found.Name
                $published = $found.PublishedDate
            }
            if ($source -eq 'PSResourceGet') {
                $version = $found.Version
                $pre = $found.Prerelease
            }
            else {
                $parts = ([string]$found.Version).Split('+')[0].Split('-', 2)
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
            $rawDeps = @($found.Dependencies)
            # The v2 feed gives them as one string: 'Name:range:framework|Name:range:framework'.
            if ($source -eq 'Api') { $rawDeps = @(([string]$found.Dependencies).Split('|')) }
            $deps = @(foreach ($d in $rawDeps) {
                    if (-not $d) { continue }
                    if ($source -eq 'Api') {
                        $p = ([string]$d).Split(':')
                        if (-not $p[0]) { continue }
                        $range = ''
                        if ($p.Count -gt 1) { $range = $p[1] }
                        "$($p[0])|$range"
                    }
                    elseif ($source -eq 'PSResourceGet') { "$($d.Name)|$($d.VersionRange)" }
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
                Name            = $name
                Repository      = $Repository
                Prerelease      = $Prerelease
                Status          = 'Found'
                Version         = $display
                ModuleVersion   = $version
                PrereleaseLabel = $pre
                PublishedDate   = $published
                Dependencies    = $deps
                Error           = $null
                # Installed versions the publisher has unlisted; $null when that wasn't checked.
                UnlistedVersions = $unlistedVersions
            }
        }
        else {
            $status = 'NotFound'
            if ($message -and $message -notmatch 'could not be found|not found|No match|Unable to find') { $status = 'Error' }

            # Unlisted packages (withdrawn by their publisher) are hidden from searches by name, but
            # can still be found by exact version. Look for the installed version to tell them apart.
            $installedVersion = $null
            if ($Installed) { $installedVersion = [string]$Installed[$n] }
            # The check for unlisted versions may already have found it.
            if ($status -eq 'NotFound' -and $installedVersion -and $unlistedVersions -contains $installedVersion) { $status = 'Unlisted'; $message = $null }
            if ($status -eq 'NotFound' -and $installedVersion) {
                $exact = $null
                try {
                    if ($source -eq 'Api') {
                        # The feed answers 404 for a version it doesn't have, which throws.
                        $key = "Id='$([uri]::EscapeDataString($n.Replace("'", "''")))',Version='$([uri]::EscapeDataString($installedVersion))'"
                        $exact = (Invoke-RestMethod -Uri "$ApiUrl/Packages($key)" -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop).entry
                    }
                    elseif ($Backend -eq 'PSResourceGet') {
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
                        $exact = Invoke-MMLocked $Lock $Backend { PowerShellGet\Find-Module @find | Select-Object -First 1 }
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
                UnlistedVersions = $unlistedVersions
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
    Link      = "$([char]27)[4m$([char]27)[96m"
    WhatIf    = "$([char]27)[1m$([char]27)[43m$([char]27)[30m"
}

# Whether the terminal UI writes web addresses as terminal hyperlinks (OSC 8). Set by Show-ModuleManager
# (see Test-MMTuiHyperlink); off otherwise, as some terminals print the sequence as text.
$script:MMTuiHyperlink = $false

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
    VersionUnlisted = @('Version unlisted', 'Magenta')
    Error          = @('Lookup failed', 'Red')
    Checking        = @('Checking...', 'Dim')
    Unknown         = @('-', 'Dim')
}

$script:MMStatusSortOrder = @{
    UpdateAvailable = 0; Error = 1; Unlisted = 2; VersionUnlisted = 2; LocalNewer = 3; UpToDate = 4; NotInRepository = 5; Checking = 6; Unknown = 7
}

# Terminal UI mouse input on Windows (see Enable-MMTuiMouse and Read-MMTuiInput). Compiled the first time
# the terminal UI turns the mouse on, not when the module loads.
$script:MMConsoleMouseSource = @'
using System;
using System.Runtime.InteropServices;

namespace ModuleManager
{
    public static class ConsoleMouse
    {
        [StructLayout(LayoutKind.Explicit, Size = 20)]
        private struct InputRecord
        {
            [FieldOffset(0)] public ushort EventType;
            // MOUSE_EVENT_RECORD
            [FieldOffset(4)] public short X;
            [FieldOffset(6)] public short Y;
            [FieldOffset(8)] public uint ButtonState;
            [FieldOffset(16)] public uint EventFlags;
            // KEY_EVENT_RECORD
            [FieldOffset(4)] public int KeyDown;
            [FieldOffset(10)] public ushort VirtualKey;
            [FieldOffset(14)] public char Char;
            [FieldOffset(16)] public uint KeyControlState;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetConsoleMode(IntPtr handle, out uint mode);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetConsoleMode(IntPtr handle, uint mode);
        [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "PeekConsoleInputW")]
        private static extern bool PeekConsoleInput(IntPtr handle, [Out] InputRecord[] buffer, uint length, out uint read);
        [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "ReadConsoleInputW")]
        private static extern bool ReadConsoleInput(IntPtr handle, [Out] InputRecord[] buffer, uint length, out uint read);

        private const uint EnableQuickEditMode = 0x40, EnableMouseInput = 0x10, EnableExtendedFlags = 0x80;
        private const ushort KeyEvent = 1, MouseEvent = 2;
        private const uint MouseMoved = 1, DoubleClick = 2, MouseWheeled = 4;
        private const uint AltPressed = 0x1 | 0x2;

        private static uint savedMode;
        private static bool enabled;
        private static uint lastButtons;

        private static IntPtr Input { get { return GetStdHandle(-10); } }

        // Turns on mouse input (and off Quick Edit, which would take the mouse for selecting text).
        public static bool Enable()
        {
            uint mode;
            if (enabled) { return true; }
            if (!GetConsoleMode(Input, out mode)) { return false; }
            uint mouseMode = (mode | EnableMouseInput | EnableExtendedFlags) & ~EnableQuickEditMode;
            if (!SetConsoleMode(Input, mouseMode)) { return false; }
            savedMode = mode;
            enabled = true;
            lastButtons = 0;
            return true;
        }

        public static void Disable()
        {
            if (!enabled) { return; }
            uint mode;
            // Restore only the bits changed, in case something else (such as TreatControlCAsInput) changed others.
            if (GetConsoleMode(Input, out mode))
            {
                uint changed = EnableMouseInput | EnableExtendedFlags | EnableQuickEditMode;
                SetConsoleMode(Input, (mode & ~changed) | (savedMode & changed));
            }
            enabled = false;
        }

        // Looks at the next console input event without waiting for one:
        //   0  nothing waiting
        //   1  a key press, left in the queue for Console.ReadKey, which returns it straight away
        //   2  a mouse button press or wheel turn (read): button is 1 left, 2 right, 3 middle,
        //      4 wheel up, 5 wheel down; x and y are the window column and row
        //   3  another event, such as a key release or a mouse move (read and ignored)
        // Console.KeyAvailable can't be used to find out whether a key is waiting: it discards every
        // event before the next key press, mouse events included.
        public static int Next(out int x, out int y, out int button)
        {
            x = 0; y = 0; button = 0;
            InputRecord[] records = new InputRecord[1];
            uint read;
            if (!PeekConsoleInput(Input, records, 1, out read) || read == 0) { return 0; }
            if (records[0].EventType == KeyEvent && IsKeyPress(records[0])) { return 1; }
            if (!ReadConsoleInput(Input, records, 1, out read) || read == 0) { return 0; }
            InputRecord r = records[0];
            if (r.EventType != MouseEvent) { return 3; }

            uint pressed = 0;
            if ((r.EventFlags & MouseWheeled) != 0)
            {
                button = ((short)(r.ButtonState >> 16)) > 0 ? 4 : 5;
            }
            else
            {
                if (r.EventFlags == 0 || r.EventFlags == DoubleClick || r.EventFlags == MouseMoved)
                {
                    pressed = r.ButtonState & ~lastButtons;
                    lastButtons = r.ButtonState;
                }
                if (r.EventFlags == MouseMoved) { return 3; }
                if ((pressed & 1) != 0) { button = 1; }
                else if ((pressed & 2) != 0) { button = 2; }
                else if ((pressed & 4) != 0) { button = 3; }
                else { return 3; }
            }
            x = r.X; y = r.Y;
            try { x -= Console.WindowLeft; y -= Console.WindowTop; } catch { }
            return 2;
        }

        // Whether Console.ReadKey returns this key event, rather than skipping it (as it does key
        // releases, Shift, Ctrl and the like on their own, and the keys of an Alt+numpad code, whose
        // character comes with the Alt release).
        private static bool IsKeyPress(InputRecord r)
        {
            ushort vk = r.VirtualKey;
            if (r.KeyDown == 0) { return vk == 0x12 && r.Char != 0; }
            if (r.Char == 0 && ((vk >= 0x10 && vk <= 0x12) || vk == 0x14 || vk == 0x90 || vk == 0x91)) { return false; }
            if ((r.KeyControlState & AltPressed) != 0)
            {
                ConsoleKey key = (ConsoleKey)vk;
                if ((key >= ConsoleKey.NumPad0 && key <= ConsoleKey.NumPad9) || key == ConsoleKey.Clear || key == ConsoleKey.Insert ||
                    (key >= ConsoleKey.PageUp && key <= ConsoleKey.DownArrow)) { return false; }
            }
            return true;
        }
    }
}
'@
