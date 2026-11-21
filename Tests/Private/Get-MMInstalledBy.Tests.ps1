BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    New-Item -ItemType Directory -Path $script:UserRoot -Force | Out-Null
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Get-MMInstalledBy' {

    It 'Recognises the record <InstalledBy> writes' -ForEach @(
        @{ InstalledBy = 'PSResourceGet' }
        @{ InstalledBy = 'PowerShellGet' }
    ) {
        $dir = New-FakeModule $script:UserRoot "MM$InstalledBy" '1.0.0' -Repository PSGallery -InstalledBy $InstalledBy
        InModuleScope ModuleManager -Parameters @{ Dir = $dir; Expected = $InstalledBy } {
            (Read-MMInstallMetadata -ModuleBase $Dir).InstalledBy | Should -Be $Expected
        }
    }

    It 'Falls back to InstalledLocation: <Case>' -ForEach @(
        @{ Case = 'the version folder is PowerShellGet'; Location = 'C:\Modules\MMX\1.0.0\'; Expected = 'PowerShellGet' }
        @{ Case = 'the module root is PSResourceGet'; Location = 'C:\Modules'; Expected = 'PSResourceGet' }
        @{ Case = 'somewhere else is unknown'; Location = 'D:\Elsewhere'; Expected = $null }
        @{ Case = 'none is unknown'; Location = $null; Expected = $null }
    ) {
        InModuleScope ModuleManager -Parameters $_ {
            $base = 'C:\Modules\MMX\1.0.0'
            if (-not $script:MMIsWindows) { $base = $base.Replace('\', '/'); if ($Location) { $Location = $Location.Replace('\', '/') } }
            $text = '<Objs><Obj><MS><S N="Name">MMX</S>'
            if ($Location) { $text += "<S N=`"InstalledLocation`">$([Net.WebUtility]::HtmlEncode($Location))</S>" }
            $text += '</MS></Obj></Objs>'
            Get-MMInstalledBy -Text $text -ModuleBase $base | Should -Be $Expected
        }
    }

    It 'Is unknown for modules without an install record' {
        $dir = New-FakeModule $script:UserRoot 'MMByHand' '1.0.0'
        InModuleScope ModuleManager -Parameters @{ Dir = $dir } {
            (Read-MMInstallMetadata -ModuleBase $Dir).InstalledBy | Should -BeNullOrEmpty
        }
    }
}
