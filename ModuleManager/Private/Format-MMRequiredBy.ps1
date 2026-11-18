function Format-MMRequiredBy {
    <#
    .SYNOPSIS
        Joins the modules that need a version into a short list for messages ("A; B; C and 12 more").
    #>
    param([string[]]$RequiredBy, [int]$Limit = 3)
    $list = @($RequiredBy | Select-Object -Unique)
    if ($list.Count -le $Limit) { return $list -join '; ' }
    "$(($list | Select-Object -First $Limit) -join '; ') and $($list.Count - $Limit) more"
}
