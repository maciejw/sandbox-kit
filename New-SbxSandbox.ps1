[CmdletBinding()]
param(
    [string]$Name = 'alma9-dev',
    [int]$Cpus = 2,
    [string]$Memory = '2g',
    [string]$WorkspacePath,
    [switch]$Recreate
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$kitPath = Join-Path $repositoryRoot 'sbx-almalinux9'
if (-not (Test-Path -LiteralPath (Join-Path $kitPath 'spec.yaml') -PathType Leaf)) {
    throw "The sandbox kit was not found: $kitPath"
}
if ([string]::IsNullOrWhiteSpace($WorkspacePath)) {
    $WorkspacePath = Join-Path (Split-Path -Parent $repositoryRoot) 'sandbox-workspace'
}
$WorkspacePath = [IO.Path]::GetFullPath($WorkspacePath)
if (-not (Test-Path -LiteralPath $WorkspacePath -PathType Container)) {
    New-Item -ItemType Directory -Path $WorkspacePath -Force | Out-Null
}

function Invoke-RequiredCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$CommandArguments
    )

    $command = Get-Command $Name -ErrorAction Stop
    & $command.Source @CommandArguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

if ($Recreate) {
    Write-Host "Removing sandbox $Name ..."
    Invoke-RequiredCommand -Name 'sbx' -CommandArguments @('rm', '--force', $Name)
}

Write-Host "Creating sandbox $Name ..."
$provisioningMount = '{0}:ro' -f $repositoryRoot
Invoke-RequiredCommand -Name 'sbx' -CommandArguments @(
    'create', '--name', $Name, '--cpus', $Cpus.ToString(), '--memory', $Memory,
    $kitPath, $WorkspacePath, $provisioningMount
)

Write-Host "Sandbox created. Connect with: sbx run --name $Name"
