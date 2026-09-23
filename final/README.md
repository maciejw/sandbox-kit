# Developer bootstrap

The sandbox image contains the pinned Ansible control node. Repository state
is mounted after image creation; application tools and the developer profile are
restored by Ansible, not baked into the image.

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
inventory=/workspace/sandbox-kit/ansible/inventory/hosts.yml
ansible-playbook -i "$inventory" \
  /workspace/sandbox-kit/ansible/playbooks/tools.yml
ansible-playbook -i "$inventory" \
  /workspace/sandbox-kit/ansible/playbooks/profile.yml \
  --extra-vars profile_source=/workspace/sandbox-kit/configuration/profile
```

Use `ansible-playbook --check` for tool convergence verification; profile copy
is idempotent when reapplied. Recreate the named sandbox after rebuilding the
image; the provisioning repository and writable workspace are preserved.

## Verification

```bash
SBX_REPOSITORY_ROOT=/workspace/sandbox-kit \
  /workspace/sandbox-kit/final/scripts/verify-dev.sh \
  /workspace/sandbox-kit/configuration/profile
```

The script checks the image-owned Ansible control node, applies the tools and
profile playbooks, reapplies the profile idempotently, and validates the
installed developer commands and shell initialization.
