BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Initialize-MMTestEnvironment
    New-Item -ItemType Directory -Path $script:UserRoot -Force | Out-Null
}

AfterAll {
    Clear-MMTestEnvironment
}

Describe 'Read-MMXmlDependency' {
    # The result is returned as one array (so 'no entry' and 'empty' differ): assign it, don't wrap it in @().

    It 'Reads PSResourceGet dependencies with their version ranges' {
        $dir = New-FakeModule $script:UserRoot 'MMRg' '1.0.0' -Repository PSGallery -Dependency 'MMA|[5.4.0, )', 'MMB|[2.1.0]'
        InModuleScope ModuleManager -Parameters @{ Path = (Join-Path $dir 'PSGetModuleInfo.xml') } {
            $deps = Read-MMXmlDependency -Text ([IO.File]::ReadAllText($Path))
            $deps.Name | Should -Be @('MMA', 'MMB')
            $deps.VersionRange | Should -Be @('[5.4.0, )', '[2.1.0]')
        }
    }

    It 'Reads PowerShellGet dependencies, turning versions into ranges' {
        $dir = New-FakeModule $script:UserRoot 'MMPg' '1.0.0' -Repository PSGallery -Dependency 'MMA|[4.0.2, )', 'MMB|[2.1.0]' -PowerShellGetFormat
        InModuleScope ModuleManager -Parameters @{ Path = (Join-Path $dir 'PSGetModuleInfo.xml') } {
            $deps = Read-MMXmlDependency -Text ([IO.File]::ReadAllText($Path))
            $deps.Name | Should -Be @('MMA', 'MMB')
            $deps.VersionRange | Should -Be @('[4.0.2, )', '[2.1.0]')
        }
    }

    It 'Returns an empty list for an empty Dependencies entry' {
        InModuleScope ModuleManager {
            $result = Read-MMXmlDependency -Text '<Obj RefId="0"><MS><Obj N="Dependencies" RefId="7"><TNRef RefId="2" /><LST /></Obj><S N="Repository">PSGallery</S></MS></Obj>'
            $result -is [array] | Should -BeTrue
            $result.Count | Should -Be 0
            $selfClosing = Read-MMXmlDependency -Text '<MS><Obj N="Dependencies" RefId="7" /></MS>'
            $selfClosing.Count | Should -Be 0
        }
    }

    It 'Returns $null when there is no Dependencies entry, so the manifest is used instead' {
        InModuleScope ModuleManager {
            Read-MMXmlDependency -Text '<Obj RefId="0"><MS><S N="Repository">PSGallery</S></MS></Obj>' | Should -BeNullOrEmpty
            $null -eq (Read-MMXmlDependency -Text '<MS></MS>') | Should -BeTrue
        }
    }

    It 'Ignores dictionaries outside the Dependencies entry' {
        InModuleScope ModuleManager {
            $text = '<MS><Obj N="Includes"><DCT><En><S N="Key">Name</S><S N="Value">NotADep</S></En></DCT></Obj>' +
            '<Obj N="Dependencies" RefId="7"><LST /></Obj></MS>'
            $result = Read-MMXmlDependency -Text $text
            $result.Count | Should -Be 0
        }
    }
}
