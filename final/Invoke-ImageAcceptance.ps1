param(
    [string]$Image = 'localhost/almalinux9-sbx:dev'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

$containerScript = @'
set -euo pipefail
repository=/mnt/sbx-repository
inventory="$repository/ansible/inventory/hosts.yml"
tools_playbook="$repository/ansible/playbooks/tools.yml"
profile_playbook="$repository/ansible/playbooks/profile.yml"
test -f "$inventory"
test -f "$tools_playbook"
test -f "$profile_playbook"

runuser -u agent -- env \
  HOME=/home/agent \
  SBX_REPOSITORY_ROOT="$repository" \
  bash "$repository/final/scripts/verify-dev.sh" \
    "$repository/.git"
'@

$arguments = @(
    'run',
    '--rm',
    '--user', 'root',
    '--volume', "$repositoryRoot`:/mnt/sbx-repository:ro",
    '--entrypoint', 'bash',
    $Image,
    '-lc',
    $containerScript
)

& podman @arguments
exit $LASTEXITCODE
