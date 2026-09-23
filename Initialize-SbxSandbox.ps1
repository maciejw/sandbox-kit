    [CmdletBinding()]
param(
    [string]$Name = 'alma9-dev',
    [string]$RepositoryPath = '/d/sandbox-kit'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryPath)) {
    throw 'RepositoryPath must be the guest path of the mounted repository.'
}
$repositoryPath = $RepositoryPath.TrimEnd('/')
$profilePath = "$repositoryPath/configuration/profile"
$inventoryPath = "$repositoryPath/ansible/inventory/hosts.yml"
$toolsPlaybookPath = "$repositoryPath/ansible/playbooks/tools.yml"
$profilePlaybookPath = "$repositoryPath/ansible/playbooks/profile.yml"

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

$commonArguments = @(
    'exec',
    '--user', 'agent',
    '--workdir', $repositoryPath,
    $Name,
    'ansible-playbook',
    '-i', $inventoryPath
)

Write-Host "Installing application tools in sandbox $Name ..."
Invoke-RequiredCommand -Name 'sbx' -CommandArguments ($commonArguments + @($toolsPlaybookPath))

Write-Host "Restoring the developer profile from $profilePath ..."
Invoke-RequiredCommand -Name 'sbx' -CommandArguments ($commonArguments + @(
    $profilePlaybookPath,
    '--extra-vars', "profile_source=$profilePath"
))

Write-Host "Sandbox $Name is initialized."
