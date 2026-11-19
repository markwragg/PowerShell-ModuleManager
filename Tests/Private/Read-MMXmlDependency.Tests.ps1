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

    It 'Resolves version ranges written once and referred back to (as when Az pins the same version of many modules)' {
        # The shape PSResourceGet writes: the first use of a range is written out, later uses refer to it by RefId.
        $text = @'
<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
  <Obj RefId="0">
    <MS>
      <Obj N="Dependencies" RefId="1">
        <TN RefId="1"><T>Microsoft.PowerShell.PSResourceGet.UtilClasses.Dependency[]</T></TN>
        <LST>
          <Obj RefId="2">
            <Props>
              <S N="Name">MMRoll.Core</S>
              <Obj N="VersionRange" RefId="3">
                <TN RefId="2"><T>NuGet.Versioning.VersionRange</T></TN>
                <ToString>[2.0.0, 2.0.0]</ToString>
                <Props><Obj N="MinVersion" RefId="4"><ToString>2.0.0</ToString></Obj></Props>
              </Obj>
            </Props>
          </Obj>
          <Obj RefId="5">
            <Props>
              <S N="Name">MMRoll.Extra</S>
              <Ref N="VersionRange" RefId="3" />
            </Props>
          </Obj>
          <Obj RefId="6">
            <Props>
              <S N="Name">MMRoll.Other</S>
              <Obj N="VersionRange" RefId="7">
                <TNRef RefId="2" />
                <ToString>[1.0.0, )</ToString>
              </Obj>
            </Props>
          </Obj>
          <Obj RefId="8">
            <Props>
              <S N="Name">MMRoll.Last</S>
              <Ref N="VersionRange" RefId="7" />
            </Props>
          </Obj>
        </LST>
      </Obj>
    </MS>
  </Obj>
</Objs>
'@
        InModuleScope ModuleManager -Parameters @{ Text = $text } {
            $result = Read-MMXmlDependency -Text $Text
            @($result | ForEach-Object { "$($_.Name) $($_.VersionRange)" }) | Should -Be @(
                'MMRoll.Core [2.0.0, 2.0.0]', 'MMRoll.Extra [2.0.0, 2.0.0]', 'MMRoll.Other [1.0.0, )', 'MMRoll.Last [1.0.0, )'
            )
        }
    }
}
