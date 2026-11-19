function Get-MMLoadedAssemblyPath {
    <#
    .SYNOPSIS
        Returns the file paths of the .NET assemblies loaded in this session.
    #>
    foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
        if ($assembly.IsDynamic) { continue }
        $location = $null
        try { $location = $assembly.Location } catch { Write-Debug $_ }
        if ($location) { $location }
    }
}
