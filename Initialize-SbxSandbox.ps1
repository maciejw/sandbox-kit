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
$profileRepositoryPath = "$repositoryPath/.git"
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

$execArguments = @(
    'exec',
    '--user', 'agent',
    '--workdir', $repositoryPath,
    $Name
)
$commonArguments = $execArguments + @(
    'ansible-playbook',
    '-i', $inventoryPath
)

Write-Host "Installing application tools in sandbox $Name ..."
Invoke-RequiredCommand -Name 'sbx' -CommandArguments ($commonArguments + @($toolsPlaybookPath))

Write-Host "Ensuring the profile repository clone in sandbox $Name ..."
$profileVariables = @{ profile_repository = $profileRepositoryPath } | ConvertTo-Json -Compress
Invoke-RequiredCommand -Name 'sbx' -CommandArguments ($commonArguments + @(
    $profilePlaybookPath,
    '--extra-vars', $profileVariables
))

Write-Host "Stowing the profile from the home clone in sandbox $Name ..."
Invoke-RequiredCommand -Name 'sbx' -CommandArguments ($execArguments + @(
    'stow',
    '--dir', '/home/agent/.dotfiles',
    '--target', '/home/agent',
    '--adopt',
    '--restow',
    'configuration'
))

Write-Host "Sandbox $Name is initialized."
