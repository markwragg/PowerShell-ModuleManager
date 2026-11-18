@{
    # Defaults for all dependencies
    PSDependOptions  = @{
        Target     = 'CurrentUser'
        Parameters = @{
            # Use a local repository for offline support
            Repository         = 'PSGallery'
            SkipPublisherCheck = $true
        }
    }

    # Common modules
    BuildHelpers     = '2.0.1'
    Pester           = '6.1.0'
    PlatyPS          = '0.12.0'
    psake            = '4.7.4'
    PSDeploy         = '1.0.1'
    PSScriptAnalyzer = '1.25.0'

    # Not used by the build, but the tests mock its commands, so it must be installed
    # (Windows PowerShell doesn't include it).
    'Microsoft.PowerShell.PSResourceGet' = '1.3.1'
}
