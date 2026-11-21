function Get-MMTuiDetailLink {
    <#
    .SYNOPSIS
        Returns the web pages of the module in the details view: @{ Project; Gallery }, either $null.

    .DESCRIPTION
        Project is the module's project page from its install record or manifest; Gallery its page
        in the repository it was installed from, where that has one (the PowerShell Gallery). Both
        are checked with ConvertTo-MMWebUri, so only http and https addresses are returned.
    #>
    param([hashtable]$State)
    $result = @{ Project = $null; Gallery = $null }
    if (-not $State.Detail) { return $result }
    $info = $State.Detail.Info
    if ($info.PSObject.Properties['ProjectUri']) { $result.Project = ConvertTo-MMWebUri $info.ProjectUri }
    foreach ($i in @($info.Installations)) {
        $source = $null
        if ($i.PSObject.Properties['SourceLocation']) { $source = $i.SourceLocation }
        $page = Get-MMPackagePageUri -Name $info.Name -Repository $i.Repository -SourceLocation $source
        if ($page) { $result.Gallery = ConvertTo-MMWebUri $page; break }
    }
    $result
}
