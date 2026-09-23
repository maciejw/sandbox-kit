# AlmaLinux 9 + rootless Podman in Docker Sandboxes

Status: **working experimental shell kit**, verified on Windows with SBX
**v0.43.0**, AlmaLinux **9.8**, guest kernel **7.0.12**, and Podman **5.8.2**.
See [VERIFICATION.md](VERIFICATION.md) for results and limitations.

The image supplies AlmaLinux userspace; SBX supplies the microVM and kernel.
Podman and its nested containers run as the non-root `agent` user, UID/GID 1000.
This kit opens Bash and includes a pinned Ansible control node, GNU Stow,
PowerShell, Docker Compose, Git, and the rootless Podman prerequisites. The base
image keeps the Microsoft and Docker package repositories configured, but does
not install the Docker CLI or daemon. Repository playbooks, developer tools,
and personal profile files are not baked into the image. Recreate the sandbox
to reset mutable state; rebuilding the image is not part of the normal
developer workflow.
See [Developer bootstrap](../final/README.md) for the contract and commands.

## What was missing from the original proposal

- The kit mixed schema v1 with v2 fields and failed actual SBX validation.
  It now consistently uses schema v2.
- AlmaLinux's image already provides `curl-minimal`; the Dockerfile keeps it.
- SBX supplies its public proxy CA through `PROXY_CA_CERT_B64`. A custom image
  must integrate it with the distribution's trust store. Merely installing
  `ca-certificates` does not establish trust in this runtime-generated CA.
- The SBX-exported `SSL_CERT_FILE` path is Debian-style. The image aliases it
  to AlmaLinux's generated bundle; runtime setup imports the CA using
  `update-ca-trust`. No sandbox-specific certificate is baked into the image.
- Rootless Podman's default networking uses `pasta`, which needs
  `/dev/net/tun`. Runtime setup creates that device node inside the sandbox.
- Overlay-on-overlay selected FUSE, but `/dev/fuse` could not be opened in the
  tested SBX runtime, even after creating the node in privileged mode.
  A separate **4 GiB sparse ext4 volume** gives Podman working **native overlay**.

The kit sets `security.privileged: true` for the **outer container inside the
SBX microVM**. This is the same placement of privilege used by Docker's built-in
`*-docker` templates. Podman itself remains rootless. The extra privilege is
needed by this tested configuration; this is not a claim that every alternative
configuration requires it. It does not attach a host Docker or Podman socket.

## Build and load locally

Run these PowerShell commands from the parent directory (`D:\sandbox-kit` here).
The Podman engine must be available. This path was verified without Docker
Desktop or a `docker` CLI on PATH.

```powershell
.\Publish-SbxImage.ps1
sbx kit validate .\sbx-almalinux9 --json
```

Check that each command succeeds before running the next. Docker build/save
can also produce the image archive; SBX has its own image store, so a local
build alone does not make the image available to SBX.

The image name matches `sandbox.image` in `spec.yaml`. To distribute the image,
choose a registry-qualified reference and update that field. This repository
does not publish anything to a registry. The base and verification images use
moving tags; record/pin digests if you need repeatable package versions.

## Create, connect, verify

Create a sandbox with a separate writable work workspace. The repository is
mounted read-only for provisioning:

```powershell
.\New-SbxSandbox.ps1 -Name alma9-dev -WorkspacePath D:\sandbox-workspace
sbx run --name alma9-dev
.\Initialize-SbxSandbox.ps1 -Name alma9-dev
```

The initialization command runs the tools playbook, asks Ansible to clone the
mounted repository's `.git` directory into `/home/agent/.dotfiles` when absent,
then runs GNU Stow from that home clone. The top-level `configuration/` package
is linked into `/home/agent`; each profile link resolves to a file under
`/home/agent/.dotfiles/configuration`. The clone is writable and the repository
mount is read-only. A conflicting home file is adopted into the clone and
becomes a Git change.

Create local profile branches and commits inside the sandbox clone, for example
with `git -C "$HOME/.dotfiles" switch -c profile/my-changes`. Its `origin` is
the mounted repository, so `git -C "$HOME/.dotfiles" pull origin master` can
bring in host commits. The repository mount is provisioning input; use
`D:\sandbox-workspace` for active project files. Pass `-RepositoryPath` to the
initializer only when the repository mount uses a different guest path.

When replacing an existing sandbox after rebuilding the image, add
`-Recreate`. It removes the sandbox and its home clone, including local commits
that have not been saved elsewhere; the mounted repository and project
workspace remain on the host.

The image is already complete at this point. Inside the new sandbox, the
mounted repository supplies the inventory and playbooks:

```bash
ansible-playbook -i /workspace/sandbox-kit/ansible/inventory/hosts.yml \
  /workspace/sandbox-kit/ansible/playbooks/tools.yml
```

The tools playbook composes the developer's tools. To initialize the profile
separately, clone the mounted repository into the agent home, then Stow its
profile package:

```bash
ansible-playbook -i /workspace/sandbox-kit/ansible/inventory/hosts.yml \
  /workspace/sandbox-kit/ansible/playbooks/profile.yml \
  --extra-vars '{"profile_repository":"/workspace/sandbox-kit/.git"}'
stow --dir "$HOME/.dotfiles" --target "$HOME" --adopt --restow configuration
```

Ansible only creates and validates the home clone. Stow manages links from its
`configuration/` package. The separate workspace is read-write for active
project files. Do not put `/home/agent/.local/share/containers` in the developer
profile; that path remains on the sandbox-specific volume.

Creating a new sandbox from the same image and initializing it again is the
reset workflow; local clone commits must be saved elsewhere before removing a
sandbox if they need to survive recreation.

The earlier runtime-only sandbox `alma9-podman` is not changed by rebuilding.
Use the second command to connect to the development sandbox after creating it;
use a new name when creating another sandbox.
For another workspace, replace the final path. To create without mounting
host files, omit that path from `sbx create`. `sbx run` with no workspace path
when creating a sandbox instead defaults to the current host directory.

From the host, verify this machine's mounted workspace using its guest path
(SBX prints that mapping during creation):

```powershell
sbx exec alma9-podman verify-sbx /d/sandbox-kit/sbx-almalinux9
sbx stop alma9-podman
sbx exec alma9-podman verify-sbx /d/sandbox-kit/sbx-almalinux9
```

`sbx exec` starts a stopped sandbox. From an interactive shell, run
`verify-sbx "$PWD"`. Without an argument, the verifier checks its current
directory; a mountless sandbox therefore checks in-sandbox storage only.

The verifier checks identity, sudo/proxy preservation, CA trust, UID/GID
mappings, rootless mode, native overlay, kernel sharing, nested HTTPS,
workspace roundtrip and ownership, and a nested image build containing `RUN`.
It removes its temporary workspace files and test image. Alpine/curl base
images remain cached. It also reports the resource-control limitation below.

## Networking and certificates

SBX policy still controls all network access. The kit explicitly allows the
pinned .NET SDK host required by the tools document and inherits the default
GitHub, Node.js, and registry policies. Verification needs Docker Hub registry,
token and blob endpoints. Under the policy used for validation those were
already allowed; `example.com` was not. A 403 can be a policy denial, not a
Podman fault:

```powershell
sbx policy check network --sandbox alma9-podman https://registry-1.docker.io --json
```

HTTPS clients **inside nested containers** also need to trust the SBX proxy CA.
Trust in the outer AlmaLinux container is not inherited. For example, inside
the sandbox:

```bash
podman run --rm \
  -v /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem:/run/sbx-ca-bundle.pem:ro \
  docker.io/curlimages/curl:latest \
  --cacert /run/sbx-ca-bundle.pem -sS -o /dev/null -w '%{http_code}\n' \
  https://registry-1.docker.io/v2/
```

Expected response: **401**, the registry's normal unauthenticated response.
TLS verification remains enabled. Builds that download over HTTPS likewise
need CA provisioning in their build stages; the verifier's build does not
perform network downloads during `RUN`.

## Limits and lifecycle

- **Per-container CPU/memory/PID limits are not enforced in this tested rootless
  configuration.** Podman accepts the flags, but the container reports
  `memory.max=max`, `cpu.max=max 100000`, and `pids.max=max`. Do not use those
  flags as a protection boundary. Set SBX VM CPU/memory allocations at creation;
  there is no verified per-container PID limit here.
- Podman warns that `/` is not a shared mount. The tested workspace bind mount
  works, but arbitrary recursive mount propagation has not been established.
- The storage volume persists across sandbox stop/start. Removing the sandbox
  removes its attached storage; host workspace files live separately.
- Runtime setup runs at installation and startup. The shell entrypoint also
  waits for the same idempotent setup, since startup hooks are not an agent
  readiness barrier. Locks serialize concurrent setup calls.
- The image alone is insufficient: create from **this kit**, which declares
  the volume, privilege setting and initialization hooks. A bare template launch
  does not reproduce the tested configuration.
- SBX kits remain experimental. Re-run validation after SBX or image updates.

## Files

- `Dockerfile`: AlmaLinux userspace, user, utilities and CA path compatibility.
- `spec.yaml`: SBX schema v2, shell entrypoint, storage, privilege and setup.
- `sync-sbx-ca.sh`: imports the runtime CA into AlmaLinux's trust store.
- `setup-sbx-runtime.sh`: CA setup, TUN device and storage ownership.
- `sbx-shell.sh`: synchronous runtime setup before Bash.
- `verify-sbx.sh`: runtime acceptance and limitation diagnostics.

## References

- [Docker kit reference](https://docs.docker.com/ai/sandboxes/customize/kit-reference/)
- [Normative v2 specification and runtime variables](https://github.com/docker/sbx-kits-contrib/blob/main/spec/SPEC-v2.md)
- [Docker templates](https://docs.docker.com/ai/sandboxes/customize/templates/)
- [Docker sandbox architecture](https://docs.docker.com/ai/sandboxes/architecture/)
- [AlmaLinux image sources](https://github.com/AlmaLinux/container-images)
- [Nested Podman considerations](https://www.redhat.com/en/blog/podman-inside-container)
