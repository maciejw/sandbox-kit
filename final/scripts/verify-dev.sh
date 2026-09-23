#!/usr/bin/env bash
# Image and developer-runtime acceptance; no application scaffolding or API requests.
set -euo pipefail

profile_repository=${1:?Usage: verify-dev.sh <mounted-repository-git-directory>}
[[ -d $profile_repository ]] || { echo "Profile repository is not a directory: $profile_repository" >&2; exit 1; }
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
profile_variables=$(jq -cn --arg profile_repository "$profile_repository" '{profile_repository: $profile_repository}')
ansible-playbook -i "$inventory" "$profile_playbook" \
  --extra-vars "$profile_variables" >/dev/null
profile_clone="$HOME/.dotfiles"
[[ -d "$profile_clone/.git" ]]
profile_origin=$(git -C "$profile_clone" remote get-url origin)
encoded_profile_repository=$(python3 -c 'from urllib.parse import quote; import sys; print(quote(sys.argv[1], safe="/"))' "$profile_repository")
case "$profile_origin" in
  "$profile_repository"|"file://$profile_repository"|"file://$encoded_profile_repository") ;;
  *) echo "Unexpected profile clone origin: $profile_origin" >&2; exit 1 ;;
esac

# A sandbox-local branch and Git state must survive profile initialization.
git -C "$profile_clone" config user.name 'Profile Acceptance'
git -C "$profile_clone" config user.email 'profile-acceptance@example.invalid'
git -C "$profile_clone" switch -c acceptance/local-profile >/dev/null
printf 'committed\n' > "$profile_clone/.profile-acceptance-commit"
git -C "$profile_clone" add .profile-acceptance-commit
git -C "$profile_clone" commit -m 'acceptance: sandbox-local profile commit' >/dev/null
printf 'unstaged\n' >> "$profile_clone/.profile-acceptance-commit"
printf 'staged\n' > "$profile_clone/.profile-acceptance-staged"
git -C "$profile_clone" add .profile-acceptance-staged
profile_branch=$(git -C "$profile_clone" branch --show-current)
profile_head=$(git -C "$profile_clone" rev-parse HEAD)
profile_status=$(git -C "$profile_clone" status --porcelain=v1 --untracked-files=all)
profile_staged=$(git -C "$profile_clone" diff --cached --binary)
profile_worktree=$(git -C "$profile_clone" diff --binary)
ansible-playbook -i "$inventory" "$profile_playbook" \
  --extra-vars "$profile_variables" >/dev/null
[[ $(git -C "$profile_clone" branch --show-current) == "$profile_branch" ]]
[[ $(git -C "$profile_clone" rev-parse HEAD) == "$profile_head" ]]
[[ $(git -C "$profile_clone" status --porcelain=v1 --untracked-files=all) == "$profile_status" ]]
[[ $(git -C "$profile_clone" diff --cached --binary) == "$profile_staged" ]]
[[ $(git -C "$profile_clone" diff --binary) == "$profile_worktree" ]]

# A conflicting home file is adopted into the writable clone by Stow.
cp "$profile_clone/configuration/.bashrc" "$HOME/.bashrc"
printf '\n# stow-adopt-acceptance\n' >> "$HOME/.bashrc"
stow --dir "$profile_clone" --target "$HOME" --adopt --restow configuration
grep -Fq '# stow-adopt-acceptance' "$profile_clone/configuration/.bashrc"
[[ -L "$HOME/.bashrc" ]]

# Restow removes links for package entries that were deleted.
printf '# stow prune acceptance\n' > "$profile_clone/configuration/.stow-prune-acceptance"
stow --dir "$profile_clone" --target "$HOME" --adopt --restow configuration
[[ -L "$HOME/.stow-prune-acceptance" ]]
rm "$profile_clone/configuration/.stow-prune-acceptance"
stow --dir "$profile_clone" --target "$HOME" --adopt --restow configuration
[[ ! -e "$HOME/.stow-prune-acceptance" && ! -L "$HOME/.stow-prune-acceptance" ]]

for profile_link in .bashrc .gitconfig .config/powershell/Microsoft.PowerShell_profile.ps1; do
  resolved_profile_link=$(readlink -f "$HOME/$profile_link")
  case "$resolved_profile_link" in
    "$profile_clone/configuration/"*) ;;
    *) echo "Profile link escapes the home clone: $profile_link -> $resolved_profile_link" >&2; exit 1 ;;
  esac
done
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
printf 'PASS: developer tools, clone preservation, Stow adoption/pruning, and Bash initialization\n'
