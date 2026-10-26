[CmdletBinding()]
param(
    [string]$Image = 'localhost/almalinux9-sbx:dev',
    [string]$ArchivePath
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$dockerfilePath = Join-Path $repositoryRoot 'images/almalinux9/Dockerfile'
if (-not (Test-Path -LiteralPath $dockerfilePath -PathType Leaf)) {
    throw "The sandbox Dockerfile was not found: $dockerfilePath"
}

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path $repositoryRoot 'almalinux9-sbx-dev.tar'
}
elseif (-not [IO.Path]::IsPathRooted($ArchivePath)) {
    $ArchivePath = Join-Path $repositoryRoot $ArchivePath
}
$ArchivePath = [IO.Path]::GetFullPath($ArchivePath)
New-Item -ItemType Directory -Path (Split-Path -Parent $ArchivePath) -Force | Out-Null

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

Write-Host "Building $Image ..."
Invoke-RequiredCommand -Name 'podman' -CommandArguments @(
    'build', '--format', 'docker', '-f', $dockerfilePath, '-t', $Image, $repositoryRoot
)

Write-Host "Exporting $Image to $ArchivePath ..."
Invoke-RequiredCommand -Name 'podman' -CommandArguments @(
    'save', '--format', 'docker-archive', '--output', $ArchivePath, $Image
)

Write-Host 'Loading the image into the SBX image store ...'
Invoke-RequiredCommand -Name 'sbx' -CommandArguments @('template', 'load', $ArchivePath)

Write-Host "SBX image ready: $Image"
