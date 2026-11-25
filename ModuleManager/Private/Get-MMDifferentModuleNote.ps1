function Get-MMDifferentModuleNote {
    <#
    .SYNOPSIS
        Explains a NotInRepository status that's down to the repository's module of that name being
        a different module (its GUID doesn't match); $null for any other status.
    #>
    param([string]$Name, [string]$Status, [object]$Result)
    if ($Status -ne 'NotInRepository' -or -not $Result -or $Result.Status -ne 'Found') { return $null }
    "The $Name module in $($Result.Repository) is a different module with the same name (its GUID doesn't match)."
}
