function ConvertTo-MMTuiKeyInfo {
    <#
    .SYNOPSIS
        Returns the key press for a key named in the terminal UI's help bar or a confirmation (such as
        Space, Esc, /, [ or U), or $null for a name that isn't one key (such as Up/Dn).
    #>
    param([string]$Name)

    # Each frame looks up every key in the help bar, so remember them. Letters give the same key
    # whatever their case, so the cache ignoring case is right.
    if ($script:MMTuiKeyCache.ContainsKey($Name)) { return $script:MMTuiKeyCache[$Name] }

    $key = switch -Regex ($Name) {
        '^Space$' { [ConsoleKeyInfo]::new(' ', [ConsoleKey]::Spacebar, $false, $false, $false); break }
        '^Enter$' { [ConsoleKeyInfo]::new([char]13, [ConsoleKey]::Enter, $false, $false, $false); break }
        '^Esc$' { [ConsoleKeyInfo]::new([char]27, [ConsoleKey]::Escape, $false, $false, $false); break }
        '^/$' { [ConsoleKeyInfo]::new('/', [ConsoleKey]::Oem2, $false, $false, $false); break }
        '^\[$' { [ConsoleKeyInfo]::new('[', [ConsoleKey]::Oem4, $false, $false, $false); break }
        '^\]$' { [ConsoleKeyInfo]::new(']', [ConsoleKey]::Oem6, $false, $false, $false); break }
        '^[A-Za-z]$' {
            [ConsoleKeyInfo]::new([char]::ToLowerInvariant($Name[0]), [ConsoleKey]$Name.ToUpperInvariant(), $false, $false, $false); break
        }
    }
    $script:MMTuiKeyCache[$Name] = $key
    $key
}
