function Get-MMLoadedModule {
    <#
    .SYNOPSIS
        Returns the modules loaded in the session being managed.

    .DESCRIPTION
        The modules loaded in the session being managed. Normally that's this session, but the
        terminal UI runs operations in a background runspace and sets $script:MMLoadedModule
        there to the UI session's modules, so loaded modules are still protected.
    #>
    if ($null -ne $script:MMLoadedModule) { return $script:MMLoadedModule }
    Get-Module -All
}
