function New-MMTuiState {
    <#
    .SYNOPSIS
        Creates the state of a terminal UI session.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    param([hashtable]$Options)
    @{
        Options      = $Options
        Remote       = $null
        NuGetOffered = $false
        Rows         = @()
        Visible      = @()
        Gallery      = @{}
        Job          = $null
        Mode         = 'list'
        Cursor       = 0
        Top          = 0
        CurrentName  = $null
        Filter       = ''
        Views        = @('All', 'Updates', 'Multiple versions', 'Loaded')
        View         = 0
        Sorts        = @('Name', 'Status', 'Versions', 'Scope')
        Sort         = 0
        Group        = $true
        Expanded     = @{}
        Message      = ''
        MessageStyle = 'Dim'
        Confirm      = $null
        Detail       = $null
        DCursor      = 0
        DTop         = 0
        DSelected    = @{}
        Task         = $null
        Log          = [System.Collections.Generic.List[object]]::new()
        LogOpen      = $false
        LogScroll    = 0
        LogBody      = 0
        Progress     = $null
        Width        = 0
        Height       = 0
        ListHeight   = 0
        Spinner      = 0
        Scanning     = $false
        Quit         = $false
    }
}
