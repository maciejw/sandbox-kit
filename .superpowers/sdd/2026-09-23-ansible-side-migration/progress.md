# SDD ledger — plan: docs/superpowers/plans/2026-09-23-ansible-side-migration.md

Pre-flight: Tasks 1→2 share the side sandbox and mounted repository; Task 2 produces the Ansible venv and canonical JSON consumer that Tasks 3→4 consume. No conflicting interfaces found.

Ruling: Execute in the current working tree — the user explicitly authorized implementation and the repository is already the shared sandbox-kit workspace; no separate worktree is introduced because the experiment itself requires host-mounted D:\sandbox-kit.

Task 1: Ruling: AlmaLinux mirrorlist access returned HTTP 403, so the side sandbox used direct HTTPS `repo.almalinux.org` BaseOS/AppStream URLs with other repositories disabled for the Python install — this keeps the image and existing sandbox unchanged; cost if wrong: the experiment depends on a side-only repository workaround.

Task 1: complete (sandbox alma9-ansible-1 created; mounted repo, Python 3.9, Stow 2.4.0, Python 3.12, Ansible Core 2.21.4, local ping, and host SSH route verified)

Task 2: complete (source-shape check red→green; canonical JSON loop, shared install task, README, and Ansible syntax check passed)

Task 3: complete (profile playbook syntax check passed; existing wrapper applied profile; corrected playbook reports zero changes on repeated apply)

Task 4: complete (tools check mode passed; first apply converged 14 tools with changed=92; second apply converged with changed=0; existing verify-dev.sh passed; footprint recorded; existing Pester suite passed 14/14)

Final: fixed profile check-mode execution — forced the wrapper's read-only test to run under Ansible --check and verified it with the profile check plus repeated apply; existing suite 14/14.

Final review: self-review (delegated review was not used; repository changes were checked against the approved plan, syntax-checked in the side sandbox, exercised end-to-end, and passed git diff --check apart from existing LF→CRLF warnings).

Follow-up: installed ansible-lint 26.9.0 in the side sandbox's Ansible venv, configured `.vscode/settings.json` for the remote interpreter/linter, and verified the VS Code remote server and extension host on `alma9-ansible-1.sbx`.

Follow-up: migrated the Ansible tool state into `ansible/inventory/group_vars/sandbox/tools.yml`; parity check matched all 14 DSC resource objects, Ansible check mode passed with zero changes, normal apply passed with changed=0, and ansible-lint/syntax checks remained green.

Follow-up verification: existing Pester suite passed 14/14 after the inventory-state migration.

Follow-up: removed the DSC-only `type` discriminator from Ansible inventory state; parity now verifies all 14 property objects without `type`, and lint/syntax checks remain green.

Final architecture decision: removed the DSC package, JSON configuration, PowerShell bootstrap, and SandboxKit resource implementation; Ansible is now the sole provisioning path and is baked into `sbx-base` with pinned `ansible-core` 2.21.4 and `ansible-lint` 26.9.0.

Final verification: rebuilt `localhost/almalinux9-sbx:dev`; image acceptance converged all 14 tools and the GNU Stow profile with zero failures; profile restore/safety acceptance passed; host Pester suite passed 10/10; Ansible lint and both playbook syntax checks passed.

Image follow-up: kept Microsoft and Docker repository definitions in `sbx-base`, installed PowerShell 7.6.6 and Docker Compose 5.5.1 in `development-runtime` without the Docker CLI/daemon, converted Dockerfile setup blocks to heredoc scripts, rebuilt successfully, and verified both repository files and package commands in the image.

Developer verification now asserts `pwsh`, the Compose plugin, and the intentional absence of `/usr/bin/docker`; the rebuilt-image acceptance suite passed after the package-stage change.

Acceptance harness cleanup: renamed `final/test-powershell.ps1` to `final/Invoke-ImageAcceptance.ps1`, updated the active README command, fixed the moved root `Invoke-Tests.ps1` test-root calculation, and reran the host suite (12/12 passed).

Simplification: removed the repository launcher entirely. `Initialize-SbxSandbox.ps1` and the verification scripts now call `ansible-playbook` directly with explicit inventory, playbook, and profile paths; profile restore acceptance still passes.

Final direct-call verification: rebuilt-image acceptance passed with zero failures; tools and profile playbooks converged successfully, and no active references to the removed `configuration/ansible/dev-bootstrap` launcher remain.

Verification simplification: removed the disposable restore harness and merged image-owned/tool checks into `final/scripts/verify-dev.sh`; consolidated image acceptance passed with exit code 0.

Profile layout cleanup: moved the GNU Stow shell helper from `ansible/tasks/` to `ansible/scripts/`, added the default mounted profile path to inventory group variables, and verified lint, syntax, and image acceptance.

Stow simplification: removed the helper, backups, and post-link verification; the profile playbook now invokes GNU Stow directly using inventory-backed source/target state. The image no longer seeds `/home/agent` from `/etc/skel`, and the rebuilt image acceptance passed.

Mount layout cleanup: removed the external `sandbox-home` profile mount. `New-SbxSandbox.ps1` now mounts the repository read-only for provisioning and a separate writable workspace first; initialization derives the profile from `/d/sandbox-kit/configuration/profile`.

Profile simplification: removed GNU Stow from the image and provisioning documentation. The Ansible profile playbook now recursively copies the repository profile into `$HOME`, overwriting sandbox-generated files when needed; a two-run image check reported `changed=1` then `changed=0` and confirmed the copied `.gitconfig` matches the source.

Output cleanup: labeled the command-path assertion loop with the command name instead of printing each registered `stat` object, and enabled `ANSIBLE_FORCE_COLOR=1` in the image. The rebuilt image emitted colored callback sequences and the Ansible lint/syntax checks remained green.

Output correction: the label alone did not suppress Ansible's serialized loop result. Replaced the assertion loop with a compact invalid-path list and verified the existing `alma9-test-1` sandbox completed the full tools playbook with `failed=0`; assertion output is now a small `All assertions passed` result.

Tool release updater: added `Update-ToolState.ps1` with GitHub, Node.js-major, and .NET-channel providers, temporary checksum calculation, URL validation, `-CheckOnly`, and `-WhatIf` support. Pester tests passed 4/4; the live check validated all 14 configured URLs; the full dry run resolved every release and discovered Codex `0.156.1` without mutating the inventory.

Tool inventory writes now use a single mikefarah `yq --inplace` expression, with an explicit `-YqPath` override. The expression test, full Pester suite, live URL check, release dry run, and Linux sandbox yq integration check passed.

GitHub PAT handling correction: API authentication is now restricted to `api.github.com`; artifact and checksum downloads use User-Agent-only headers, avoiding 401 responses from public release download URLs. Regression coverage and the live URL/full release dry runs passed.

Tool release status output now marks current versions with green `✅` and available upgrades with yellow `⬆️`; the full dry run displayed Codex `0.154.0 -> 0.156.1` as an available update and all other tools as current.

Preview safety correction: `-WhatIf` now skips GitHub artifact downloads and reuses the configured checksum while resolving version/source changes; actual updates still download and recalculate checksums. Pester coverage passed 7/7 and the full dry run completed without artifact-download progress.

Status-marker rendering cleanup: replaced the emoji upgrade marker with a plain Unicode `▲` so terminals render the yellow update indicator consistently; current versions remain green `✅`.
