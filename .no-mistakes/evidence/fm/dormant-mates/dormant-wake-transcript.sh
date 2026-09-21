#!/usr/bin/env bash
# Manual evidence: drive fm-control.sh dormant/wake, fm_supervision_status,
# and fm-turnend-guard.sh against the hermetic tmux stub the tests use.
set -u
export GIT_AUTHOR_NAME=ev GIT_AUTHOR_EMAIL=ev@example.com GIT_COMMITTER_NAME=ev GIT_COMMITTER_EMAIL=ev@example.com
WT=/Users/patrick/.no-mistakes/worktrees/72da313f481c/01M3136ACNM8AQE2BYZSCWSJKR
cd "$WT" || exit 1
. tests/lib.sh
TMP_ROOT=$(fm_test_tmproot ev-dormant); mkdir -p "$TMP_ROOT"; TMP_ROOT=$(cd "$TMP_ROOT" && pwd)
trap 'rm -rf "$TMP_ROOT"' EXIT
# reuse the exact fixture helpers from tests/fm-control.test.sh
eval "$(sed -n '/^make_tmux_stub()/,/^# --- 1\. adapter contract/p' tests/fm-control.test.sh | sed '$d')"
CONTROL="$ROOT/bin/fm-control.sh"
show() { printf '\n$ %s\n' "$*"; }
run() { local dir=$1; shift; show "fm-control.sh $*"; run_control "$dir" "$@"; echo "[exit=$?]"; }
run_stub_spawn() { # wake needs fm-spawn; stub it so no real agent starts
  local dir=$1 testroot="$1/control-root"; shift
  mkdir -p "$testroot"
  if [ ! -d "$testroot/bin" ]; then
    cp -R "$ROOT/bin" "$testroot/bin"
    cat > "$testroot/bin/fm-spawn.sh" <<'SH'
#!/usr/bin/env bash
printf 'fm-spawn.sh %s\n' "$*" >> "$FM_FAKE_DIR/spawn-log"
printf 'claude' > "$FM_FAKE_DIR/command"
exit 0
SH
    chmod +x "$testroot/bin/fm-spawn.sh"
  fi
  show "fm-control.sh $*"
  env PATH="$dir/fakebin:$PATH" FM_HOME="$dir/home" FM_FAKE_DIR="$dir/fake" \
    FM_CONTROL_POLL=0.01 FM_CONTROL_LAUNCH_WAIT=0.05 "$testroot/bin/fm-control.sh" "$@" 2>&1
  echo "[exit=$?]"
}

echo "=== 1. dormant: stop an idle local secondmate and record dormancy ==="
dir=$(new_case ev)
add_task "$dir" domain claude secondmate
mkdir -p "$dir/wt-domain/state"; printf 'domain\n' > "$dir/wt-domain/.fm-secondmate-home"
alive_as "$dir" claude
run "$dir" domain dormant
show "cat state/domain.dormant"; sed 's/^set_at=.*/set_at=<utc timestamp>/' "$dir/home/state/domain.dormant"
show "bytes typed into the agent pane"; literals "$dir"

echo; echo "=== 2. dormant again: idempotent, no extra keystrokes ==="
run "$dir" domain dormant
show "bytes typed into the agent pane (unchanged)"; literals "$dir"

echo; echo "=== 3. supervision: a dormant-only home does not need a watcher ==="
show "fm_supervision_status \$FM_HOME/state"
( . "$ROOT/bin/fm-supervision-lib.sh"; fm_supervision_status "$dir/home/state" 300
  echo "FM_SUP_IN_FLIGHT=$FM_SUP_IN_FLIGHT FM_SUP_NEEDED=$FM_SUP_NEEDED" )
show "session-start style digest line for the dormant mate"
( STATE="$dir/home/state"; id=domain; meta="$STATE/$id.meta"
  if grep -q '^kind=secondmate$' "$meta" && [ -f "$STATE/$id.dormant" ]; then
    printf 'endpoint: dormant (expected stopped state; marker=%s)\n' "$STATE/$id.dormant"; fi )

echo; echo "=== 4. turn-end guard: dormant-only parent home ends silently; real work blocks in 2 lines ==="
eval "$(sed -n '/^install_guard_scripts()/,/^}/p' tests/fm-turnend-guard.test.sh)"
eval "$(sed -n '/^make_primary_dir()/,/^}/p' tests/fm-turnend-guard.test.sh)"
g=$(make_primary_dir "$TMP_ROOT/guard")
printf 'kind=secondmate\n' > "$g/state/domain.meta"; printf 'v1\nid=domain\n' > "$g/state/domain.dormant"
show "fm-turnend-guard.sh  (state: domain.meta + domain.dormant only)"
out=$(printf '{"stop_hook_active":false}' | CLAUDECODE=1 FM_HOME="$g" bash "$g/bin/fm-turnend-guard.sh" 2>&1); rc=$?
printf '%s' "$out"; echo "[exit=$rc] stderr lines=$(printf '%s' "$out" | grep -c .)"
: > "$g/state/task1.meta"
show "fm-turnend-guard.sh  (state: + task1.meta in flight, no watcher)"
out=$(printf '{"stop_hook_active":false}' | CLAUDECODE=1 FM_HOME="$g" bash "$g/bin/fm-turnend-guard.sh" 2>&1); rc=$?
printf '%s\n' "$out"; echo "[exit=$rc] stderr lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')"

echo; echo "=== 5. wake: normal fm-spawn recovery path, proven alive, marker cleared ==="
run_stub_spawn "$dir" domain wake
show "spawn calls made"; cat "$dir/fake/spawn-log"
show "ls state/domain.dormant"; ls "$dir/home/state/domain.dormant" 2>&1

echo; echo "=== 6. wake when already awake and not dormant ==="
run_stub_spawn "$dir" domain wake

echo; echo "=== 7. refusals: in-flight child work, remote secondmate, non-secondmate ==="
d2=$(new_case ev2); add_task "$d2" domain claude secondmate
mkdir -p "$d2/wt-domain/state"; : > "$d2/wt-domain/state/child.meta"; alive_as "$d2" claude
run "$d2" domain dormant
show "state/domain.dormant exists?"; ls "$d2/home/state/domain.dormant" 2>&1
d3=$(new_case ev3); add_task "$d3" rmate claude secondmate; echo 'remote_host=box.example' >> "$d3/home/state/rmate.meta"; alive_as "$d3" claude
run "$d3" rmate dormant
run "$d3" rmate wake
d4=$(new_case ev4); add_task "$d4" ship1 claude ship; alive_as "$d4" claude
run "$d4" ship1 dormant
