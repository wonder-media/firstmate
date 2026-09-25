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
  pass "private cached App token is passed only through the GitHub command environment"
}

test_stale_cache_refresh_writes_private_cache() {
  local dir output cache
  dir=$(make_case refresh)
  cache="$dir/home/state/github-app-installation-token.json"
  node -e '
    const { generateKeyPairSync } = require("crypto");
    const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
    process.stdout.write(privateKey.export({ type: "pkcs8", format: "pem" }));
  ' > "$dir/app.pem"
  printf '{"app_id":1,"installation_id":2,"private_key_file":"app.pem"}\n' > "$dir/credentials.json"
  printf '%s\n' "$dir/credentials.json" > "$dir/home/config/github-app-credentials"
  printf '{"token":"stale-installation-token-000000","expires_at":"2000-01-01T00:00:00Z"}\n' > "$cache"
  chmod 0644 "$cache"
  cat > "$dir/stub-https.js" <<'JS'
const https = require('https');
const { EventEmitter } = require('events');
https.request = (options, onResponse) => {
  const request = new EventEmitter();
  request.destroy = () => {};
  request.end = () => {
    const response = new EventEmitter();
    response.statusCode = options.path === '/app/installations/2/access_tokens'
      && /^Bearer [^.]+\.[^.]+\.[^.]+$/.test(options.headers.Authorization) ? 201 : 401;
    response.setEncoding = () => {};
    onResponse(response);
    const expires = new Date(Date.now() + 3600 * 1000).toISOString();
    response.emit('data', JSON.stringify({ token: 'fixture-installation-token-1234567890', expires_at: expires }));
    response.emit('end');
  };
  return request;
};
JS

  output=$(NODE_OPTIONS="--require $dir/stub-https.js" run_helper "$dir" run-safe gh pr view 22)
  [ "$output" = command-output ] || fail "refreshed App token changed command stdout"
  grep -qxF "gh_token=$FAKE_APP_TOKEN" "$dir/command.log" \
    || fail "stale cache was not refreshed with a newly minted App token"
  [ "$(file_mode "$cache")" = 600 ] || fail "helper did not write the App token cache at mode 0600"
  grep -qF "$FAKE_APP_TOKEN" "$cache" || fail "helper did not persist the refreshed App token"
  pass "stale App token cache is refreshed and rewritten at mode 0600"
}

test_app_request_failure_retries_on_captain_login() {
  local dir expires output rc
  dir=$(make_case app-scope)
  printf '%s\n' "$dir/credentials.json" > "$dir/home/config/github-app-credentials"
  expires=$(date -u -v+30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ)
  printf '{"token":"%s","expires_at":"%s"}\n' "$FAKE_APP_TOKEN" "$expires" \
    > "$dir/home/state/github-app-installation-token.json"
  chmod 0600 "$dir/home/state/github-app-installation-token.json"
  cat > "$dir/fakebin/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh_token=%s\n' "${GH_TOKEN:-}" >> "$FM_TEST_COMMAND_LOG"
if [ "${GH_TOKEN:-}" = fixture-installation-token-1234567890 ]; then
  printf 'app-partial-output\n'
  printf 'GraphQL: Could not resolve to a Repository\n' >&2
  exit 1
fi
printf '%s\n' MERGED
SH
  chmod +x "$dir/fakebin/gh"

  set +e
  output=$(GH_TOKEN=personal-token run_helper "$dir" run-safe gh pr view 22 2> "$dir/stderr")
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || fail "App request failure was not retried on the captain login"
  [ "$output" = MERGED ] || fail "App request failure leaked the failed attempt's stdout"
  [ "$(grep -c '^gh_token=' "$dir/command.log")" -eq 2 ] || fail "App request failure did not retry exactly once"
  sed -n 2p "$dir/command.log" | grep -qxF 'gh_token=personal-token' \
    || fail "App request failure retry did not use the captain login"
  [ "$(cat "$dir/stderr")" = 'warning: GitHub App installation cannot reach this repository; retrying with captain GitHub login' ] \
    || fail "App request failure did not emit exactly one safe diagnostic"

  output=$(FM_HOME="$dir/home" FM_TEST_COMMAND_LOG="$dir/command.log" \
    PATH="$dir/fakebin:$PATH" "$POLL" --validated github \
    https://github.com/wonder-media/firstmate/pull/22 github.com wonder-media/firstmate 22)
  [ "$output" = merged ] || fail "merge poll missed a merge the App installation cannot see"
  pass "App installation that cannot reach the repository retries once on the captain login"
}

test_other_app_failure_surfaces_without_retry() {
  local dir expires output rc
  dir=$(make_case app-merge-refused)
  printf '%s\n' "$dir/credentials.json" > "$dir/home/config/github-app-credentials"
  expires=$(date -u -v+30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ)
  printf '{"token":"%s","expires_at":"%s"}\n' "$FAKE_APP_TOKEN" "$expires" \
    > "$dir/home/state/github-app-installation-token.json"
  chmod 0600 "$dir/home/state/github-app-installation-token.json"
  cat > "$dir/fakebin/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh_token=%s\n' "${GH_TOKEN:-}" >> "$FM_TEST_COMMAND_LOG"
printf 'merge-attempt-output\n'
printf 'Pull request is not mergeable: the merge commit cannot be cleanly created\n' >&2
exit 3
SH
  chmod +x "$dir/fakebin/gh"

  set +e
  output=$(GH_TOKEN=personal-token run_helper "$dir" run-safe gh pr merge 22 2> "$dir/stderr")
  rc=$?
  set -e
  [ "$rc" -eq 3 ] || fail "ordinary App failure changed the command exit status"
  [ "$output" = merge-attempt-output ] || fail "ordinary App failure hid the command stdout"
  [ "$(grep -c '^gh_token=' "$dir/command.log")" -eq 1 ] || fail "ordinary App failure was retried"
  [ "$(cat "$dir/stderr")" = 'Pull request is not mergeable: the merge commit cannot be cleanly created' ] \
    || fail "ordinary App failure did not surface only its real error"
  pass "ordinary App-authenticated failure surfaces once without a captain-login retry"
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

  output=$(run_helper "$dir" run-safe gh pr list)
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
  local dir rc group
  dir=$(make_case projects)
  for group in project run api; do
    set +e
    run_helper "$dir" run-safe gh "$group" list > "$dir/stdout" 2> "$dir/stderr"
    rc=$?
    set -e
    [ "$rc" -eq 2 ] || fail "gh $group command was not rejected by the App wrapper"
    [ ! -s "$dir/command.log" ] || fail "gh $group command reached gh through the App wrapper"
    grep -qxF 'error: GitHub App authentication is not approved for this command' "$dir/stderr" \
      || fail "gh $group rejection diagnostic changed"
  done
  pass "Projects v2 and non-allowlisted groups cannot run through App authentication"
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
test_stale_cache_refresh_writes_private_cache
test_mint_output_never_enters_argv
test_configured_failure_falls_back_once
test_app_request_failure_retries_on_captain_login
test_other_app_failure_surfaces_without_retry
test_projects_are_rejected_before_execution
test_merge_poll_uses_app_identity
test_pointer_inherits_without_credentials

printf '# all fm-github-app-token tests passed\n'
