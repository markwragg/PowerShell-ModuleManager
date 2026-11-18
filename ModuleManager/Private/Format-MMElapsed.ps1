function Format-MMElapsed {
    <#
    .SYNOPSIS
        Formats a duration as m:ss (or h:mm:ss).
    #>
    param([timespan]$Elapsed)
    if ($Elapsed.TotalHours -ge 1) { return '{0}:{1:mm\:ss}' -f [int][Math]::Floor($Elapsed.TotalHours), $Elapsed }
    '{0}:{1:ss}' -f [int][Math]::Floor($Elapsed.TotalMinutes), $Elapsed
}
