#!/usr/bin/env bash
# Captain-visible demo: the primary's config/council.json reaches a live
# secondmate home through the real bin/fm-config-push.sh command.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/.helpers.sh"

REPO="$ROOT"
w=$(new_world council-evidence)
c1=$(git -C "$w/main" rev-parse HEAD)
add_sm_worktree "$w" sm "$c1"
sm_real=$(cd "$w/sm" && pwd -P)
printf -- '- sm - council evidence home (home: %s; scope: config; projects: alpha; added 2026-09-22)\n' "$sm_real" > "$w/home/data/secondmates.md"
record_live_watcher_fixture "$w/home"

say() { printf '\n$ %s\n' "$*"; }

printf '=== Captain edits the fleet council roster on the primary ===\n'
cp "$REPO/bin/council/council.example.json" "$w/home/config/council.json"
say "cat config/council.json   # primary"
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("default_roster =",d["default_roster"]);print("minimum_counted_reports =",d["caps"]["minimum_counted_reports"])' "$w/home/config/council.json"

say "ls secondmate-home/config/   # before the push"
ls "$w/sm/config" 2>/dev/null || printf '(no config/ in the secondmate home yet)\n'

say "fm-config-push.sh"
run_config_push "$w" "$w/tmux.log" 2>&1 | sed 's|'"$w"'|<world>|g'

say "cat secondmate-home/config/council.json   # after the push"
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("default_roster =",d["default_roster"])' "$w/sm/config/council.json"
printf 'security seat brief file: bin/council/roles/%s.md exists: ' security
[ -f "$REPO/bin/council/roles/security.md" ] && printf 'yes\n' || printf 'no\n'

printf '\n=== Captain narrows the roster; the home follows ===\n'
python3 - "$w/home/config/council.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["default_roster"] = ["architect", "empiricist", "security"]
json.dump(d, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
say "fm-config-push.sh"
run_config_push "$w" "$w/tmux.log" 2>&1 | sed 's|'"$w"'|<world>|g'
say "cat secondmate-home/config/council.json"
python3 -c 'import json,sys;print("default_roster =",json.load(open(sys.argv[1]))["default_roster"])' "$w/sm/config/council.json"

printf '\n=== Captain removes the roster; the home copy goes too ===\n'
rm -f "$w/home/config/council.json"
say "fm-config-push.sh"
run_config_push "$w" "$w/tmux.log" 2>&1 | sed 's|'"$w"'|<world>|g'
say "ls secondmate-home/config/council.json"
ls "$w/sm/config/council.json" 2>&1 | sed 's|'"$w"'|<world>|g'
