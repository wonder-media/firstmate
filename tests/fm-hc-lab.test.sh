#!/usr/bin/env bash
# Public lab CLI regressions. Oracle: roots must exclude untrusted writers,
# sessions must never be adopted, and incomplete inventories cannot verify.
# Command stubs inject filesystem failures, not expected inventory contents.
set -eu
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-hc-lab-tests)
LAB=${1:-$ROOT/bin/fm-hc-lab.sh}
export FM_HC_LAB_DIR="$TMP_ROOT/lab" FM_HC_LAB_SOCK_DIR="$TMP_ROOT/sockets"
export XDG_STATE_HOME="$TMP_ROOT/state" XDG_RUNTIME_DIR="$TMP_ROOT/runtime"
mkdir -p "$TMP_ROOT/fakebin" "$XDG_STATE_HOME/herdr-core"
printf 'real state\n' > "$XDG_STATE_HOME/herdr-core/state"
export REAL_FIND REAL_CAT
REAL_FIND=$(command -v find)
REAL_CAT=$(command -v cat)
REAL_SLEEP=$(command -v sleep)
cat > "$TMP_ROOT/fakebin/hc" <<'SH'
#!/usr/bin/env bash
printf '{"pid":123}\n'
SH
cat > "$TMP_ROOT/fakebin/find" <<'SH'
#!/usr/bin/env bash
[ "${FAIL_READ:-}" != find ] || exit 1
if [ "${FAIL_READ:-}" = metadata ]; then
  # Simulate a file disappearing between inventory and metadata collection.
  printf '%s/missing-file\n' "$1"
  exit 0
fi
exec "$REAL_FIND" "$@"
SH
cat > "$TMP_ROOT/fakebin/cat" <<'SH'
#!/usr/bin/env bash
case "${FAIL_READ:-}:$*" in
  roots:*/fleet-roots.txt|baseline:*/fleet-state.txt) exit 1 ;;
esac
exec "$REAL_CAT" "$@"
SH
# No real Core processes exist in these tests.
cat > "$TMP_ROOT/fakebin/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  '-o pgid= -p '*) [ "${FAIL_READ:-}" != pgid ] || exit 1 ;;
  '-o ppid= -p '*) [ "${FAIL_READ:-}" != ppid ] || exit 1 ;;
  ewwax*)
    n=$(cat "$FM_TEST_PS_COUNTER" 2>/dev/null || echo 0)
    n=$((n + 1))
    printf '%s\n' "$n" > "$FM_TEST_PS_COUNTER"
    [ "${FAIL_READ:-}" != "scan-$n" ] || exit 1
    if [ "$n" = 1 ] && [ -n "${FM_TEST_PS_CHILD:-}" ]; then
      printf '%s 1 999999 hold HC_SESSION=%s\n' "$FM_TEST_PS_CHILD" "$FM_TEST_PS_SESSION"
    fi
    ;;
esac
exit 0
SH
export FM_TEST_PS_COUNTER="$TMP_ROOT/ps-count"

printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_ROOT/fakebin/sleep"
chmod +x "$TMP_ROOT/fakebin/"*
export FM_HC_BIN="$TMP_ROOT/fakebin/hc" PATH="$TMP_ROOT/fakebin:$PATH"

refuse() {
  local diagnostic=$1
  shift
  if "$@" > "$TMP_ROOT/out" 2> "$TMP_ROOT/err"; then
    fail "unexpected success: $*"
  fi
  grep -q "$diagnostic" "$TMP_ROOT/err" || fail "missing diagnostic: $diagnostic"
}

for root in "$FM_HC_LAB_DIR" "$FM_HC_LAB_SOCK_DIR"; do
  mkdir -m 777 "$root"
  chmod 777 "$root"
  for command in provision run stop teardown; do
    refuse 'unsafe root' bash "$LAB" "$command" fm-hclab-unsafe ls
  done
  [ ! -e "$FM_HC_LAB_DIR/fm-hclab-unsafe" ] || fail 'unsafe root accepted'
  rm -rf "$root"
  mkdir -m 700 "$TMP_ROOT/redirect"
  ln -s "$TMP_ROOT/redirect" "$root"
  refuse 'unsafe root' bash "$LAB" provision fm-hclab-redirected
  [ ! -e "$TMP_ROOT/redirect/fm-hclab-redirected" ] || fail 'symlink root accepted'
  rm "$root"
  rmdir "$TMP_ROOT/redirect"
done

bash "$LAB" provision fm-hclab-good
# The filesystem's permission bits are the owned output contract here.
python3 - "$FM_HC_LAB_DIR" "$FM_HC_LAB_SOCK_DIR" <<'PY'
import os, stat, sys
for path in sys.argv[1:]:
    assert stat.S_IMODE(os.stat(path).st_mode) == 0o700, path
PY
printf 'do not overwrite\n' > "$FM_HC_LAB_DIR/fm-hclab-good/sentinel"
refuse 'refusing to adopt or overwrite' bash "$LAB" provision fm-hclab-good
[ "$(cat "$FM_HC_LAB_DIR/fm-hclab-good/sentinel")" = 'do not overwrite' ] || fail 'existing session overwritten'

for failure in find metadata roots baseline; do
  refuse 'refusing unverified teardown' env FAIL_READ=$failure bash "$LAB" teardown fm-hclab-good
  [ -d "$FM_HC_LAB_DIR/fm-hclab-good" ] || fail 'failed verification removed evidence'
done
refuse 'could not record the fleet-state tripwire' env FAIL_READ=find bash "$LAB" provision fm-hclab-incomplete
[ ! -e "$FM_HC_LAB_DIR/fm-hclab-incomplete" ] || fail 'incomplete provision retained'
for failure in pgid ppid scan-1 scan-2 scan-3; do
  printf '0\n' > "$FM_TEST_PS_COUNTER"
  touch "$FM_HC_LAB_SOCK_DIR/fm-hclab-good.sock" "$FM_HC_LAB_SOCK_DIR/fm-hclab-good.holder.test.sock"
  refuse 'could not enumerate session processes' env FAIL_READ=$failure bash "$LAB" teardown fm-hclab-good
  assert_present "$FM_HC_LAB_DIR/fm-hclab-good/sentinel" "$failure retained lab state"
  assert_present "$FM_HC_LAB_SOCK_DIR/fm-hclab-good.sock" "$failure retained lab socket"
  assert_present "$FM_HC_LAB_SOCK_DIR/fm-hclab-good.holder.test.sock" "$failure retained holder socket"
done
printf '0\n' > "$FM_TEST_PS_COUNTER"
"$REAL_SLEEP" 300 &
child=$!
env FM_TEST_PS_CHILD="$child" FM_TEST_PS_SESSION=fm-hclab-good bash "$LAB" teardown fm-hclab-good
if wait "$child"; then fail 'lab cleanup did not signal its owned session child'; fi
[ ! -e "$FM_HC_LAB_DIR/fm-hclab-good" ] || fail 'successful teardown retained session'
printf 'ok - private roots, exclusive sessions, and fail-closed tripwire\n'

CI_CLEANUP="$ROOT/bin/fm-hc-ci-cleanup.sh"
printf 'fm-hclab-preexisting\n' > "$TMP_ROOT/snapshot"
mkdir -p "$FM_HC_LAB_DIR/fm-hclab-preexisting" "$FM_HC_LAB_DIR/fm-hclab-ci"
printf 'keep\n' > "$FM_HC_LAB_DIR/fm-hclab-ci/sentinel"
for failure in pgid ppid scan-1 scan-2 scan-3; do
  printf '0\n' > "$FM_TEST_PS_COUNTER"
  touch "$FM_HC_LAB_SOCK_DIR/fm-hclab-ci.sock" "$FM_HC_LAB_SOCK_DIR/fm-hclab-ci.holder.test.sock"
  refuse 'could not enumerate session processes' env FAIL_READ=$failure bash "$CI_CLEANUP" teardown "$TMP_ROOT/snapshot"
  assert_present "$FM_HC_LAB_DIR/fm-hclab-ci/sentinel" "$failure retained CI state"
  assert_present "$FM_HC_LAB_SOCK_DIR/fm-hclab-ci.sock" "$failure retained CI socket"
  assert_present "$FM_HC_LAB_SOCK_DIR/fm-hclab-ci.holder.test.sock" "$failure retained CI holder socket"
done
printf '0\n' > "$FM_TEST_PS_COUNTER"
"$REAL_SLEEP" 300 &
child=$!
env FM_TEST_PS_CHILD="$child" FM_TEST_PS_SESSION=fm-hclab-ci bash "$CI_CLEANUP" teardown "$TMP_ROOT/snapshot"
if wait "$child"; then fail 'CI cleanup did not signal its owned session child'; fi
assert_absent "$FM_HC_LAB_DIR/fm-hclab-ci" "verified empty CI inventory permits state cleanup"
assert_absent "$FM_HC_LAB_SOCK_DIR/fm-hclab-ci.sock" "verified empty CI inventory permits socket cleanup"
assert_present "$FM_HC_LAB_DIR/fm-hclab-preexisting" "CI cleanup preserves preexisting sessions"
printf 'ok - lab and CI cleanup preserve state and sockets on process inventory failure\n'
