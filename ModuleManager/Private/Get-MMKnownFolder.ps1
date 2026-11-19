function Get-MMKnownFolder {
    <#
    .SYNOPSIS
        Returns the current user's Documents folder or the Program Files folder.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)][ValidateSet('Documents', 'ProgramFiles')][string]$Name)
    if ($Name -eq 'Documents') { return [Environment]::GetFolderPath('MyDocuments') }
    $env:ProgramFiles
}
