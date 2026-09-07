#!/usr/bin/env bash
# Evidence driver: a captain-owned secondmate home whose .claude/settings.local.json
# already carries the captain's permissions, env, statusLine and hooks - including a
# captain command sharing Firstmate's own Stop entry, an entry that declares an empty
# hooks array, and an already-empty event. Runs the SHIPPED helpers for spawn (merge),
# respawn (idempotent), teardown (retire), and prints the real file at each step.
# Case B repeats it on a home the captain hand-edited into a shape the merge cannot
# walk, to show the warn-and-continue path.
set -u
REPO=${1:?repo root}
. "$REPO/bin/fm-control-lib.sh"

mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }

run_case() {  # <label> <settings-json-heredoc-file>
  local label=$1 seed=$2 home state set_ before
  home=$(mktemp -d -t fm-captain-home); state=$(mktemp -d -t fm-captain-state)
  set_=$home/.claude/settings.local.json
  mkdir -p "$home/.claude"; cp "$seed" "$set_"; chmod 600 "$set_"

  local hooks
  hooks='{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"'"$REPO"'/bin/fm-busy-event.sh apply '"$state"' mate busy --gen G1 --source claude-hook --event user-prompt-submit 2>/dev/null || true"}]}],"Stop":[{"hooks":[{"type":"command","command":"touch '"$state"'/mate.turn-ended; '"$REPO"'/bin/fm-busy-event.sh apply '"$state"' mate idle --gen G1 --source claude-hook --event stop 2>/dev/null || true"}]}],"StopFailure":[{"hooks":[{"type":"command","command":"'"$REPO"'/bin/fm-busy-event.sh apply '"$state"' mate idle --gen G1 --source claude-hook --event stop-failure 2>/dev/null || true"}]}],"SessionEnd":[{"hooks":[{"type":"command","command":"'"$REPO"'/bin/fm-busy-event.sh apply '"$state"' mate idle --gen G1 --source claude-hook --event session-end 2>/dev/null || true"}]}]}}'

  # Fold firstmate's long absolute commands to a short tag so the file reads.
  show() { sed "s|[^\"]*fm-busy-event.sh[^\"]*|<FIRSTMATE LIFECYCLE HOOK>|g" "$set_"; }

  echo "################ $label ################"
  echo "--- 1. captain's home before firstmate touches it (mode $(mode "$set_")) ---"
  show

  echo
  echo "--- 2. spawn ---"
  if fm_control_claude_shared_settings_mergeable "$set_"; then
    echo "gate: mergeable -> arm the semantic lifecycle wiring"
    fm_control_claude_hooks_write "$set_" "$hooks" shared \
      && echo "merge: ok (mode still $(mode "$set_"))" || echo "merge: FAILED"
  else
    echo "gate: NOT mergeable -> warn, spawn continues with semantic wiring disarmed"
    echo "      (captain's file left byte-for-byte untouched, launch NOT refused)"
  fi
  show

  echo
  echo "--- 3. respawn into the same home ---"
  before=$(cat "$set_")
  if fm_control_claude_shared_settings_mergeable "$set_"; then
    fm_control_claude_hooks_write "$set_" "$hooks" shared >/dev/null && echo "merge: ok"
  else
    echo "gate: NOT mergeable -> still disarmed, no write"
  fi
  [ "$before" = "$(cat "$set_")" ] \
    && echo "file byte-identical to step 2: yes (idempotent)" \
    || echo "file changed: NOT idempotent"

  echo
  echo "--- 4. teardown: retire firstmate hooks ---"
  local rc=0
  fm_control_secondmate_lifecycle_retire "$home" "$state" mate || rc=$?
  echo "retire rc=$rc  (0 = nothing firstmate-owned left)"
  show
  echo "mode after retire: $(mode "$set_")"

  echo
  echo "--- 5. captain content after the full spawn/respawn/teardown cycle ---"
  jq -c '{permissions,env,statusLine,
          captain_hook_commands: [.. | objects | select(has("command")) | .command
                                  | select(test("fm-busy-event")|not)],
          empty_entry_kept: (((.hooks.PreToolUse // [])[]? | select(type=="object" and .matcher=="Write")) != null),
          empty_event_kept: (.hooks | has("SessionStart")),
          hand_edited_event: (.hooks.Notification // "n/a")}' "$set_"
  echo
  rm -rf "$home" "$state"
}

seedA=$(mktemp -t fm-seedA); seedB=$(mktemp -t fm-seedB)
cat > "$seedA" <<'JSON'
{
  "permissions": { "allow": ["Bash(git status:*)"], "deny": ["Bash(rm:*)"] },
  "env": { "CAPTAIN_TOKEN": "keep-me" },
  "statusLine": { "type": "command", "command": "captain-statusline" },
  "hooks": {
    "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "captain-pretooluse" } ] },
                    { "matcher": "Write", "hooks": [] } ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "captain-own-stop" } ] } ],
    "SessionStart": []
  }
}
JSON
sed 's/"SessionStart": \[\]/"SessionStart": [],\n    "Notification": { "captain": "hand-edited, not an array" }/' "$seedA" > "$seedB"

run_case "CASE A - well-formed captain settings" "$seedA"
run_case "CASE B - captain hand-edited an event into a non-array" "$seedB"
rm -f "$seedA" "$seedB"

# CASE C - the regression the last fix commit closes: firstmate armed while the
# file was well-formed, THEN the captain hand-edited an event into a non-array.
# Teardown must still prune firstmate's own hook instead of claiming a clean
# retirement while the hook keeps firing for the next mate leased into the home.
homeC=$(mktemp -d -t fm-captain-homeC); stateC=$(mktemp -d -t fm-captain-stateC)
setC=$homeC/.claude/settings.local.json; mkdir -p "$homeC/.claude"
cat > "$setC" <<JSON
{"hooks":{
  "Notification":{"matcher":"Bash","hooks":[{"type":"command","command":"captain-hand-edit"}]},
  "Stop":[{"hooks":[{"type":"command","command":"touch $stateC/mate.turn-ended; $REPO/bin/fm-busy-event.sh apply $stateC mate idle --gen G1 --source claude-hook --event stop"}]}]}}
JSON
echo "################ CASE C - armed home, then a captain hand-edit ################"
echo "--- before teardown ---"
sed "s|[^\"]*fm-busy-event.sh[^\"]*|<FIRSTMATE LIFECYCLE HOOK>|g" "$setC"
rcC=0; fm_control_secondmate_lifecycle_retire "$homeC" "$stateC" mate || rcC=$?
echo "--- after teardown (retire rc=$rcC) ---"
sed "s|[^\"]*fm-busy-event.sh[^\"]*|<FIRSTMATE LIFECYCLE HOOK>|g" "$setC"
echo "firstmate hook commands still installed: $(jq '[.. | objects | select(has("command")) | .command | select(test("fm-busy-event"))] | length' "$setC")"
rm -rf "$homeC" "$stateC"
