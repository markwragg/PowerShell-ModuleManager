function ConvertTo-MMTuiKeyInfo {
    <#
    .SYNOPSIS
        Returns the key press for a key named in the terminal UI's help bar or a confirmation (such as
        Space, Esc, / or U), or $null for a name that isn't one key (such as Up/Dn).
    #>
    param([string]$Name)

    switch -Regex ($Name) {
        '^Space$' { return [ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false) }
        '^Enter$' { return [ConsoleKeyInfo]::new([char]13, [ConsoleKey]::Enter, $false, $false, $false) }
        '^Esc$' { return [ConsoleKeyInfo]::new([char]27, [ConsoleKey]::Escape, $false, $false, $false) }
        '^/$' { return [ConsoleKeyInfo]::new('/', [ConsoleKey]::Oem2, $false, $false, $false) }
        '^[A-Za-z]$' {
            return [ConsoleKeyInfo]::new([char]::ToLowerInvariant($Name[0]), [ConsoleKey]$Name.ToUpperInvariant(), $false, $false, $false)
        }
    }
    $null
}
