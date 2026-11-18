# Run Pester tests
# Unit tests: verify inputs / outputs / expected execution path
# Misc tests: verify manifest data, check comment-based help exists
Task 'Test' -Depends 'ImportStagingModule' {
    $lines
    $CoverageTarget = 90

    # -Global so code run via InModuleScope (in the module under test's scope) sees this Pester version too,
    # rather than auto-loading a different installed version and clashing with the already-loaded Pester.dll.
    Import-Module -Name 'Pester' -RequiredVersion '6.1.0' -Force -Global

    # Gather test results. Store them in a variable and file
    $CodeFiles = (Get-ChildItem $ENV:BHModulePath -Recurse -Include '*.ps1').FullName
    $TestFilePath = Join-Path -Path $ArtifactFolder -ChildPath $TestFile

    $PesterConfiguration = New-PesterConfiguration
    $PesterConfiguration.Run.Path = $TestScripts.FullName
    $PesterConfiguration.Run.PassThru = $true
    $PesterConfiguration.CodeCoverage.Enabled = $true
    $PesterConfiguration.CodeCoverage.Path = $CodeFiles
    $PesterConfiguration.CodeCoverage.CoveragePercentTarget = $CoverageTarget
    $PesterConfiguration.TestResult.Enabled = $true
    $PesterConfiguration.TestResult.OutputFormat = 'NUnitXml'
    $PesterConfiguration.TestResult.OutputPath = $TestFilePath
    $PesterConfiguration.Output.Verbosity = 'Detailed'

    $TestResults = Invoke-Pester -Configuration $PesterConfiguration

    # Fail build if any tests fail
    if ($TestResults.FailedCount -gt 0) {
        throw "Failed '$($TestResults.FailedCount)' tests, build failed"
    }

    # Pester only reports the coverage target, so fail the build here if coverage drops below it.
    if ($TestResults.CodeCoverage.CoveragePercent -lt $CoverageTarget) {
        throw ("Code coverage is {0:N2}%, below the {1}% target, build failed" -f $TestResults.CodeCoverage.CoveragePercent, $CoverageTarget)
    }

    # Surface the coverage result as a pipeline output variable so a later stage (which runs in a
    # separate, discarded workspace) can apply it to README.md without re-running the tests.
    if ($env:GITHUB_OUTPUT) {
        $CoveragePercent = [math]::floor($TestResults.CodeCoverage.CoveragePercent)

        "CoveragePercent=$CoveragePercent" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
    }
}
