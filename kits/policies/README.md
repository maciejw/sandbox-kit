# Team policy examples

These optional SBX v2 mixins demonstrate team-specific network rules. They use
reserved `example.com` hosts as placeholders: replace them before using them
for a real team. Selecting neither mixin keeps the existing sandbox behavior.

## Layout

```text
images/almalinux9/                   Dockerfile and image-owned runtime scripts
kits/almalinux9/spec.yaml            Base sandbox: image, launch, storage, setup
kits/policies/team-backend/spec.yaml Backend network additions and denials
kits/policies/team-frontend/spec.yaml Frontend network additions and denials
```

Each kit needs its own directory containing `spec.yaml`. Image sources live
separately under `images/`. Policy mixins have no `sandbox:`
block and no image of their own; both examples can use the same base image.

| Example | Allows | Denies |
| --- | --- | --- |
| [Backend](team-backend/spec.yaml) | NuGet plus sample private packages and backend API, on port 443. | Sample backend telemetry host, on every port. |
| [Frontend](team-frontend/spec.yaml) | npm plus sample frontend API and asset host, on port 443. | Sample frontend analytics host, on every port. |

## Customize

1. Copy an example directory, such as `team-backend`, to `team-myteam`.
2. Give its `name` a unique value and update its display name and description.
3. Replace the placeholder hosts in `permissions.network.allow` and `deny`.
   Use `host:443` to restrict an entry to HTTPS's usual port, or omit the port
   to match all ports. Include separate hosts used by redirects or downloads.
4. Validate the mixin, then select it when creating a new sandbox.

Rules compose with the base kit, other selected mixins, and host policy.
**The allow entries are additions, not an exclusive team allowlist.** The host's
Balanced preset already permits common development services. Denials win over
matching allowances; organization policy may further restrict access. Selecting
both examples combines their rules rather than choosing one over the other.

To establish a strict allowlist, also review the host policy preset and every
selected kit's allowances. These examples do not change machine-wide policy.

## Validate and use

Run from the repository root in PowerShell after building and loading the image
with `Publish-SbxImage.ps1`:

```powershell
sbx kit validate .\kits\almalinux9 --offline --json
sbx kit validate .\kits\policies\team-backend --offline --json
sbx kit validate .\kits\policies\team-frontend --offline --json
```

The creation wrapper currently selects only the base kit. For a team policy,
use this command in place of `New-SbxSandbox.ps1`; it preserves the same
read-only provisioning repository and separate writable project workspace:

```powershell
$repositoryRoot = (Get-Location).Path
$workspacePath = 'D:\sandbox-workspace'
New-Item -ItemType Directory -Path $workspacePath -Force | Out-Null

sbx create --name alma9-backend --cpus 2 --memory 2g `
  --kit ./kits/policies/team-backend `
  ./kits/almalinux9 $workspacePath "${repositoryRoot}:ro"

.\Initialize-SbxSandbox.ps1 -Name alma9-backend
sbx run --name alma9-backend
```

For the frontend example, change the `--kit` path to
`./kits/policies/team-frontend` and choose a different sandbox name. If the
repository is not at `D:\sandbox-kit`, pass its guest mount path using the
initializer's `-RepositoryPath` parameter.

Inspect effective policy decisions after creation:

```powershell
sbx policy ls alma9-backend
sbx policy check network --sandbox alma9-backend https://api.backend.example.com --json
sbx policy check network --sandbox alma9-backend https://telemetry.backend.example.com --json
```

Use your replacement hostnames in those checks. Verify actual allowed and
denied connections from the sandbox as well: offline validation checks the kit
format, not connectivity or runtime enforcement. Podman image acceptance does
not exercise SBX's network policy.

Edits to a local spec do not update an existing sandbox. Use a new sandbox for
the revised kit selection; save local profile commits before removing an old
one. For an immediate adjustment to an existing sandbox, use scoped
`sbx policy allow network --sandbox NAME HOST` or
`sbx policy deny network --sandbox NAME HOST` commands instead. Policy-only
changes do not require rebuilding the image.

## Other restrictions

Keep shared image/runtime requirements in the base kit, including its current
`security.privileged: true` requirement for nested Podman. Team network mixins
do not change that requirement. Workspace read-only mounts and CPU/memory
allocations are selected by the creation command. Do not assume arbitrary
Docker security flags are valid fields in an SBX spec.

See Docker's [v2 kit reference](https://docs.docker.com/ai/sandboxes/customize/kits-v2/)
and [local policy guide](https://docs.docker.com/ai/sandboxes/governance/access-controls/local/)
for the available fields and policy precedence.
