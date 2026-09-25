#!/usr/bin/env bash
# Regression tests for fm-spawn's task-local agent co-author commit-msg hook.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-spawn-commit-msg-hook)

make_fakebin() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "$*" in
  *"#{pane_current_path}"*) printf '%s\n' "${FM_FAKE_PANE_PATH:?FM_FAKE_PANE_PATH unset}"; exit 0 ;;
esac
case "${1:-}" in
  display-message) printf 'firstmate\n'; exit 0 ;;
  list-windows|has-session|new-session|new-window|kill-window|send-keys) exit 0 ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  cat > "$fakebin/treehouse" <<'SH'
#!/usr/bin/env bash
if [ "${1:-} ${2:-}" = "status --json" ]; then
  printf '[{"path":"%s","status":"in-use","lease_id":"","lease_holder":"","leased_at":null,"processes":[]}]\n' \
    "${FM_FAKE_PANE_PATH:?FM_FAKE_PANE_PATH unset}"
  exit 0
fi
if [ "${1:-} ${2:-}" = "status --help" ]; then
  printf '%s\n' 'Usage: treehouse status --json'
fi
exit 0
SH
  chmod +x "$fakebin/treehouse"
  printf '%s\n' "$fakebin"
}

make_case() {
  CASE_DIR="$TMP_ROOT/case"
  HOME_DIR="$CASE_DIR/home"
  PROJECT_DIR="$CASE_DIR/project"
  WORKTREE_DIR="$CASE_DIR/worktree"
  FAKEBIN_DIR=$(make_fakebin "$CASE_DIR/fake")
  mkdir -p "$HOME_DIR/data/hook-first-z1" "$HOME_DIR/data/hook-second-z2" \
    "$HOME_DIR/projects" "$HOME_DIR/state" "$HOME_DIR/config"
  printf 'brief for first hook spawn\n' > "$HOME_DIR/data/hook-first-z1/brief.md"
  printf 'brief for second hook spawn\n' > "$HOME_DIR/data/hook-second-z2/brief.md"
  touch "$HOME_DIR/state/.last-watcher-beat"
  fm_git_worktree "$PROJECT_DIR" "$WORKTREE_DIR" hook-test
}

run_spawn() {
  local id=$1
  FM_ROOT_OVERRIDE='' FM_HOME="$HOME_DIR" \
    FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
    FM_PROJECTS_OVERRIDE="$HOME_DIR/projects" FM_CONFIG_OVERRIDE="$HOME_DIR/config" \
    FM_SPAWN_NO_GUARD=1 TMUX="fake,1,0" FM_FAKE_PANE_PATH="$WORKTREE_DIR" \
    PATH="$FAKEBIN_DIR:$PATH" \
    "$SPAWN" "$id" "$PROJECT_DIR" --scout --harness codex 2>&1
}

test_spawn_installs_scoped_hook_and_filters_only_agents() {
  local out status hook message
  out=$(run_spawn hook-first-z1)
  status=$?
  expect_code 0 "$status" "spawn should install the commit-msg hook"
  assert_contains "$out" "spawned hook-first-z1" "spawn did not report success"

  hook="$WORKTREE_DIR/.fm-git-hooks/commit-msg"
  [ -x "$hook" ] || fail "spawn did not install an executable task-local commit-msg hook"
  [ "$(git -C "$WORKTREE_DIR" config --worktree --get core.hooksPath)" = .fm-git-hooks ] \
    || fail "task worktree does not use its task-local hooks path"
  [ -z "$(git -C "$PROJECT_DIR" config --worktree --get core.hooksPath 2>/dev/null || true)" ] \
    || fail "spawn changed the primary checkout's worktree-local hooks path"

  printf 'hook behavior\n' > "$WORKTREE_DIR/hook-behavior.txt"
  git -C "$WORKTREE_DIR" add hook-behavior.txt
  git -C "$WORKTREE_DIR" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' \
    commit -q -m 'exercise task-local hook' \
    -m 'Co-authored-by: Cursor <cursoragent@cursor.com>' \
    -m 'Co-authored-by: Kun Chen <3233006+kunchenguid@users.noreply.github.com>'
  message=$(git -C "$WORKTREE_DIR" log -1 --format=%B)
  assert_not_contains "$message" "cursoragent@cursor.com" \
    "task-local hook allowed the confirmed Cursor agent trailer into a commit"
  assert_contains "$message" "Co-authored-by: Kun Chen <3233006+kunchenguid@users.noreply.github.com>" \
    "task-local hook removed a legitimate human co-author"
  pass "spawn binds an executable hook only to the task worktree and real commits keep human co-authors"
}

test_hook_is_idempotently_replaced_for_reused_worktree() {
  local out status hook saved
  hook="$WORKTREE_DIR/.fm-git-hooks/commit-msg"
  saved="$CASE_DIR/expected-commit-msg"
  cp "$hook" "$saved"
  printf '%s\n' '#!/bin/sh' 'exit 99' > "$hook"
  printf 'stale material\n' > "$WORKTREE_DIR/.fm-git-hooks/stale-file"

  out=$(run_spawn hook-second-z2)
  status=$?
  expect_code 0 "$status" "a reused worktree should replace stale hook material"
  assert_contains "$out" "spawned hook-second-z2" "reused-worktree spawn did not report success"
  cmp -s "$saved" "$hook" || fail "reused-worktree spawn did not restore the canonical hook"
  assert_absent "$WORKTREE_DIR/.fm-git-hooks/stale-file" \
    "reused-worktree spawn retained stale hook-directory material"
  pass "repeated installation atomically replaces stale task-local hook material"
}

test_project_hooks_still_run_in_task_worktree() {
  local project_hooks message
  project_hooks=$(cd "$PROJECT_DIR" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/hooks
  mkdir -p "$project_hooks"
  # shellcheck disable=SC2016 # literal hook script text
  printf '%s\n' '#!/bin/sh' '[ -z "${FM_TEST_BLOCK_COMMIT:-}" ]' > "$project_hooks/pre-commit"
  # shellcheck disable=SC2016 # literal hook script text
  printf '%s\n' '#!/bin/sh' 'printf "Project-hook: ran\n" >> "$1"' > "$project_hooks/commit-msg"
  chmod +x "$project_hooks/pre-commit" "$project_hooks/commit-msg"

  printf 'blocked change\n' > "$WORKTREE_DIR/project-hook.txt"
  git -C "$WORKTREE_DIR" add project-hook.txt
  FM_TEST_BLOCK_COMMIT=1 git -C "$WORKTREE_DIR" -c user.name='Firstmate Tests' \
    -c user.email='tests@example.invalid' commit -q -m 'blocked by project hook' >/dev/null 2>&1 \
    && fail "task-local hooks path bypassed the project's pre-commit hook"

  git -C "$WORKTREE_DIR" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' \
    commit -q -m 'project hooks chain' -m 'Co-authored-by: Cursor <cursoragent@cursor.com>'
  expect_code 0 "$?" "commit should succeed when the project hook allows it"
  message=$(git -C "$WORKTREE_DIR" log -1 --format=%B)
  assert_not_contains "$message" "cursoragent@cursor.com" \
    "chained project commit-msg hook replaced the agent co-author filter"
  assert_contains "$message" "Project-hook: ran" \
    "task-local commit-msg hook did not chain to the project's commit-msg hook"
  rm -f "$project_hooks/pre-commit" "$project_hooks/commit-msg"
  pass "project pre-commit and commit-msg hooks still run inside the task worktree"
}

test_project_hooks_path_set_after_spawn_is_chained() {
  local message
  mkdir -p "$WORKTREE_DIR/.late-hooks"
  # shellcheck disable=SC2016 # literal hook script text
  printf '%s\n' '#!/bin/sh' 'printf "Late-hook: ran\n" >> "$1"' > "$WORKTREE_DIR/.late-hooks/commit-msg"
  chmod +x "$WORKTREE_DIR/.late-hooks/commit-msg"
  git -C "$WORKTREE_DIR" config --local core.hooksPath .late-hooks

  printf 'late hooks path\n' > "$WORKTREE_DIR/late-hook.txt"
  git -C "$WORKTREE_DIR" add late-hook.txt
  git -C "$WORKTREE_DIR" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' \
    commit -q -m 'late project hooks path' -m 'Co-authored-by: Cursor <cursoragent@cursor.com>'
  expect_code 0 "$?" "commit should succeed with a project hooks path configured after spawn"
  git -C "$WORKTREE_DIR" config --local --unset core.hooksPath
  message=$(git -C "$WORKTREE_DIR" log -1 --format=%B)
  assert_not_contains "$message" "cursoragent@cursor.com" \
    "late project hooks path replaced the agent co-author filter"
  assert_contains "$message" "Late-hook: ran" \
    "task-local commit-msg hook ignored a project hooks path configured after spawn"
  pass "a project hooks path configured after spawn is still chained"
}

test_known_agent_identities_are_removed_without_other_edits() {
  local hook before after expected
  hook="$WORKTREE_DIR/.fm-git-hooks/commit-msg"
  before="$CASE_DIR/known-identities.before"
  after="$CASE_DIR/known-identities.after"
  expected="$CASE_DIR/known-identities.expected"
  cat > "$before" <<'MSG'
subject

body stays byte-for-byte

Co-authored-by: Cursor <cursoragent@cursor.com>
Co-authored-by: Claude Opus <noreply@anthropic.com>
Co-authored-by: Codex <noreply@openai.com>
Co-authored-by: OpenCode <noreply@opencode.ai>
Co-authored-by: Claude Sonnet 4 <noreply@pi.dev>
 Co-authored-by: Cursor <cursoragent@cursor.com>
Co-authored-by: Kun Chen <3233006+kunchenguid@users.noreply.github.com>
MSG
  cat > "$expected" <<'MSG'
subject

body stays byte-for-byte

 Co-authored-by: Cursor <cursoragent@cursor.com>
Co-authored-by: Kun Chen <3233006+kunchenguid@users.noreply.github.com>
MSG
  cp "$before" "$after"
  "$hook" "$after"
  expect_code 0 "$?" "hook should succeed after filtering known agent identities"
  cmp -s "$expected" "$after" \
    || fail "hook changed content beyond known agent co-author lines"
  pass "known Cursor, Claude, Codex, OpenCode, and Pi identities are removed exactly"
}

test_hook_fails_open_for_unexpected_inputs() {
  local hook missing_dep unreadable malformed original empty_path
  hook="$WORKTREE_DIR/.fm-git-hooks/commit-msg"
  empty_path="$CASE_DIR/empty-path"
  mkdir -p "$empty_path"

  missing_dep="$CASE_DIR/missing-dependency-message"
  printf '%s\n' 'subject' '' 'Co-authored-by: Cursor <cursoragent@cursor.com>' > "$missing_dep"
  cp "$missing_dep" "$missing_dep.expected"
  PATH="$empty_path" /bin/sh "$hook" "$missing_dep"
  expect_code 0 "$?" "hook should allow the commit when a dependency is missing"
  cmp -s "$missing_dep.expected" "$missing_dep" \
    || fail "missing-dependency path changed the commit message"

  unreadable="$CASE_DIR/unreadable-message"
  printf '%s\n' 'subject' '' 'Co-authored-by: Cursor <cursoragent@cursor.com>' > "$unreadable"
  cp "$unreadable" "$unreadable.expected"
  chmod 000 "$unreadable"
  "$hook" "$unreadable"
  status=$?
  chmod 600 "$unreadable"
  expect_code 0 "$status" "hook should allow the commit when the message is unreadable"
  cmp -s "$unreadable.expected" "$unreadable" \
    || fail "unreadable-message path changed the commit message"

  malformed="$CASE_DIR/malformed-message"
  printf 'subject\000malformed payload\n' > "$malformed"
  cp "$malformed" "$malformed.expected"
  "$hook" "$malformed"
  expect_code 0 "$?" "hook should allow a malformed message it cannot safely filter"
  cmp -s "$malformed.expected" "$malformed" \
    || fail "malformed-message path changed the commit message"

  original="$CASE_DIR/not-a-message"
  mkdir -p "$original"
  "$hook" "$original"
  expect_code 0 "$?" "hook should allow the commit when given a non-file message path"
  pass "missing dependencies and unreadable or malformed inputs leave messages untouched and exit zero"
}

make_case
test_spawn_installs_scoped_hook_and_filters_only_agents
test_hook_is_idempotently_replaced_for_reused_worktree
test_project_hooks_still_run_in_task_worktree
test_project_hooks_path_set_after_spawn_is_chained
test_known_agent_identities_are_removed_without_other_edits
test_hook_fails_open_for_unexpected_inputs

echo "# all fm-spawn commit-msg hook tests passed"
