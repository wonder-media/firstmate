#!/usr/bin/env bash
# Evidence driver: prints the REAL bin/fm-crew-state.sh line an operator sees for
# each secondmate current-state case named in the intent. Reuses the shipped
# test-suite fixture helpers (lines 1..218 of tests/fm-crew-state.test.sh) so the
# fakes are the same ones CI uses; no assertions here - just the reader output.
set -u
REPO=${1:?repo root}
HELPERS=$(mktemp -t fm-crew-helpers)
sed -n '1,218p' "$REPO/tests/fm-crew-state.test.sh" \
  | sed "s|\$(dirname \"\${BASH_SOURCE\[0\]}\")/lib.sh|$REPO/tests/lib.sh|" > "$HELPERS"
# shellcheck source=/dev/null
. "$HELPERS"

show() { printf '%-48s %s\n' "$1" "$(run_crew_state "$2" mate)"; }

printf '# `bin/fm-crew-state.sh mate` - secondmate current state, one line per case\n\n'

# --- healthy idle: only with live endpoint + current generation + semantic record
while IFS='^' read -r harness source backend; do
  reset_fakes
  d=$(make_secondmate_lifecycle_case "ev-idle-$harness-$backend" "$harness" "$source" idle "$backend")
  [ "$backend" != herdr ] || FM_FAKE_HERDR_AGENT_STATUS=idle
  printf 'working: old coordination event\nnote: later informational note\n' > "$d/state/mate.status"
  show "healthy idle ($harness on $backend)" "$d"
done <<'ROWS'
claude^claude-hook^tmux
claude^claude-hook^herdr
opencode^opencode-plugin^tmux
pi^pi-ext^tmux
ROWS

# --- busy
reset_fakes
d=$(make_secondmate_lifecycle_case ev-busy claude claude-hook busy tmux)
printf 'blocked [key=old]: prior blocker\nnote: status chatter\n' > "$d/state/mate.status"
show "busy coordinator" "$d"

# --- open decision / blocker stay visible under idle
reset_fakes
d=$(make_secondmate_lifecycle_case ev-decision claude claude-hook idle tmux)
printf 'needs-decision [key=scope]: choose scope\nnote: later informational note\n' > "$d/state/mate.status"
show "open decision + later note" "$d"

reset_fakes
d=$(make_secondmate_lifecycle_case ev-blocked claude claude-hook idle tmux)
printf 'blocked [key=infra]: waiting on infra\nnote: later informational note\n' > "$d/state/mate.status"
show "open blocker + later note" "$d"

reset_fakes
d=$(make_secondmate_lifecycle_case ev-resolved claude claude-hook idle tmux)
printf 'needs-decision [key=race]: pick order\nresolved [key=race]: selected order\n' > "$d/state/mate.status"
show "decision resolved -> back to healthy idle" "$d"

# --- a trailing declaration always wins
reset_fakes
d=$(make_secondmate_lifecycle_case ev-paused claude claude-hook idle tmux)
printf 'blocked [key=infra]: waiting on infra\npaused: awaiting the upstream release\n' > "$d/state/mate.status"
show "declared paused outranks older blocker" "$d"

reset_fakes
d=$(make_secondmate_lifecycle_case ev-failed claude claude-hook idle tmux)
printf 'working: coordinating\nfailed: cannot reach the upstream repo\n' > "$d/state/mate.status"
show "declared failed" "$d"

reset_fakes
d=$(new_case ev-declared-unsupported); mkdir -p "$d/wt"; make_fakebin "$d" >/dev/null
fm_write_meta "$d/state/mate.meta" "window=fm:fm-mate" "endpoint_task_id=mate" \
  "worktree=$d/wt" "project=$d/wt" "kind=secondmate" "harness=cursor" "home=$d/wt"
printf 'working: coordinating\npaused: awaiting the upstream release\n' > "$d/state/mate.status"
show "declared paused on unsupported harness" "$d"

reset_fakes
d=$(make_secondmate_lifecycle_case ev-superseded claude claude-hook idle tmux)
printf 'paused: awaiting the upstream release\nnote: later informational note\n' > "$d/state/mate.status"
show "pause superseded by later note -> idle" "$d"

reset_fakes
d=$(make_secondmate_lifecycle_case ev-busy-over-decl claude claude-hook busy tmux)
printf 'failed: cannot reach the upstream repo\n' > "$d/state/mate.status"
show "live busy outranks a declaration" "$d"

# --- unknown, with the reason preserved
reset_fakes
d=$(make_secondmate_lifecycle_case ev-stale claude claude-hook idle tmux)
sed -i.bak 's/^busy_gen=.*/busy_gen=retired-generation/' "$d/state/mate.meta"; rm -f "$d/state/mate.meta.bak"
show "stale lifecycle generation" "$d"

reset_fakes
d=$(make_secondmate_lifecycle_case ev-dead claude claude-hook idle herdr)
FM_FAKE_HERDR_NO_AGENT=1
show "dead endpoint" "$d"

reset_fakes
d=$(new_case ev-unsupported); mkdir -p "$d/wt"; make_fakebin "$d" >/dev/null
fm_write_meta "$d/state/mate.meta" "window=fm:fm-mate" "endpoint_task_id=mate" \
  "worktree=$d/wt" "project=$d/wt" "kind=secondmate" "harness=cursor" "home=$d/wt"
show "harness with no lifecycle adapter" "$d"

reset_fakes
d=$(make_secondmate_lifecycle_case ev-unverified claude claude-hook idle tmux)
printf 'backend=zellij\n' >> "$d/state/mate.meta"
show "backend not proven for recovery" "$d"

reset_fakes
d=$(new_case ev-remote); mkdir -p "$d/wt"; make_fakebin "$d" >/dev/null
fm_write_meta "$d/state/mate.meta" "window=remote:mate" "endpoint_task_id=mate" \
  "worktree=$d/wt" "project=/srv/firstmate" "kind=secondmate" \
  "harness=claude" "remote_host=mate.invalid" "home=/srv/firstmate"
show "remote source unreachable" "$d"

rm -f "$HELPERS"
