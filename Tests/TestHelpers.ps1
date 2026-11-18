# Shared helpers for the ModuleManager tests. Dot-source from a BeforeAll block:
#
#   . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
#   Initialize-MMTestEnvironment
#
# The tests build fake module trees in a temporary folder and point PSModulePath at them, so they never
# touch your real modules or the network.

function Import-MMTestModule {
    if (-not $env:BHProjectName) { $env:BHProjectName = 'ModuleManager' }
    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
    Get-Module $env:BHProjectName | Remove-Module -Force -ErrorAction Ignore
    Import-Module (Join-Path $projectRoot $env:BHProjectName) -Force
}

function Initialize-MMTestEnvironment {
    Import-MMTestModule
    $script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) "MMTests_$([guid]::NewGuid().ToString('N'))"
    $script:UserRoot = Join-Path $script:TestRoot 'user'
    $script:OtherRoot = Join-Path $script:TestRoot 'other'
    $script:SavedPath = $env:PSModulePath
}

function Clear-MMTestEnvironment {
    if ($script:SavedPath) { $env:PSModulePath = $script:SavedPath }
    if ($script:TestRoot -and (Test-Path $script:TestRoot)) { Remove-Item $script:TestRoot -Recurse -Force }
    Remove-Module ModuleManager -Force -ErrorAction SilentlyContinue
}

function New-FakeModule {
    <#
        -Dependency takes 'Name|NuGetRange' strings and writes them to PSGetModuleInfo.xml in
        PSResourceGet's format, or PowerShellGet's with -PowerShellGetFormat ('[1.0]' becomes
        RequiredVersion, '[1.0, )' MinimumVersion). -ManifestText is added to the .psd1 as is.
    #>
    param(
        [string]$Root, [string]$Name, [string]$Version, [string]$Prerelease,
        [string[]]$RequiredModules, [string]$Repository, [switch]$Unversioned, [switch]$ObjDate,
        [string[]]$Dependency, [switch]$PowerShellGetFormat, [string]$ManifestText
    )
    $dir = if ($Unversioned) { Join-Path $Root $Name } else { Join-Path (Join-Path $Root $Name) $Version }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $req = ''
    if ($RequiredModules) { $req = "RequiredModules = @($(($RequiredModules | ForEach-Object { "'$_'" }) -join ', '))" }
    $pre = ''
    if ($Prerelease) { $pre = "Prerelease = '$Prerelease'" }
    @"
@{
    # Prerelease = 'commented-out'
    ModuleVersion = '$Version'
    GUID = '$([guid]::NewGuid())'
    Author = 'Test Author'
    Description = 'Fake module $Name'
    $req
    $ManifestText
    PrivateData = @{ PSData = @{ $pre } }
}
"@ | Set-Content -LiteralPath (Join-Path $dir "$Name.psd1")
    if ($Repository) {
        $date = if ($ObjDate) {
            "<Obj N=`"InstalledDate`" RefId=`"1`">`n      <DT>2025-01-02T03:04:05.0000000+00:00</DT>`n    </Obj>"
        }
        else { '<DT N="InstalledDate">2025-01-02T03:04:05.0000000+00:00</DT>' }
        $deps = ''
        if ($PSBoundParameters.ContainsKey('Dependency')) {
            $items = foreach ($d in $Dependency) {
                $depName, $range = $d.Split('|')
                if ($PowerShellGetFormat) {
                    $entries = "<En><S N=`"Key`">Name</S><S N=`"Value`">$depName</S></En>"
                    if ($range -match '^\[([^,\]]+)\]$') { $entries += "<En><S N=`"Key`">RequiredVersion</S><S N=`"Value`">$($Matches[1])</S></En>" }
                    elseif ($range -match '^\[([^,]+),') { $entries += "<En><S N=`"Key`">MinimumVersion</S><S N=`"Value`">$($Matches[1].Trim())</S></En>" }
                    "<Obj RefId=`"9`"><TNRef RefId=`"4`" /><DCT>$entries<En><S N=`"Key`">CanonicalId</S><S N=`"Value`">nuget:$depName</S></En></DCT></Obj>"
                }
                else {
                    "<Obj RefId=`"8`"><TN RefId=`"5`"><T>Microsoft.PowerShell.PSResourceGet.UtilClasses.Dependency</T></TN><Props>" +
                    "<S N=`"Name`">$depName</S><Obj N=`"VersionRange`" RefId=`"9`"><TN RefId=`"6`"><T>NuGet.Versioning.VersionRange</T></TN>" +
                    "<ToString>$range</ToString><Props><Obj N=`"MinVersion`" RefId=`"10`"><ToString>x</ToString></Obj></Props></Obj></Props></Obj>"
                }
            }
            $deps = "<Obj N=`"Dependencies`" RefId=`"7`"><TN RefId=`"4`"><T>System.Array</T></TN><LST>$($items -join '')</LST></Obj>"
        }
        @"
<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
  <Obj RefId="0"><MS>
    <S N="Name">$Name</S>
    <S N="Repository">$Repository</S>
    $date
    $deps
  </MS></Obj>
</Objs>
"@ | Set-Content -LiteralPath (Join-Path $dir 'PSGetModuleInfo.xml')
    }
    $dir
}

function Reset-FakeModules {
    <#
        Builds a fresh fake module tree and points PSModulePath at it:
          user:  MMAlpha 1.0.0, 1.1.0, 2.0.0-beta1 | MMBeta 0.5.0 (unversioned folder)
                 MMDependent 1.0.0 (requires MMGamma) | MMGamma 3.0.0 (PowerShellGet-style date)
          other: MMAlpha 0.9 (no install metadata)
    #>
    if (Test-Path $script:TestRoot) { Remove-Item $script:TestRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $script:UserRoot, $script:OtherRoot -Force | Out-Null
    New-FakeModule $script:UserRoot 'MMAlpha' '1.0.0' -Repository PSGallery | Out-Null
    New-FakeModule $script:UserRoot 'MMAlpha' '1.1.0' -Repository PSGallery | Out-Null
    New-FakeModule $script:UserRoot 'MMAlpha' '2.0.0' -Prerelease 'beta1' -Repository PSGallery | Out-Null
    New-FakeModule $script:OtherRoot 'MMAlpha' '0.9' | Out-Null
    New-FakeModule $script:UserRoot 'MMBeta' '0.5.0' -Unversioned | Out-Null
    New-FakeModule $script:UserRoot 'MMDependent' '1.0.0' -RequiredModules 'MMGamma' -Repository PSGallery | Out-Null
    New-FakeModule $script:UserRoot 'MMGamma' '3.0.0' -Repository PSGallery -ObjDate | Out-Null
    # Stray non-version content should be ignored
    Set-Content -LiteralPath (Join-Path (Join-Path $script:UserRoot 'MMAlpha') 'notes.zip') -Value 'x'
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:UserRoot 'MMAlpha') 'not-a-version') -Force | Out-Null
    $env:PSModulePath = @($script:UserRoot, $script:OtherRoot) -join [IO.Path]::PathSeparator
}

function Add-FakeFamily {
    <#
        Adds a module family to the fake tree, shaped like Az (a rollup that pins exact versions
        of its members, which depend on a shared core module):
          MMRoll 1.0.0       needs MMRoll.Core [1.0.0], MMRoll.Extra [1.0.0]   (PowerShellGet format)
          MMRoll 2.0.0       needs MMRoll.Core [2.0.0], MMRoll.Extra [1.0.0]   (PSResourceGet format)
          MMRoll.Core        1.0.0, 2.0.0, 3.0.0
          MMRoll.Extra 1.0.0 needs MMRoll.Core [1.0.0, )
    #>
    New-FakeModule $script:UserRoot 'MMRoll' '1.0.0' -Repository PSGallery -Dependency 'MMRoll.Core|[1.0.0]', 'MMRoll.Extra|[1.0.0]' -PowerShellGetFormat | Out-Null
    New-FakeModule $script:UserRoot 'MMRoll' '2.0.0' -Repository PSGallery -Dependency 'MMRoll.Core|[2.0.0]', 'MMRoll.Extra|[1.0.0]' | Out-Null
    foreach ($v in '1.0.0', '2.0.0', '3.0.0') {
        New-FakeModule $script:UserRoot 'MMRoll.Core' $v -Repository PSGallery -Dependency @() | Out-Null
    }
    New-FakeModule $script:UserRoot 'MMRoll.Extra' '1.0.0' -Repository PSGallery -Dependency 'MMRoll.Core|[1.0.0, )' | Out-Null
}

function Set-FakeGalleryCache {
    <#
        Prefills the module's repository lookup cache so the update cmdlets work without the network:
        MMAlpha 2.0.0 (update), MMBeta not found, MMDependent 1.0.0 (up to date), MMGamma 2.5.0 (local newer).
    #>
    InModuleScope ModuleManager {
        $script:MMRepositories = @('PSGallery')
        $script:MMGalleryCache = @{}
        $now = [datetime]::UtcNow
        function Add-Fake($name, $pre, $status, $version) {
            $script:MMGalleryCache[(Get-MMCacheKey $name 'PSGallery' $pre)] = [pscustomobject]@{
                RequestedName = $name; Name = $name; Repository = 'PSGallery'; Prerelease = $pre; Status = $status
                Version = $version; ModuleVersion = $(if ($version) { [version]$version }); PrereleaseLabel = $null
                PublishedDate = $now; Error = $null; CachedAt = $now
            }
        }
        Add-Fake 'MMAlpha' $true 'Found' '2.0.0'
        Add-Fake 'MMBeta' $false 'NotFound' $null
        Add-Fake 'MMDependent' $false 'Found' '1.0.0'
        Add-Fake 'MMGamma' $false 'Found' '2.5.0'
    }
}

# Options for New-MMTuiState (pass into InModuleScope with -Parameters @{ Options = $TuiOptions }).
$TuiOptions = @{ Name = '*'; Scope = $null; IncludeSystem = $false; IncludePrerelease = $false; Repository = $null; ThrottleLimit = 4 }
