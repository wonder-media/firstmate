#!/usr/bin/env bash
# Operator-view demo: the Codex primary's supervision checkpoint cadence.
set -u
ROOT=${FM_DEMO_ROOT:?}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-codex-demo.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

# A stand-in for `timeout` that records the bound it was handed and returns the
# quiet-checkpoint code at once, so the shipped default is observable without
# waiting five real minutes. The real watcher is never launched.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/timeout" <<'SH'
#!/usr/bin/env bash
printf 'timeout invoked with bound: %ss\n' "$1" >&2
exit 124
SH
cat > "$TMP/bin/timeout-signal" <<'SH'
#!/usr/bin/env bash
printf 'signal: mate-1 needs-decision\n'
exit 0
SH
chmod +x "$TMP/bin/timeout" "$TMP/bin/timeout-signal"

echo "=== 1. What a Codex primary is told to run ============================="
"$ROOT/bin/fm-supervision-instructions.sh" --harness codex | sed -n '10,40p'
echo

echo "=== 2. The shipped default bound, observed at the CLI =================="
echo '$ bin/fm-watch-checkpoint.sh          # no --seconds, no override'
env PATH="$TMP/bin:$PATH" "$ROOT/bin/fm-watch-checkpoint.sh"; echo "  exit: $?"
echo
echo '$ FM_CODEX_WATCH_CHECKPOINT=180 bin/fm-watch-checkpoint.sh   # override still honoured'
env PATH="$TMP/bin:$PATH" FM_CODEX_WATCH_CHECKPOINT=180 "$ROOT/bin/fm-watch-checkpoint.sh"; echo "  exit: $?"
echo
echo '$ bin/fm-watch-checkpoint.sh --seconds 600                   # explicit bound wins'
env PATH="$TMP/bin:$PATH" "$ROOT/bin/fm-watch-checkpoint.sh" --seconds 600; echo "  exit: $?"
echo

echo "=== 3. An actionable wake still closes the checkpoint immediately ======"
cp "$TMP/bin/timeout-signal" "$TMP/bin/timeout"
echo '$ bin/fm-watch-checkpoint.sh          # watcher reports a signal'
env PATH="$TMP/bin:$PATH" "$ROOT/bin/fm-watch-checkpoint.sh"; echo "  exit: $? (0 = wake passed through, not the 124 quiet return)"
echo

echo "=== 4. Quiet model returns per hour ===================================="
printf '  %-10s %-26s %s\n' seconds "quiet returns/hour" "worst-case user-message delay"
for s in 180 300 600; do
  printf '  %-10s %-26s %ss\n' "$s" "$((3600 / s))" "$s"
done
echo "  shipped default: 300s -> 12/hour (was 180s -> 20/hour)"
echo
echo "=== end ================================================================"
