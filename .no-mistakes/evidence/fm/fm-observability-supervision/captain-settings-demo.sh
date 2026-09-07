#!/usr/bin/env bash
# Operator-view demo: a captain's own ~/.claude/settings.local.json in a
# long-lived secondmate home, before firstmate arms its lifecycle hooks, while
# armed, and after firstmate retires them on teardown.
set -u
ROOT=${FM_DEMO_ROOT:?}
. "$ROOT/bin/fm-control-lib.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-caps-demo.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

HOOKS='{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"touch /s/mate.turn-ended; /fm/bin/fm-busy-event.sh apply /s mate idle --gen G1"}]}]}}'

roundtrip() {  # <label> <captain-json>
  local label=$1 home="$TMP/$2" f
  mkdir -p "$home/.claude"; f="$home/.claude/settings.local.json"
  printf '%s\n' "$3" | jq . > "$f"
  echo "--- $label"
  echo "  captain's file BEFORE firstmate arms:"; jq -c . "$f" | sed 's/^/    /'
  fm_control_claude_hooks_write "$f" "$HOOKS" shared || echo "    (arm declined)"
  echo "  WHILE a firstmate secondmate is armed:"; jq -c . "$f" | sed 's/^/    /'
  fm_control_secondmate_lifecycle_retire "$home" /s mate; echo "  retire exit: $?"
  echo "  captain's file AFTER teardown retires firstmate:"; jq -c . "$f" | sed 's/^/    /'
  echo
}

echo "=== Captain-owned secondmate settings survive arm + retire ============="
echo

roundtrip "A. captain permissions + their own PreToolUse hook" a \
  '{"permissions":{"allow":["Bash(git status)"]},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"captain-guard.sh"}]}]},"statusLine":{"type":"command","command":"my-status.sh"}}'

roundtrip "B. captain command sitting INSIDE firstmate's Stop entry" b \
  '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"captain-own-stop.sh"}]}]}}'

roundtrip "C. captain entry that declares an EMPTY hooks array" c \
  '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[]}]}}'

roundtrip "D. captain event that is an EMPTY array (untouched by firstmate)" d \
  '{"hooks":{"PreToolUse":[],"SessionStart":[{"hooks":[{"type":"command","command":"captain-start.sh"}]}]}}'

# Note: when the captain's EMPTY event is the very event firstmate merges into
# (Stop), the merge fills it and the retire empties it again, so the bare `[]`
# declaration is not restored. Nothing executable is lost - an empty event list
# runs no hook - and this is the accepted contract: only structures made empty
# by removing firstmate's own commands are dropped.
roundtrip "E. captain EMPTY Stop event, the one firstmate merges into" e \
  '{"hooks":{"Stop":[],"SessionStart":[{"hooks":[{"type":"command","command":"captain-start.sh"}]}]}}'

echo "=== jq stays optional on a tmux-only install ==========================="
echo
NOJQ="$TMP/nojq"; mkdir -p "$NOJQ"
for t in bash printf mkdir rm mv chmod stat uname dirname cat sed; do
  r=$(command -v "$t" 2>/dev/null) && ln -sf "$r" "$NOJQ/$t"
done
CREWWT="$TMP/crew"; mkdir -p "$CREWWT/.claude"
env -i PATH="$NOJQ" HOME="$TMP" bash -c '
  . "'"$ROOT"'/bin/fm-control-lib.sh"
  f="'"$CREWWT"'/.claude/settings.local.json"
  command -v jq >/dev/null 2>&1 && { echo "jq unexpectedly present"; exit 1; }
  echo "  jq on PATH: no"
  fm_control_claude_hooks_write "$f" '"'$HOOKS'"' owned && echo "  ordinary crew worktree arm: ok (file written)"
  fm_control_claude_hooks_clear "$f" owned && echo "  ordinary crew worktree relaunch clear: ok"
  [ -e "$f" ] && echo "  file still present (BAD)" || echo "  file removed: ok"
'
echo
echo "=== end ================================================================"
