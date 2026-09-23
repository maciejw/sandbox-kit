#!/usr/bin/env bash
# Image and developer-runtime acceptance; no application scaffolding or API requests.
set -euo pipefail

profile_source=${1:?Usage: verify-dev.sh <mounted-profile-source-directory>}
[[ -d $profile_source ]] || { echo "Profile source is not a directory: $profile_source" >&2; exit 1; }
: "${HOME:?HOME must be set}"
repository_root=${SBX_REPOSITORY_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}
repository_root=$(realpath -e -- "$repository_root")
inventory="$repository_root/ansible/inventory/hosts.yml"
tools_playbook="$repository_root/ansible/playbooks/tools.yml"
profile_playbook="$repository_root/ansible/playbooks/profile.yml"
[[ ! -e "$repository_root/config" ]] || {
  echo 'Personal configuration was copied into the repository source.' >&2
  exit 1
}
[[ ! -e /opt/sbx-tools && ! -e /opt/dotnet ]] || {
  echo 'Application tools or tarball runtime state was copied under /opt.' >&2
  exit 1
}
export PATH="$HOME/.local/bin:$HOME/.dotnet/tools:/usr/local/bin:/usr/bin:/bin:$PATH"
export DOTNET_ROOT="$HOME/.local/share/sbx-tools/dotnet/current"
export NPM_CONFIG_PREFIX="$HOME/.local"

ansible-playbook --version | grep -Fq 'core 2.21.4'
ansible-lint --version | grep -Fq '26.9.0'
ansible-playbook -i "$inventory" "$tools_playbook" >/dev/null
ansible-playbook -i "$inventory" "$tools_playbook" --check >/dev/null
ansible-playbook -i "$inventory" "$profile_playbook" \
  --extra-vars "profile_source=$profile_source" >/dev/null
git --version
pwsh --version
rpm -q powershell docker-compose-plugin
[[ -x /usr/libexec/docker/cli-plugins/docker-compose ]]
[[ ! -e /usr/bin/docker ]]
jq --version
jq -n '{bootstrap:true}'
yq --version
yq -n '.bootstrap = true'
[[ $(dotnet --version) == 10.0.401 ]]
dotnet --list-sdks
[[ $(node --version) == v24.21.0 ]]
node -e 'if (2 + 2 !== 4) process.exit(1); console.log("Node runtime OK")'
npm --version
codex --version
codex --profile sbx mcp list
eza --version
fd --version
rg --version
delta --version
zoxide --version
bat --version
fzf --version
edit --version
msedit --version
oh-my-posh version
[[ -L "$HOME/.local/bin/edit" && $(readlink -- "$HOME/.local/bin/edit") == "$HOME/.local/share/sbx-tools/edit/current/edit" ]]
[[ -L "$HOME/.local/bin/msedit" && $(readlink -- "$HOME/.local/bin/msedit") == "$HOME/.local/share/sbx-tools/edit/current/edit" ]]
[[ $(readlink -- "$HOME/.local/share/sbx-tools/dotnet/current") == "$HOME/.local/share/sbx-tools/dotnet/"* ]]
bash -ic 'type z; type fzf; alias ls; alias cat' </dev/null
ansible-playbook --version
printf 'PASS: developer tools, Ansible convergence, and Bash initialization\n'
