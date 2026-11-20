function Get-MMUserIdentity {
    <#
    .SYNOPSIS
        Returns the user this session runs as: @{ Sid; Name }.

    .DESCRIPTION
        Used to check that an action run with administrator rights runs as the same user (see
        Invoke-MMElevatedAction). On Windows, Sid is the user's security identifier; elsewhere it's
        the user ID.
    #>
    if (Test-MMIsWindows) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        return @{ Sid = $identity.User.Value; Name = $identity.Name }
    }
    @{ Sid = [string](& id -u); Name = [Environment]::UserName }
}
