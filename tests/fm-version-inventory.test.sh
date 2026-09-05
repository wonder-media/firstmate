#!/usr/bin/env bash
# Behavior tests for the explicit maintenance version inventory.
#
# Every release lookup is served by deterministic local fakes. The suite proves
# exact owning channels, compatibility/freshness separation, intentional CI pins,
# offline behavior, and hard request bounds without contacting a real network.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BASE_PATH=${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
TMP_ROOT=$(fm_test_tmproot fm-version-inventory)

make_fake_tools() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/gh-axi" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then printf '%s\n' 'gh-axi 0.1.35'; exit 0; fi
printf '%s\n' "${GH_REPO:-missing}" >> "${FM_FAKE_GITHUB_LOG:?}"
case "${GH_REPO:-}" in
  kunchenguid/no-mistakes) version=1.64.0 ;;
  kunchenguid/treehouse) version=2.3.0 ;;
  ogulcancelik/herdr) version=0.8.2 ;;
  *) exit 9 ;;
esac
printf 'releases[1]{tag,name,draft,prerelease,published}:\n  v%s,v%s,no,no,now\n' "$version" "$version"
SH
  cat > "$fakebin/npm" <<'SH'
#!/usr/bin/env bash
package=${2:-}
printf '%s\n' "$package" >> "${FM_FAKE_NPM_LOG:?}"
case "$package" in
  gh-axi) printf '%s\n' 0.1.35 ;;
  chrome-devtools-axi) printf '%s\n' 0.1.34 ;;
  lavish-axi) printf '%s\n' 0.1.64 ;;
  tasks-axi) printf '%s\n' 0.2.5 ;;
  quota-axi) printf '%s\n' 0.1.37 ;;
  *) exit 9 ;;
esac
SH
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'no-mistakes version v1.31.2'
SH
  cat > "$fakebin/treehouse" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then printf '%s\n' 'v2.0.1'; exit 0; fi
if [ "${1:-} ${2:-}" = 'get --help' ]; then printf '%s\n' 'treehouse get [--lease]'; exit 0; fi
exit 9
SH
  cat > "$fakebin/herdr" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then printf '%s\n' 'herdr 0.7.4'; exit 0; fi
printf '%s\n' "unexpected live herdr command: $*" >&2
exit 9
SH
  cat > "$fakebin/chrome-devtools-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'chrome-devtools-axi 0.1.34'
SH
  cat > "$fakebin/lavish-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'lavish-axi 0.1.46'
SH
  cat > "$fakebin/tasks-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'tasks-axi 0.2.3'
SH
  cat > "$fakebin/quota-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'quota-axi 0.1.38'
SH
  chmod +x "$fakebin"/*
  printf '%s\n' "$fakebin"
}

assert_row() {  # <output> <exact row>
  printf '%s\n' "$1" | grep -Fx "$2" >/dev/null \
    || fail "missing inventory row: $2"
}

test_inventory_separates_compatibility_freshness_and_pins() {
  local dir fakebin github_log npm_log out
  dir="$TMP_ROOT/main"
  mkdir -p "$dir"
  github_log="$dir/github.log"
  npm_log="$dir/npm.log"
  : > "$github_log"
  : > "$npm_log"
  fakebin=$(make_fake_tools "$dir")
  out=$(PATH="$fakebin:$BASE_PATH" FM_FAKE_GITHUB_LOG="$github_log" FM_FAKE_NPM_LOG="$npm_log" \
    "$ROOT/bin/fm-version-inventory.sh")

  assert_row "$out" $'no-mistakes\t1.31.2\t1.31.2\t1.64.0\tsupported\tupdate-available\tnone\tgithub:kunchenguid/no-mistakes'
  assert_row "$out" $'treehouse\t2.0.1\tlease-capable\t2.3.0\tsupported\tintentionally-pinned\tCI=2.0.1\tgithub:kunchenguid/treehouse'
  assert_row "$out" $'herdr\t0.7.4\tprotocol>=14\t0.8.2\tunknown (protocol not probed)\tintentionally-pinned\tCI=0.7.4\tgithub:ogulcancelik/herdr'
  assert_row "$out" $'gh-axi\t0.1.35\t0.1.29\t0.1.35\tsupported\tcurrent-stable\tnone\tnpm:gh-axi'
  assert_row "$out" $'chrome-devtools-axi\t0.1.34\tpresent\t0.1.34\tsupported\tcurrent-stable\tnone\tnpm:chrome-devtools-axi'
  assert_row "$out" $'lavish-axi\t0.1.46\t0.1.46\t0.1.64\tsupported\tupdate-available\tnone\tnpm:lavish-axi'
  assert_row "$out" $'tasks-axi\t0.2.3\t0.2.4\t0.2.5\tbelow-minimum\tupdate-available\tnone\tnpm:tasks-axi'
  assert_row "$out" $'quota-axi\t0.1.38\t0.1.25\t0.1.37\tsupported\tahead-of-stable\tnone\tnpm:quota-axi'
  [ "$(cat "$github_log")" = $'kunchenguid/no-mistakes\nkunchenguid/treehouse\nogulcancelik/herdr' ] \
    || fail "GitHub release channels were not exact: $(cat "$github_log")"
  [ "$(cat "$npm_log")" = $'gh-axi\nchrome-devtools-axi\nlavish-axi\ntasks-axi\nquota-axi' ] \
    || fail "npm release channels were not exact: $(cat "$npm_log")"
  pass "version inventory separates compatibility, stable freshness, and intentional pins"
}

test_offline_inventory_never_calls_release_channels() {
  local dir fakebin github_log npm_log out
  dir="$TMP_ROOT/offline"
  mkdir -p "$dir"
  github_log="$dir/github.log"
  npm_log="$dir/npm.log"
  : > "$github_log"
  : > "$npm_log"
  fakebin=$(make_fake_tools "$dir")
  out=$(PATH="$fakebin:$BASE_PATH" FM_FAKE_GITHUB_LOG="$github_log" FM_FAKE_NPM_LOG="$npm_log" \
    "$ROOT/bin/fm-version-inventory.sh" --offline)

  [ ! -s "$github_log" ] || fail "offline inventory called a GitHub release channel"
  [ ! -s "$npm_log" ] || fail "offline inventory called npm"
  [ "$(printf '%s\n' "$out" | grep -c $'\tunknown/offline\t')" -eq 8 ] \
    || fail "offline inventory did not distinguish every unavailable stable version"
  pass "offline inventory reports unknown/offline without any release request"
}

test_release_request_is_hard_bounded() {
  local dir fakebin github_log npm_log out started ended elapsed
  dir="$TMP_ROOT/bounded"
  mkdir -p "$dir"
  github_log="$dir/github.log"
  npm_log="$dir/npm.log"
  : > "$github_log"
  : > "$npm_log"
  fakebin=$(make_fake_tools "$dir")
  cat > "$fakebin/gh-axi" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then printf '%s\n' 'gh-axi 0.1.35'; exit 0; fi
sleep 30
SH
  chmod +x "$fakebin/gh-axi"
  started=$(date +%s)
  out=$(PATH="$fakebin:$BASE_PATH" FM_FAKE_GITHUB_LOG="$github_log" FM_FAKE_NPM_LOG="$npm_log" \
    FM_VERSION_INVENTORY_TIMEOUT=1 "$ROOT/bin/fm-version-inventory.sh")
  ended=$(date +%s)
  elapsed=$((ended - started))

  [ "$elapsed" -lt 10 ] || fail "three bounded GitHub requests ran for ${elapsed}s"
  assert_row "$out" $'no-mistakes\t1.31.2\t1.31.2\tunknown/offline\tsupported\tunknown/offline\tnone\tgithub:kunchenguid/no-mistakes'
  assert_row "$out" $'treehouse\t2.0.1\tlease-capable\tunknown/offline\tsupported\tunknown/offline\tCI=2.0.1\tgithub:kunchenguid/treehouse'
  pass "each release-channel request is hard bounded and degrades to unknown/offline"
}

test_multi_digit_versions_parse_whole() {
  local dir fakebin github_log npm_log out
  dir="$TMP_ROOT/multi-digit"
  mkdir -p "$dir"
  github_log="$dir/github.log"
  npm_log="$dir/npm.log"
  : > "$github_log"
  : > "$npm_log"
  fakebin=$(make_fake_tools "$dir")
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'no-mistakes version v12.3.4'
SH
  cat > "$fakebin/tasks-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'tasks-axi 10.20.30'
SH
  cat > "$fakebin/npm" <<'SH'
#!/usr/bin/env bash
package=${2:-}
printf '%s\n' "$package" >> "${FM_FAKE_NPM_LOG:?}"
case "$package" in
  gh-axi) printf '%s\n' 0.1.35 ;;
  chrome-devtools-axi) printf '%s\n' 0.1.34 ;;
  lavish-axi) printf '%s\n' 0.1.64 ;;
  tasks-axi) printf '%s\n' 11.0.0 ;;
  quota-axi) printf '%s\n' 0.1.37 ;;
  *) exit 9 ;;
esac
SH
  chmod +x "$fakebin/no-mistakes" "$fakebin/tasks-axi" "$fakebin/npm"
  out=$(PATH="$fakebin:$BASE_PATH" FM_FAKE_GITHUB_LOG="$github_log" FM_FAKE_NPM_LOG="$npm_log" \
    "$ROOT/bin/fm-version-inventory.sh")

  assert_row "$out" $'no-mistakes\t12.3.4\t1.31.2\t1.64.0\tsupported\tahead-of-stable\tnone\tgithub:kunchenguid/no-mistakes'
  assert_row "$out" $'tasks-axi\t10.20.30\t0.2.4\t11.0.0\tsupported\tupdate-available\tnone\tnpm:tasks-axi'
  pass "multi-digit installed and available versions are parsed whole"
}

test_inventory_separates_compatibility_freshness_and_pins
test_offline_inventory_never_calls_release_channels
test_release_request_is_hard_bounded
test_multi_digit_versions_parse_whole

echo "# all fm-version-inventory tests passed"
