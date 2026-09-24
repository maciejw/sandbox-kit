param(
    [string]$Image = 'localhost/almalinux9-sbx:dev'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

$containerScript = @'
set -euo pipefail
repository=/mnt/sbx-repository
inventory="$repository/ansible/inventory/hosts.yml"
tools_playbook="$repository/ansible/playbooks/tools.yml"
profile_playbook="$repository/ansible/playbooks/profile.yml"
profile_repository="$repository/.git"
git config --system --add safe.directory "$profile_repository"
test -f "$inventory"
test -f "$tools_playbook"
test -f "$profile_playbook"

run_nested_parent_repository_regression() {
  local test_home test_log profile_clone sentinel
  test_home=$(runuser -u agent -- mktemp -d)
  test_log="$test_home/profile-playbook.log"
  profile_clone="$test_home/.dotfiles"
  sentinel="$profile_clone/nested-parent-sentinel"

  runuser -u agent -- env \
    HOME="$test_home" \
    PROFILE_REPOSITORY="$profile_repository" \
    bash -c '
      set -euo pipefail
      git init --quiet "$HOME"
      git -C "$HOME" remote add origin "$PROFILE_REPOSITORY"
      mkdir -p "$HOME/.dotfiles"
      printf "nested-parent-sentinel\\n" > "$HOME/.dotfiles/nested-parent-sentinel"
    '

  if runuser -u agent -- env \
    HOME="$test_home" \
    SBX_REPOSITORY_ROOT="$repository" \
    ansible-playbook -i "$inventory" "$profile_playbook" \
      --extra-vars "{\"profile_repository\":\"$profile_repository\"}" >"$test_log" 2>&1; then
    echo 'FAIL: profile playbook accepted a nested non-checkout .dotfiles path.' >&2
    return 1
  fi

  if ! grep -Fq 'not the root of a Git checkout' "$test_log"; then
    echo 'FAIL: nested parent repository did not fail for the root-identity reason.' >&2
    sed -n '1,160p' "$test_log" >&2
    return 1
  fi

  if [[ ! -f "$sentinel" ]] || [[ $(<"$sentinel") != 'nested-parent-sentinel' ]]; then
    echo 'FAIL: nested parent regression changed the sentinel path or contents.' >&2
    return 1
  fi
}

run_user_clone_guard_regression() {
  local test_home test_log profile_clone sentinel before_branch before_head after_branch after_head
  local invocation_failure after_snapshot_failure guard_failure sentinel_failure state_failure
  test_home=$(runuser -u agent -- mktemp -d)
  test_log="$test_home/verify-dev.log"
  profile_clone="$test_home/.dotfiles"
  sentinel="$profile_clone/persistent-sentinel"

  runuser -u agent -- env \
    PROFILE_REPOSITORY="$profile_repository" \
    PROFILE_CLONE="$profile_clone" \
    bash -c '
      set -euo pipefail
      git clone --quiet "$PROFILE_REPOSITORY" "$PROFILE_CLONE"
      printf "persistent-sentinel\\n" > "$PROFILE_CLONE/persistent-sentinel"
      git -C "$PROFILE_CLONE" add persistent-sentinel
    '

  before_branch=$(runuser -u agent -- git -C "$profile_clone" branch --show-current)
  before_head=$(runuser -u agent -- git -C "$profile_clone" rev-parse HEAD)
  runuser -u agent -- git -C "$profile_clone" status --porcelain=v1 --untracked-files=all > "$test_home/before-status"
  runuser -u agent -- git -C "$profile_clone" diff --cached --binary > "$test_home/before-staged"
  runuser -u agent -- git -C "$profile_clone" diff --binary > "$test_home/before-worktree"
  cp -- "$sentinel" "$test_home/before-sentinel"

  invocation_failure=0
  if runuser -u agent -- env \
    HOME="$test_home" \
    SBX_REPOSITORY_ROOT="$repository" \
    bash "$repository/final/scripts/verify-dev.sh" "$profile_repository" >"$test_log" 2>&1; then
    invocation_failure=1
  fi

  after_snapshot_failure=0
  if ! after_branch=$(runuser -u agent -- git -C "$profile_clone" branch --show-current); then
    after_snapshot_failure=1
    after_branch='<unavailable>'
  fi
  if ! after_head=$(runuser -u agent -- git -C "$profile_clone" rev-parse HEAD); then
    after_snapshot_failure=1
    after_head='<unavailable>'
  fi
  if ! runuser -u agent -- git -C "$profile_clone" status --porcelain=v1 --untracked-files=all > "$test_home/after-status"; then
    after_snapshot_failure=1
  fi
  if ! runuser -u agent -- git -C "$profile_clone" diff --cached --binary > "$test_home/after-staged"; then
    after_snapshot_failure=1
  fi
  if ! runuser -u agent -- git -C "$profile_clone" diff --binary > "$test_home/after-worktree"; then
    after_snapshot_failure=1
  fi
  if ! cp -- "$sentinel" "$test_home/after-sentinel"; then
    after_snapshot_failure=1
  fi

  guard_failure=0
  if ! grep -Fq 'SBX_DISPOSABLE_ACCEPTANCE=1' "$test_log"; then
    echo 'FAIL: pre-existing clone did not fail for the disposable-acceptance guard reason.' >&2
    sed -n '1,160p' "$test_log" >&2
    guard_failure=1
  fi

  sentinel_failure=0
  if ! cmp -s "$test_home/before-sentinel" "$test_home/after-sentinel"; then
    echo 'FAIL: unmarked verify-dev.sh invocation changed the persistent clone sentinel.' >&2
    sentinel_failure=1
  fi

  state_failure=0
  if [[ $invocation_failure -ne 0 ]]; then
    echo 'FAIL: unmarked verify-dev.sh invocation accepted a pre-existing clone.' >&2
    state_failure=1
  fi
  if [[ $after_snapshot_failure -ne 0 ]]; then
    echo 'FAIL: could not capture the persistent clone state after unmarked invocation.' >&2
    state_failure=1
  fi
  if [[ "$after_branch" != "$before_branch" ]]; then
    echo 'FAIL: unmarked verify-dev.sh invocation changed the persistent clone branch.' >&2
    state_failure=1
  fi
  if [[ "$after_head" != "$before_head" ]]; then
    echo 'FAIL: unmarked verify-dev.sh invocation changed the persistent clone HEAD.' >&2
    state_failure=1
  fi
  if ! cmp -s "$test_home/before-status" "$test_home/after-status"; then
    echo 'FAIL: unmarked verify-dev.sh invocation changed the persistent clone status.' >&2
    state_failure=1
  fi
  if ! cmp -s "$test_home/before-staged" "$test_home/after-staged"; then
    echo 'FAIL: unmarked verify-dev.sh invocation changed the persistent clone staged diff.' >&2
    state_failure=1
  fi
  if ! cmp -s "$test_home/before-worktree" "$test_home/after-worktree"; then
    echo 'FAIL: unmarked verify-dev.sh invocation changed the persistent clone worktree diff.' >&2
    state_failure=1
  fi

  if [[ $guard_failure -ne 0 || $sentinel_failure -ne 0 || $state_failure -ne 0 ]]; then
    return 1
  fi
}

regression_failures=0
if ! run_nested_parent_repository_regression; then
  regression_failures=$((regression_failures + 1))
fi
if ! run_user_clone_guard_regression; then
  regression_failures=$((regression_failures + 1))
fi
if [[ $regression_failures -ne 0 ]]; then
  echo "FAIL: $regression_failures profile preservation regression(s)." >&2
  exit 1
fi

runuser -u agent -- env \
  HOME=/home/agent \
  SBX_REPOSITORY_ROOT="$repository" \
  SBX_DISPOSABLE_ACCEPTANCE=1 \
  bash "$repository/final/scripts/verify-dev.sh" \
    "$repository/.git"
'@

$arguments = @(
    'run',
    '--rm',
    '--user', 'root',
    '--volume', "$repositoryRoot`:/mnt/sbx-repository:ro",
    '--entrypoint', 'bash',
    $Image,
    '-lc',
    $containerScript
)

& podman @arguments
exit $LASTEXITCODE
