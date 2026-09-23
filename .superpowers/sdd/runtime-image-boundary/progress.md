# SDD ledger — plan: docs/superpowers/plans/2026-09-21-runtime-image-boundary.md

Setup: Windows could not execute the Unix `sdd-workspace` helper, so this scoped workspace and ledger were created manually. Existing staged/user-owned files are preserved.

Pre-flight: shared interfaces
- Task 1 produces Dockerfile/path contract tests consumed by Tasks 2–5; preserve the existing test path-resolution behavior while adding mounted-root support.
- Task 2 produces the runtime-only image consumed by Tasks 3–7; PSResourceGet and Pester remain image-owned, while all repository files are absent.
- Task 3 produces `SBX_REPOSITORY_ROOT` launcher/driver behavior consumed by Tasks 4–5; both explicit and upward-discovered roots must resolve the same paths.
- Task 4 produces the finished-image validation flow consumed by Task 7; all source-dependent commands run from the read-only repository mount.
- Task 5 consumes Task 3's launcher contract and is used by Task 4's runtime checks.

Scope verdict: within_scope. One repository and one cohesive image/runtime-boundary outcome.
Plan audit: ready_with_assumptions. Assumption: Podman build/run access remains available for the final image validation.

Task 1: complete
- RED: Bootstrap.Tests.ps1 after adding runtime-only image and root-aware launcher assertions — 9 passed, 4 failed for the expected legacy COPY/`/opt`/build-DSC/launcher contracts.
- GREEN: host module fast loop passed 14 tests; final Bootstrap.Tests.ps1 passed 15 tests, including the full-Dockerfile and mounted-harness contracts.

Ruling: Task 5's repository-root verification scripts were implemented before the Task 4 harness run — the harness invokes `verify-tools.sh`, so this dependency is required to exercise the approved finished-image flow without image-owned paths.

Task 2: complete
- GREEN: runtime-only Dockerfile contract filter — 2 passed.
- Image build: `localhost/sandbox-kit:runtime-only` completed successfully with DSC 3.3.0, PowerShell 7.6.6, PSResourceGet, and Pester layers.

Task 3: complete
- GREEN: explicit-root, upward-discovery, and invalid-root container checks; both valid paths returned successful DSC system-get output and nonexistent explicit roots returned stable marker diagnostics from both launcher paths.
- Static launcher/driver contract test passed.

Task 4: complete
- GREEN: finished-image harness passed 29 tests, direct class-resource discovery, unset-root upward discovery, repository verify-tools, system test, tools get, profile set, and profile test.

Task 5: complete
- RED then GREEN: verification-script path contract failed before refactor and passed after all three scripts used `SBX_REPOSITORY_ROOT`/repository-relative paths.

Task 6: complete
- GREEN: repository documentation and runtime-boundary notes updated in `final/README.md`, `sbx-almalinux9/README.md`, and `DSC-ARCHITECTURE.md`.

Task 7: complete
- GREEN: runtime-only image inspection confirmed PSResourceGet 1.3.0-preview2 and Pester are present while `/opt/sbx-bootstrap`, `/opt/sbx-bootstrap-ps`, and `/usr/local/bin/dev-bootstrap` are absent; PowerShell and Bash syntax checks passed.
- GREEN: final mounted-image validation completed successfully after adding root-side `HOME=/root` for the unset-root system probe.

Review: rework findings addressed
- Fixed nonexistent explicit-root diagnostics before path canonicalization in both launch paths.
- Added finished-image unset-root upward-discovery execution from a nested repository directory.
- Added `verify-tools.sh` to the standard finished-image harness.
- Added full-Dockerfile guards against repository-specific COPY sources and legacy bootstrap paths.
- Independent reviewer noted a separate pre-existing profile-composition documentation contradiction; it remains outside this runtime-boundary scope.
- Final independent review verdict: accept; no remaining Critical or Important findings.

Post-plan hardening: security remediation
- Added `dnf-command(versionlock)`, locked DSC 3.3.0 and PowerShell 7.6.6, and upgraded the remaining AlmaLinux 9 runtime packages.
- The rebuilt image reports no remaining AlmaLinux security updates from `dnf updateinfo list security`; mounted-image validation passed 31 tests plus DSC discovery and driver checks.
