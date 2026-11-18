BeforeDiscovery {
    # Reads the source files rather than the loaded module, so private functions are covered too.
    $source = Join-Path $PSScriptRoot '..\..\ModuleManager'
    $functions = foreach ($file in Get-ChildItem -Path (Join-Path $source 'Public'), (Join-Path $source 'Private') -Filter '*.ps1') {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
        foreach ($f in $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            $help = $f.GetHelpContent()
            @{
                Name     = $f.Name
                File     = "$($file.Directory.Name)/$($file.Name)"
                Synopsis = if ($help) { $help.Synopsis } else { $null }
            }
        }
    }
}

Describe 'Function help' {

    It '<Name> (<File>) has a synopsis' -ForEach $functions {
        $Synopsis | Should -Not -BeNullOrEmpty -Because 'every function, public or private, should say what it does'
    }
}
