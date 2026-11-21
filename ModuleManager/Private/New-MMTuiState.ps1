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
        # Details view: each version's size in bytes by folder ($null if it couldn't be read; see
        # Update-MMTuiDetailSize), and each version's dependencies (see Get-MMTuiDependencyInfo).
        # Both are cleared when the modules are rescanned.
        Sizes        = @{}
        DepIndex     = $null
        DepInfo      = @{}
        Task         = $null
        Log          = [System.Collections.Generic.List[object]]::new()
        LogOpen      = $false
        LogScroll    = 0
        LogBody      = 0
        Progress     = $null
        Width        = 0
        Height       = 0
        ListHeight   = 0
        # Bumped when row statuses change, and what the visible rows were last worked out from
        # (see Update-MMTuiVisible -IfChanged).
        StatusVersion = 0
        VisibleKey   = $null
        # The lines last drawn (see Write-MMTuiFrame); $null draws the whole screen next time.
        Screen       = $null
        Spinner      = 0
        Scanning     = $false
        Quit         = $false
        # Mouse input (see Enable-MMTuiMouse, Read-MMTuiInput and Invoke-MMTuiMouse): how it arrives,
        # keys read while looking for a mouse report, the last click (for double-clicks), and where
        # the last frame drew what (set by Get-MMTuiFrame).
        Mouse        = $null
        PendingKeys  = [System.Collections.Generic.Queue[object]]::new()
        LastClick    = $null
        Layout       = @{}
    }
}
