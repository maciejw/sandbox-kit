[CmdletBinding()]
param(
    [string[]]$Path
)

$ErrorActionPreference = 'Stop'

$testRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$temporaryRoot = Join-Path $testRoot ('.pester-temp-' + [Guid]::NewGuid().ToString('N'))
$oldTemp = $env:TEMP
$oldTmp = $env:TMP

function Restore-EnvironmentVariable {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$Value
    )

    if ($null -eq $Value) {
        Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue
    }
    else {
        Set-Item -LiteralPath "Env:$Name" -Value $Value
    }
}

$exitCode = 0
try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    $env:TEMP = $temporaryRoot
    $env:TMP = $temporaryRoot

    Import-Module Pester -ErrorAction Stop
    $configuration = New-PesterConfiguration
    $configuration.TestDrive.Enabled = $true
    $configuration.TestRegistry.Enabled = $false
    $configuration.Output.Verbosity = 'Detailed'
    $configuration.Run.PassThru = $true
    $configuration.Run.Path = if ($Path) {
        @($Path | ForEach-Object {
            if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $testRoot $_ }
        })
    }
    else {
        @($testRoot)
    }

    $result = Invoke-Pester -Configuration $configuration
    if ($result.FailedCount -gt 0) { $exitCode = 1 }
}
catch {
    Write-Error $_
    $exitCode = 1
}
finally {
    Restore-EnvironmentVariable -Name TEMP -Value $oldTemp
    Restore-EnvironmentVariable -Name TMP -Value $oldTmp
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $exitCode
