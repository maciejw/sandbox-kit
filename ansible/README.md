# Ansible sandbox provisioning

Ansible is the authoritative provisioning engine for the sandbox image. The
image contains Ansible Core `2.21.4` and ansible-lint `26.9.0` in
`/opt/ansible`; the repository supplies the inventory, tool state, playbooks,
and developer profile at runtime.

## Source of truth

`inventory/group_vars/sandbox/tools.yml` contains the 14 pinned application
tools, including versions, URLs, checksums, archive formats, strip-component
values, and command maps.

`inventory/group_vars/sandbox/profile.yml` contains the default guest path for
the mounted developer profile. Override `profile_source` when a sandbox uses a
different mount.

## Usage

Call Ansible directly with explicit repository paths:

The image sets `ANSIBLE_FORCE_COLOR=1`, so playbook output remains readable when
SBX captures the command stream instead of presenting Ansible with a TTY.

```bash
inventory=ansible/inventory/hosts.yml
ansible-playbook -i "$inventory" ansible/playbooks/tools.yml
ansible-playbook -i "$inventory" ansible/playbooks/tools.yml --check
ansible-playbook -i "$inventory" ansible/playbooks/profile.yml \
  --extra-vars profile_source=/d/sandbox-kit/configuration/profile
```

The inventory supplies the default profile source. Callers may override the
source with `--extra-vars`; the profile playbook copies the profile tree into
`$HOME` and overwrites existing files.

Tools are stored under `~/.local/share/sbx-tools`, downloads under
`~/.cache/sbx-tools`, state under `~/.local/state/sbx-tools`, and command links
under `~/.local/bin`. Ansible restores the profile files directly into `$HOME`.

## Direct checks

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/tools.yml --syntax-check
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/tools.yml --check --diff
ansible-lint ansible/
```

`requirements.txt` documents the image-pinned control-plane versions for
rebuilding the environment outside the image.

## Updating tool releases

From the repository root, use `Update-ToolState.ps1` to validate the configured
URLs and update release fields in the inventory. The write path uses mikefarah
`yq` in place, so a working `yq` executable must be available on `PATH` (or be
passed with `-YqPath`):

```powershell
pwsh -NoLogo -NoProfile -File .\Update-ToolState.ps1 -CheckOnly
pwsh -NoLogo -NoProfile -File .\Update-ToolState.ps1 -WhatIf
pwsh -NoLogo -NoProfile -File .\Update-ToolState.ps1
# Example when yq is not on PATH:
pwsh -NoLogo -NoProfile -File .\Update-ToolState.ps1 -YqPath C:\tools\yq.exe
```

GitHub tools use the newest stable release, while Node.js and the .NET SDK stay
within their configured major/minor channels. The updater downloads candidate
assets to temporary files to recalculate their configured checksums and writes
the inventory only after every tool has resolved successfully.
