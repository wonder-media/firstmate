#!/usr/bin/env bash
# Behavior tests for opt-in GitHub App authentication and fail-safe fallback.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-config-inherit-lib.sh
. "$ROOT/bin/fm-config-inherit-lib.sh"

HELPER="$ROOT/bin/fm-github-app-token.sh"
POLL="$ROOT/bin/fm-pr-poll.sh"
TMP_ROOT=$(fm_test_tmproot fm-github-app-token)
FAKE_APP_TOKEN='fixture-installation-token-1234567890'

file_mode() {
  if [ "$(uname)" = Darwin ]; then
    stat -f %Lp "$1"
  else
    stat -c %a "$1"
  fi
}

make_case() {
  local name=$1 dir
  dir="$TMP_ROOT/$name"
  mkdir -p "$dir/home/config" "$dir/home/state" "$dir/fakebin"
  cat > "$dir/fakebin/gh" <<'SH'
#!/usr/bin/env bash
printf 'args=%s\n' "$*" >> "$FM_TEST_COMMAND_LOG"
printf 'gh_token=%s\n' "${GH_TOKEN:-}" >> "$FM_TEST_COMMAND_LOG"
printf 'github_token=%s\n' "${GITHUB_TOKEN:-}" >> "$FM_TEST_COMMAND_LOG"
printf 'command-output\n'
SH
  chmod +x "$dir/fakebin/gh"
  : > "$dir/command.log"
  printf '%s\n' "$dir"
}

run_helper() {
  local dir=$1
  shift
  FM_HOME="$dir/home" FM_TEST_COMMAND_LOG="$dir/command.log" \
    PATH="$dir/fakebin:$PATH" "$HELPER" "$@"
}

test_absent_pointer_is_transparent() {
  local dir output
  dir=$(make_case absent)
  output=$(GH_TOKEN=personal-token GITHUB_TOKEN=personal-github-token \
    run_helper "$dir" run-safe gh pr list --repo wonder-media/firstmate)
  [ "$output" = command-output ] || fail "absent pointer changed command stdout"
  grep -qxF 'args=pr list --repo wonder-media/firstmate' "$dir/command.log" \
    || fail "absent pointer changed command arguments"
  grep -qxF 'gh_token=personal-token' "$dir/command.log" \
    || fail "absent pointer changed GH_TOKEN"
  grep -qxF 'github_token=personal-github-token' "$dir/command.log" \
    || fail "absent pointer changed GITHUB_TOKEN"
  pass "absent GitHub App pointer preserves the prior command environment and output"
}

test_private_cache_supplies_app_identity() {
  local dir expires output
  dir=$(make_case cached)
  printf '%s\n' "$dir/credentials.json" > "$dir/home/config/github-app-credentials"
  expires=$(date -u -v+30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ)
  printf '{"token":"%s","expires_at":"%s"}\n' "$FAKE_APP_TOKEN" "$expires" \
    > "$dir/home/state/github-app-installation-token.json"
  chmod 0600 "$dir/home/state/github-app-installation-token.json"

  output=$(GH_TOKEN=personal-token GITHUB_TOKEN=personal-github-token \
    run_helper "$dir" run-safe gh pr view 22)
  [ "$output" = command-output ] || fail "cached App token changed command stdout"
  grep -qxF "gh_token=$FAKE_APP_TOKEN" "$dir/command.log" \
    || fail "cached App token did not become GH_TOKEN"
  grep -qxF "github_token=$FAKE_APP_TOKEN" "$dir/command.log" \
    || fail "cached App token did not become GITHUB_TOKEN"
  assert_no_grep "$FAKE_APP_TOKEN" <(grep '^args=' "$dir/command.log") \
    "App token appeared in command arguments"
  [ "$(file_mode "$dir/home/state/github-app-installation-token.json")" = 600 ] \
    || fail "App token cache was not mode 0600"
  pass "private cached App token is passed only through the GitHub command environment"
}

test_mint_output_never_enters_argv() {
  local dir output
  dir=$(make_case mint)
  printf '%s\n' "$dir/credentials.json" > "$dir/home/config/github-app-credentials"
  cat > "$dir/fakebin/node" <<'SH'
#!/usr/bin/env bash
printf 'node_args=%s\n' "$*" >> "$FM_TEST_COMMAND_LOG"
printf '%s\n' 'fixture-installation-token-1234567890'
SH
  chmod +x "$dir/fakebin/node"

  output=$(run_helper "$dir" run-safe gh run list)
  [ "$output" = command-output ] || fail "minted App token changed command stdout"
  grep -qxF 'node_args=' "$dir/command.log" || fail "token minter received argv"
  grep -qxF "gh_token=$FAKE_APP_TOKEN" "$dir/command.log" \
    || fail "minted App token did not reach the GitHub command"
  assert_no_grep "$FAKE_APP_TOKEN" <(grep -E '^(args|node_args)=' "$dir/command.log") \
    "minted App token appeared in argv"
  pass "minting and GitHub execution keep key and token material out of argv"
}

test_configured_failure_falls_back_once() {
  local dir output rc
  dir=$(make_case fallback)
  printf '%s\n' "$dir/missing-credentials.json" > "$dir/home/config/github-app-credentials"
  set +e
  output=$(GH_TOKEN=personal-token GITHUB_TOKEN=personal-github-token \
    run_helper "$dir" run-safe gh pr list 2> "$dir/stderr")
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || fail "configured App failure blocked the GitHub command"
  [ "$output" = command-output ] || fail "configured App failure changed command stdout"
  [ "$(grep -c '^warning: GitHub App authentication unavailable; using captain GitHub login$' "$dir/stderr")" -eq 1 ] \
    || fail "configured App failure did not emit exactly one safe diagnostic"
  grep -qxF 'gh_token=personal-token' "$dir/command.log" \
    || fail "configured App failure did not preserve captain GH_TOKEN"
  assert_no_grep 'missing-credentials' "$dir/stderr" \
    "configured App failure exposed a credential path"
  pass "App authentication failure falls back once without blocking the command"
}

test_projects_are_rejected_before_execution() {
  local dir rc
  dir=$(make_case projects)
  set +e
  run_helper "$dir" run-safe gh project list > "$dir/stdout" 2> "$dir/stderr"
  rc=$?
  set -e
  [ "$rc" -eq 2 ] || fail "Projects v2 command was not rejected by the App wrapper"
  [ ! -s "$dir/command.log" ] || fail "Projects v2 command reached gh through the App wrapper"
  grep -qxF 'error: GitHub App authentication is not approved for this command' "$dir/stderr" \
    || fail "Projects v2 rejection diagnostic changed"
  pass "Projects v2 cannot accidentally run through App authentication"
}

test_merge_poll_uses_app_identity() {
  local dir expires output
  dir=$(make_case merge-poll)
  printf '%s\n' "$dir/credentials.json" > "$dir/home/config/github-app-credentials"
  expires=$(date -u -v+30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ)
  printf '{"token":"%s","expires_at":"%s"}\n' "$FAKE_APP_TOKEN" "$expires" \
    > "$dir/home/state/github-app-installation-token.json"
  chmod 0600 "$dir/home/state/github-app-installation-token.json"
  cat > "$dir/fakebin/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh_token=%s\n' "${GH_TOKEN:-}" >> "$FM_TEST_COMMAND_LOG"
printf '%s\n' MERGED
SH
  chmod +x "$dir/fakebin/gh"

  output=$(FM_HOME="$dir/home" FM_TEST_COMMAND_LOG="$dir/command.log" \
    PATH="$dir/fakebin:$PATH" "$POLL" --validated github \
    https://github.com/wonder-media/firstmate/pull/22 github.com wonder-media/firstmate 22)
  [ "$output" = merged ] || fail "merge poll did not report the App-authenticated merged state"
  grep -qxF "gh_token=$FAKE_APP_TOKEN" "$dir/command.log" \
    || fail "merge poll did not use App authentication"
  pass "watcher merge poll uses App authentication"
}

test_pointer_inherits_without_credentials() {
  local dir credential_path
  dir=$(make_case inheritance)
  credential_path="$dir/external-vault/fleet-app.json"
  printf '%s\n' "$credential_path" > "$dir/home/config/github-app-credentials"
  mkdir -p "$dir/second/config"

  propagate_inheritable_config "$dir/home/config" "$dir/second/config" \
    || fail "GitHub App pointer inheritance failed"
  cmp -s "$dir/home/config/github-app-credentials" "$dir/second/config/github-app-credentials" \
    || fail "GitHub App pointer did not inherit byte-exact"
  [ ! -e "$dir/second/config/fleet-app.json" ] \
    || fail "GitHub App credential material was copied into the secondmate home"
  rm -f "$dir/home/config/github-app-credentials"
  propagate_inheritable_config "$dir/home/config" "$dir/second/config" \
    || fail "GitHub App pointer absence convergence failed"
  [ ! -e "$dir/second/config/github-app-credentials" ] \
    || fail "primary pointer absence did not clear the secondmate pointer"
  pass "secondmate inheritance copies only the external credential pointer"
}

test_absent_pointer_is_transparent
test_private_cache_supplies_app_identity
test_mint_output_never_enters_argv
test_configured_failure_falls_back_once
test_projects_are_rejected_before_execution
test_merge_poll_uses_app_identity
test_pointer_inherits_without_credentials

printf '# all fm-github-app-token tests passed\n'
