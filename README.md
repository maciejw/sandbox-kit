# Sandbox Kit

A Windows-hosted AlmaLinux 9 development sandbox using Docker Sandboxes (SBX),
rootless Podman inside the sandbox, Ansible for developer tools, and GNU Stow
for the home profile.

## Prerequisites

- PowerShell 7, Git, the Docker Sandboxes `sbx` CLI, and host Podman on `PATH`.
- A running Podman machine (`podman info` should succeed).
- Network access for image packages and the configured developer tool downloads.

The commands below assume this repository is checked out at `D:\sandbox-kit`.
Use a separate directory for project work. The profile is cloned from this
repository's committed Git state; commit profile changes before initializing a
new sandbox.

## Quickstart

Run in PowerShell on the Windows host, checking that each command succeeds:

```powershell
cd D:\sandbox-kit

# Build the image, export it, and load it into SBX's separate image store.
.\Publish-SbxImage.ps1
sbx kit validate .\kits\almalinux9 --json

# Create the sandbox and its writable project workspace.
.\New-SbxSandbox.ps1 -Name alma9-dev -WorkspacePath D:\sandbox-workspace

# Install developer tools, clone the profile, and create its home links.
# sbx exec starts the sandbox if it is stopped.
.\Initialize-SbxSandbox.ps1 -Name alma9-dev

# Open the initialized sandbox shell.
sbx run --name alma9-dev
```

The repository is mounted read-only for provisioning; `D:\sandbox-workspace`
is mounted read-write for project files. Initialization creates a writable
clone at `/home/agent/.dotfiles`, then links its `configuration/` package into
the sandbox home with Stow.

If your checkout is elsewhere, use that location in `cd` and pass its guest
mount path to initialization, for example
`-RepositoryPath /d/another-location/sandbox-kit`. SBX reports mount mappings
when it creates the sandbox.

## Everyday use

```powershell
sbx run --name alma9-dev
sbx stop alma9-dev

# Reapply tools and restow the profile after host-side changes.
.\Initialize-SbxSandbox.ps1 -Name alma9-dev
```

Repeated initialization preserves an existing profile clone's branch, commits,
staged changes, and working changes; it does not fetch or pull updates.
Stow's `--adopt` moves conflicting home files into the clone, where Git shows
them as changes. Review profile edits inside the sandbox with
`git -C "$HOME/.dotfiles" status`.

To bring committed host changes into an existing profile clone, run inside the
sandbox:

```bash
git -C "$HOME/.dotfiles" pull origin master
stow --dir "$HOME/.dotfiles" --target "$HOME" --adopt --restow configuration
```

Save sandbox-local profile commits elsewhere before removing or recreating the
sandbox. Adding `-Recreate` to `New-SbxSandbox.ps1` removes the existing sandbox
and its home clone. Rebuild and load the image after Dockerfile changes, then
create a new sandbox to use it.

## Team policies

Optional network policy mixins live under [kits/policies/](kits/policies/README.md).
The backend and frontend examples show where to allow team services, deny
specific destinations, and select a policy with `sbx create --kit`. Customize
their placeholder hosts before use. Both reuse the base sandbox image.

## Checks

From the repository root on the host:

```powershell
# Host helper tests; requires the Pester module.
pwsh -NoLogo -NoProfile -File .\Invoke-Tests.ps1

# Disposable container acceptance; requires the built image in host Podman.
pwsh -NoLogo -NoProfile -File .\final\Invoke-ImageAcceptance.ps1
```

Image acceptance checks tool provisioning, profile clone preservation, Stow
adoption/pruning, and shell initialization. For SBX-specific runtime checks,
including nested containers and workspace mounts, see the
[sandbox kit guide](kits/almalinux9/README.md#create-connect-verify).

## Repository guide

| Location | Purpose |
| --- | --- |
| [Developer bootstrap](final/README.md) | Initialization flow and disposable image acceptance. |
| [Image source](images/almalinux9/README.md) | Dockerfile and scripts installed in the image. |
| [Sandbox kit](kits/almalinux9/README.md) | SBX setup, networking, certificates, and runtime limitations. |
| [Team policy examples](kits/policies/README.md) | Separate backend/frontend policy mixins and customization commands. |
| [Runtime verification](kits/almalinux9/VERIFICATION.md) | Recorded SBX verification results and boundaries. |
| [Kit distribution](kits/README.md) | Layout, image references, and sharing kits through Git, ZIP, or a registry. |
| [Ansible provisioning](ansible/README.md) | Playbooks, tool state, direct checks, and release updates. |
| [Tool inventory](ansible/inventory/group_vars/sandbox/tools.yml) | Pinned developer tool versions, downloads, and checksums. |
| [Profile package](configuration/) | Home-relative files linked by GNU Stow. |
| [Tool release updater](Update-ToolState.ps1) | Check URLs or preview release updates with `-CheckOnly` and `-WhatIf`. |

The SBX kit is experimental. Review its documented runtime limitations before
depending on nested-container resource controls or changing its storage setup.
