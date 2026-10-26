# Verification — 2026-09-17

Historical evidence: paths below reflect the layout at verification time.
The kit now lives in `kits/almalinux9`; image sources are in `images/almalinux9`.

## Final configuration

- Host: Windows amd64; SBX `v0.43.0` (`79805a6e3c6667520dc2da4f6bdeddae9b700969`).
- Builder: Windows Podman client 6.1.2, remote WSL Podman engine 5.8.2.
- Image: `localhost/almalinux9-sbx:poc`.
- Image ID: `a04135d8e5d732ef27af3473ade5ec60094d36deaebe2248e80599b1623d5799`.
- Userspace: AlmaLinux 9.8; Podman 5.8.2; SBX guest kernel 7.0.12.
- Sandbox: `alma9-podman`, 2 virtual CPUs, 2 GiB requested memory.
- Privileged outer container inside its microVM; rootless Podman as UID/GID 1000.
- Dedicated 4 GiB sparse ext4 volume mounted at `/home/agent/.local/share/containers`.
- Host workspace `D:\sandbox-kit\sbx-almalinux9` mounted at
  `/d/sandbox-kit/sbx-almalinux9`.

## Results

`sbx kit validate .\sbx-almalinux9 --json` returned `valid: true`, no warnings.

`sbx exec alma9-podman verify-sbx /d/sandbox-kit/sbx-almalinux9`
returned exit code 0 both on a fresh sandbox and after `sbx stop alma9-podman`.
The checks established:

| Check | Observed result |
| --- | --- |
| AlmaLinux, UID/GID, home ownership | AlmaLinux 9.8, agent 1000:1000, home owned by 1000 |
| Sudo and proxy preservation | Passwordless sudo; all six proxy variables preserved |
| Registry TLS | Verified HTTPS, expected unauthenticated HTTP 401 |
| Rootless execution | `Host.Security.Rootless=true`; Alpine container runs |
| UID and GID mappings | `0 -> 1000 (1)` and `1 -> 100000 (65536)` |
| Storage | Overlay on ext4; `Native Overlay Diff:true` |
| Kernel sharing | Outer sandbox and nested Alpine both report 7.0.12 |
| Nested HTTPS | Curl image verifies HTTPS using read-only SBX CA bundle mount |
| Workspace | Host-mounted file read, copied by nested container, content matches, owner UID 1000 |
| Nested build | Alpine-based build with COPY and RUN succeeds; built image returns expected content |
| Restart | Same acceptance passes; cached images persist |
| Shell entrypoint | `sbx run --name alma9-podman -- -c ...` runs a rootless container and exits 0 |

## Confirmed limitations, not passing claims

Podman accepted `--memory 64m --cpus 0.5 --pids-limit 64`, but the container
reported:

```text
max
max 100000
max
```

An explicit `--cgroups=enabled` probe also did not establish enforcement.
This configuration therefore does **not** promise rootless per-container
resource controls. VM-wide allocation is configured through SBX.

The `/` mount is not shared; ordinary workspace bind mounting passed, while
arbitrary mount propagation remains unverified. Nested HTTPS was tested with
an explicit CA mount. HTTPS downloads during a nested image build were not
tested; they require provisioning CA trust in the build stage.

## Experiments that changed the implementation

1. Original kit rejected by SBX: v1 declaration with v2 entrypoint/command syntax.
2. AlmaLinux image booted directly, proving Ubuntu inheritance unnecessary here.
3. Image pulls initially failed certificate verification. Creating the Debian
   bundle path alone did not fix it. Importing the runtime `PROXY_CA_CERT_B64`
   into AlmaLinux's trust store did.
4. Default outer-container mode lacked TUN/FUSE device nodes and had read-only
   cgroups. Privileged mode supplied capabilities and writable cgroups but did
   not create the nodes. Creating TUN enabled rootless pasta networking.
5. FUSE remained inaccessible (`Operation not permitted`) even to root with the
   device node present. VFS storage worked as a diagnostic fallback.
6. A block-backed ext4 volume enabled working native overlay; final configuration
   uses that volume and does not depend on FUSE or VFS.
7. `example.com` returned 403 because SBX policy denied it. The nested HTTPS
   acceptance check instead uses the already-allowed Docker registry endpoint.

The final image was exported locally and loaded into SBX, not published.
Rebuilding from moving base/repository tags can produce a different image ID.

## Handoff state

The verified `alma9-podman` sandbox remains available, stopped after the shell
command completed. Connect with `sbx run --name alma9-podman`.
The final archive is `D:\sandbox-kit\almalinux9-sbx-poc.tar`.

Cleanup of the disposable probes was rejected by automatic approval review
because the workspace was out of credits. No cleanup command executed.
The four stopped sandboxes `alma9-podman-probe`, `alma9-ca-probe`,
`alma9-runtime-probe`, and `alma9-volume-probe` remain, along with the
`ca-probe` and `runtime-probe` image tags and their two local tar archives.
These are diagnostic leftovers, not dependencies of the verified kit.
