function Update-MMTuiStatus {
    <#
    .SYNOPSIS
        Applies repository lookup results to the terminal UI rows.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes only the in-memory state of the terminal UI or an in-memory object, not system state.')]
    param([hashtable]$State)
    $checking = [bool]$State.Job
    # So Update-MMTuiVisible -IfChanged knows to sort again.
    $State.StatusVersion++
    foreach ($row in $State.Rows) {
        $result = $State.Gallery[$row.Name.ToLowerInvariant()]
        if ($result) {
            $row.Result = $result
            $row.Status = Get-MMUpdateStatus -Module $row.Info -Result $result
            $row.Latest = [string]$result.Version
        }
        elseif ($checking) { $row.Status = 'Checking'; $row.Latest = '' }
        else { $row.Status = 'Unknown'; $row.Latest = '' }
    }
}
