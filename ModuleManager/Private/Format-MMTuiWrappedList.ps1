function Format-MMTuiWrappedList {
    <#
    .SYNOPSIS
        Lays out a labelled, comma-separated list over as many terminal UI lines as it needs, up to a limit.

    .DESCRIPTION
        Each item is an array of (text, styleName) segments. Lines after the first are indented to
        line up with the first item. When the items don't fit in $MaxLines lines, the last line
        ends with "and N more". Returns the lines, each built by Format-MMTuiLine at $Width.
    #>
    [OutputType([string[]])]
    param([string]$Label, [object[]]$Items, [int]$Width, [int]$MaxLines = 1)
    if ($MaxLines -lt 1) { return @() }
    $indent = ' ' * $Label.Length
    $room = [Math]::Max(1, $Width - $Label.Length - 1)
    $lengths = @(foreach ($item in $Items) { $n = 0; foreach ($seg in $item) { $n += ([string]$seg[0]).Length }; $n })

    # Greedy: each line holds the items that fit, with ', ' between them.
    $lines = [System.Collections.Generic.List[object]]::new()
    $current = [System.Collections.Generic.List[int]]::new()
    $used = 0
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $need = $lengths[$i]
        if ($current.Count) { $need += 2 }
        if ($current.Count -and $used + $need -gt $room) {
            $lines.Add($current.ToArray()); $current = [System.Collections.Generic.List[int]]::new(); $used = 0; $need = $lengths[$i]
        }
        $current.Add($i); $used += $need
    }
    if ($current.Count) { $lines.Add($current.ToArray()) }

    $more = 0
    if ($lines.Count -gt $MaxLines) {
        $kept = [object[]]::new($MaxLines)
        for ($l = 0; $l -lt $MaxLines; $l++) { $kept[$l] = $lines[$l] }
        $last = [System.Collections.Generic.List[int]]::new([int[]]$kept[-1])
        $shown = 0; foreach ($l in $kept) { $shown += @($l).Count }
        # Drop items from the last line until "and N more" fits after it.
        while ($true) {
            $more = $Items.Count - $shown
            $len = 0; foreach ($j in $last) { $len += $lengths[$j] + 2 }
            if ($len + " and $more more".Length -le $room -or $last.Count -le 1) { break }
            $last.RemoveAt($last.Count - 1); $shown--
        }
        $kept[-1] = $last.ToArray()
        $lines = $kept
    }

    $result = [System.Collections.Generic.List[string]]::new()
    for ($l = 0; $l -lt $lines.Count; $l++) {
        $segments = [System.Collections.Generic.List[object]]::new()
        if ($l -eq 0) { $segments.Add(@($Label, 'Dim')) } else { $segments.Add(@($indent, $null)) }
        $first = $true
        foreach ($j in @($lines[$l])) {
            if (-not $first) { $segments.Add(@(', ', 'Dim')) }
            foreach ($seg in $Items[$j]) { $segments.Add($seg) }
            $first = $false
        }
        if ($more -and $l -eq $lines.Count - 1) { $segments.Add(@(" and $more more", 'Dim')) }
        $result.Add((Format-MMTuiLine $segments.ToArray() $Width))
    }
    $result.ToArray()
}
