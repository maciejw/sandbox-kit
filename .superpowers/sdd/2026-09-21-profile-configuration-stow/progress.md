# SDD ledger — plan: docs/superpowers/plans/2026-09-21-profile-configuration-stow.md

Ruling: Work in the current checkout — the repository has no commits and the entire baseline is staged as user-owned additions, so a new Git worktree has no meaningful base; preserve the index and do not commit.

Pre-flight: Task 1 produces the Stow package/link test contract consumed by Task 2; Task 2 produces the package-directory resource contract consumed by Tasks 3 and 4; Task 3 produces the migrated package consumed by Task 4 and the end-to-end harness in Task 5; Task 4 produces the runtime dependency and SBX workflow consumed by Task 5. All write ownership is sequential in this single checkout.

Completed: ProfileConfiguration was removed from SandboxKit and the canonical
profile was migrated to direct home-relative Stow paths. The native wrapper
validates source safety, rejects Podman storage and unsafe links, backs up
regular conflicts, locks per-home operations, and verifies links cross-platform.
The image installs GNU Stow from EPEL in development-runtime only. Verification
evidence: host Pester 31/31, mounted-image Pester 31/31, focused disposable
backup/idempotence and drift/safety checks passed, and verify-restore.sh passed
with its profile-only scope. No commit was created.
SBX kit validation was attempted but remained blocked by the host settings
store lock (`DockerSandboxes/sandboxes/config/settings.json.lock`); no sandbox
mutation was performed.
