function Get-MMTuiFamily {
    <#
    .SYNOPSIS
        Returns the rows an action on a terminal UI row covers (a collapsed family covers all its members).

    .DESCRIPTION
        The rows an action on $Row covers: with grouping on, a family parent whose members aren't
        listed under it stands for the whole family; anything else is just itself.
    #>
    param([hashtable]$State, [object]$Row)
    if ($State.Group -and $Row.Children.Count -and -not $Row.Open) {
        return @(@($Row) + @($Row.Children))
    }
    @($Row)
}
