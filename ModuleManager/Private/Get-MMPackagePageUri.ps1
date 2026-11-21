function Get-MMPackagePageUri {
    <#
    .SYNOPSIS
        Returns the web page of a module in the repository it was installed from, if there is one.

    .DESCRIPTION
        Only the PowerShell Gallery is known to have a page per package, so other repositories
        return $null. The repository is recognised by its name (PSGallery) or by its address.
    #>
    [OutputType([string])]
    param([string]$Name, [string]$Repository, [string]$SourceLocation)
    if (-not $Name) { return $null }
    if ($Repository -eq 'PSGallery' -or $SourceLocation -match '^https?://(www\.)?powershellgallery\.com(/|$)') {
        return "https://www.powershellgallery.com/packages/$([uri]::EscapeDataString($Name))"
    }
    $null
}
