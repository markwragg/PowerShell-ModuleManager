function Get-MMConsoleSize {
    <#
    .SYNOPSIS
        Returns the size the terminal UI draws at: @{ Width; Height }.

    .DESCRIPTION
        One less than the window width (writing to the last column can scroll some consoles), and
        at least 39 x 8 so the layout still fits in a tiny window.
    #>
    @{
        Width  = [Math]::Max(40, [Console]::WindowWidth) - 1
        Height = [Math]::Max(8, [Console]::WindowHeight)
    }
}
