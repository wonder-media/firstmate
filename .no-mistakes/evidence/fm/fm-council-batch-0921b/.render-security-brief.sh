#!/usr/bin/env bash
# Render the prompt the council SECURITY seat actually receives:
# bin/fm-brief.sh --scout scaffold + rubric common clauses + round-1 variant
# + exactly one role template (bin/council/roles/security.md), per
# .agents/skills/council/SKILL.md "Briefs and dispatch".
set -eu
REPO=$1
OUT=$2
HOME_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fm-council-brief.XXXXXX")
mkdir -p "$HOME_DIR/data" "$HOME_DIR/state"
FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$REPO" bash "$REPO/bin/fm-brief.sh" \
  council-r1-security firstmate --scout >/dev/null

TASK="$HOME_DIR/task.md"
{
  printf 'Council round 1, seat: security.\n\n'
  # Common clauses + round 1 variant from bin/council/rubric.md, placeholders filled.
  awk '/^## Common clauses/,/^## Round 2\+ variant/' "$REPO/bin/council/rubric.md" \
    | sed '/^## Round 2+ variant/,$d'
  printf '\n'
  # Exactly one role template for this seat.
  cat "$REPO/bin/council/roles/security.md"
} > "$TASK"

python3 - "$HOME_DIR/data/council-r1-security/brief.md" "$TASK" "$OUT" "$HOME_DIR" "$REPO" <<'PY'
import sys
from pathlib import Path

brief, task, out, home, repo = sys.argv[1:]
text = Path(brief).read_text(encoding="utf-8")
body = Path(task).read_text(encoding="utf-8")
body = (body
        .replace("{seat}", "security")
        .replace("{round}", "1")
        .replace("{plan-path}", "data/plans/fleet-tokens-v3.md (frozen)")
        .replace("{paste-non-negotiables}", "no new external service; ship behind the existing flag")
        .replace("{allowed-evidence-paths-or-excerpts-without-peer-findings}",
                 "bin/, docs/, tests/ in your own scout copy"))
text = text.replace("{TASK}", body.rstrip() + "\n")
text = text.replace(home, "<secondmate-home>").replace(repo, "<firstmate-repo>")
Path(out).write_text(text, encoding="utf-8")
PY
rm -rf "$HOME_DIR"
printf 'rendered %s\n' "$OUT"
