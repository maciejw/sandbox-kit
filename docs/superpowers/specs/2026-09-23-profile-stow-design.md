# Stow-Managed Profile Design

**Status:** Draft for review

## Objective

Keep a writable Git clone of this repository at `$HOME/.dotfiles` in each
sandbox, and use GNU Stow to link the developer profile from that clone into
`$HOME`. Ansible is responsible for creating the clone when it is absent. The
initializer runs Stow after Ansible completes.

The profile must remain editable through the clone: a user can create a branch,
adopt or edit profile files, commit those changes, and update the branch from
`origin/master` without initialization resetting the clone.

## Current State

- The Windows repository is mounted read-only in the sandbox at
  `/d/sandbox-kit`; the separate project workspace is writable.
- `$HOME` inside the image is `/home/agent`.
- `ansible/playbooks/profile.yml` currently copies
  `/d/sandbox-kit/configuration/profile` into `$HOME`.
- `configuration/profile` already contains home-relative entries such as
  `.bashrc`, `.gitconfig`, `.codex/`, and `.config/`.
- The development image installs EPEL but does not currently install GNU Stow.
- The host checkout has a local `master` commit but no configured Git remote.

## Design

### Repository clone

The profile provisioning playbook will ensure that the committed repository is
cloned from `/d/sandbox-kit/.git` to `$HOME/.dotfiles` when that destination is
absent. This preserves the repository history and gives the clone an `origin`
that points to the read-only host mount.

When `$HOME/.dotfiles` already exists, initialization must preserve its current
branch, commits, staged changes, and working-tree changes. It must not fetch,
pull, switch branches, reset, clean, or replace the existing clone. If the path
exists but is not a Git checkout of this repository, initialization fails
without deleting or overwriting it. Configure the Ansible Git task with
`update: false`: it clones when absent and does not fetch when the clone already
exists. Stow remains a separate step and may intentionally change a conflicting
home file into a package working-tree change when `--adopt` is used.

With this source path, `git pull origin master` in the clone reads commits from
the host checkout's `master`. The host checkout currently has no external
remote, so external-server updates are outside this design. The read-only source
allows fetching but not pushing.

### Stow package layout

Move the contents of `configuration/profile/` up one level so `configuration/`
is the Stow package:

```text
configuration/
  .bash_profile
  .bashrc
  .codex/
  .config/
  .gitconfig
```

The Ansible and image files remain outside the package. The initializer applies
the package from the clone with:

```bash
stow --dir "$HOME/.dotfiles" --target "$HOME" --adopt --restow configuration
```

GNU Stow's `--adopt` deliberately moves an existing regular target file into
the package, replacing that package file's contents with the adopted file.
This makes the clone's working tree show the adopted change for the user to
review and commit. `--restow` first removes the package's links and then
recreates them, which also prunes obsolete links. There is no subsequent Git
reset. See the [GNU Stow invocation manual](https://www.gnu.org/software/stow/manual/html_node/Invoking-Stow.html).

### Ownership and initialization order

1. The initializer applies the existing Ansible tools playbook.
2. Ansible ensures the `$HOME/.dotfiles` clone exists and leaves an existing
   checkout untouched.
3. The initializer runs GNU Stow from the cloned package into `$HOME`.

GNU Stow will be installed in the development-runtime image from EPEL. Profile
files remain outside the image so the read-only repository mount remains the
source used for creating new clones.

## Lifecycle Assumption

The clone and local commits live in the sandbox home. The current sandbox
definition has no host-backed mount for `$HOME/.dotfiles`. They therefore remain
available while that sandbox home is retained, but are not guaranteed to
survive `New-SbxSandbox.ps1 -Recreate`, which removes the named sandbox before
creating it again. Preserving unpushed branches across recreation would require
a separate persistence design for this directory.

## Acceptance Criteria

- A new sandbox initialization clones the host repository into
  `$HOME/.dotfiles` and creates the expected Stow links into `$HOME`.
- The links point into `$HOME/.dotfiles/configuration`, not the read-only
  `/d/sandbox-kit` mount.
- Repeated initialization leaves the selected branch, local commits, staged
  changes, and working-tree changes intact while ensuring the profile is
  restowed.
- A regular conflicting home file is adopted into the package, and the clone
  shows that profile change as a Git change for the user to review.
- An unrelated existing directory or non-repository at `$HOME/.dotfiles` is
  not removed or overwritten.
- The image provides GNU Stow, and the documented initialization commands
  apply the same clone-then-Stow sequence.

## Non-Goals

- Adding a remote server URL to the host repository or pushing from the
  sandbox.
- Automatically updating an existing clone or choosing the user's branch
  merge/rebase strategy.
- Preserving the clone across sandbox recreation.
- Linking Ansible, image, or other project files into `$HOME`.
