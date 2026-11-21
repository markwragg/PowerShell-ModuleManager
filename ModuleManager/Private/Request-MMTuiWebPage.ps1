function Request-MMTuiWebPage {
    <#
    .SYNOPSIS
        Opens a web page from the details view in the browser: the one given, or the module's project
        page (or failing that its gallery page).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Opens a web page the user asked for; changes no system state.')]
    param([hashtable]$State, [string]$Uri)
    if (-not $Uri) {
        $links = Get-MMTuiDetailLink $State
        $Uri = $links.Project
        if (-not $Uri) { $Uri = $links.Gallery }
    }
    if (-not $Uri) { Set-MMTuiMessage $State 'This module has no project or gallery page.' 'Yellow'; return }
    try {
        Open-MMWebPage -Uri $Uri
        Set-MMTuiMessage $State "Opened $Uri" 'Green'
    }
    catch { Set-MMTuiMessage $State "Could not open $Uri : $($_.Exception.Message)" 'Red' }
}
