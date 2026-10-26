# Developer bootstrap

The sandbox image contains the pinned Ansible control node and GNU Stow.
Repository state is mounted after image creation; Ansible installs application
tools and clones the profile repository, then Stow links the profile from the
home clone.

## Build and validate

```powershell
.\Publish-SbxImage.ps1
pwsh -NoLogo -NoProfile -File .\final\Invoke-ImageAcceptance.ps1 -Image localhost/almalinux9-sbx:dev
```

The validation wrapper mounts this repository read-only and checks the image,
Ansible installation, tool playbook, profile playbook, and workflow scripts.

## Create and initialize a sandbox

```powershell
.\New-SbxSandbox.ps1 -Name alma9-dev -WorkspacePath D:\sandbox-workspace
sbx run --name alma9-dev
.\Initialize-SbxSandbox.ps1 -Name alma9-dev
```

The initializer runs:

```bash
inventory=/d/sandbox-kit/ansible/inventory/hosts.yml
ansible-playbook -i "$inventory" \
  /d/sandbox-kit/ansible/playbooks/tools.yml
ansible-playbook -i "$inventory" \
  /d/sandbox-kit/ansible/playbooks/profile.yml \
  --extra-vars '{"profile_repository":"/d/sandbox-kit/.git"}'
stow --dir "$HOME/.dotfiles" --target "$HOME" --adopt --restow configuration
```

Ansible clones the mounted repository into `$HOME/.dotfiles` only when the path
is absent, then Stow manages links from its top-level `configuration/` package.
The clone playbook preserves an existing clone's branch and Git changes; Stow
can adopt conflicting home files into the clone. Removing or recreating the
sandbox also removes its home clone, so save local commits elsewhere first if
they need to survive.

## Verification

```powershell
pwsh -NoLogo -NoProfile -File .\final\Invoke-ImageAcceptance.ps1 -Image localhost/almalinux9-sbx:dev
```

The disposable wrapper runs `verify-dev.sh` inside a `--rm` container. The
script is disposable-only: it requires `SBX_DISPOSABLE_ACCEPTANCE=1` and
refuses to run when `$HOME/.dotfiles` already exists. It checks the image-owned
Ansible control node, applies the tools and clone playbooks, creates a
sandbox-local branch to verify preservation, checks Stow adoption and pruning,
and validates links and installed developer tools.
