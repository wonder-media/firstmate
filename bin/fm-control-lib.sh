#!/usr/bin/env bash
# fm-control-lib.sh - the ONE executable owner of firstmate's agent lifecycle
# CONTROL-PLANE mechanics.
#
# Data plane vs control plane (captain-approved root architecture, 2026-07-13).
# bin/fm-send.sh is the DATA plane: conversational text for the agent to read,
# always routing-marked for a kind=secondmate target so the reply comes back
# through the status path. That marking is exactly right for a message and
# exactly wrong for a lifecycle command: a marked "/quit" arrives as ordinary
# chat ("[fm-from-firstmate] /quit") that the agent reasons ABOUT instead of
# executing. bin/fm-control.sh is the CONTROL plane: allowlisted lifecycle
# verbs addressed to an exact task id, with the per-harness mechanics owned
# here rather than improvised per harness in agent prose.
#
# This file owns three capability tables plus their pure artifact-path tables
# and nothing else. It has no side effects, runs no backend command, and reads
# no state, so it can be sourced by a test as a pure contract:
#
#   1. Verb allowlist. There is no arbitrary-text and no generic raw-key entry
#      point on the control plane; a caller either names an allowlisted verb or
#      is refused.
#   2. Per-harness control mechanics: which key interrupts a running turn, how
#      many times it must be sent, whether the composer needs clearing after
#      that key, which adapter-owned cancellation acknowledgement is observable,
#      which command exits the agent, and which task kinds the adapter is
#      verified to run. These are the empirically verified facts previously
#      carried only in the harness-adapters skill's per-adapter tables; that
#      skill now points here so one executable owner holds them, and
#      bin/fm-send.sh's --key path reads the same table rather than a second
#      copy of it.
#   3. Per-backend capability: which named keys a runtime backend can deliver,
#      and whether the backend has a recovery-grade agent-state classifier
#      (bin/fm-backend.sh's fm_backend_agent_state) able to PROVE that an agent
#      stopped. A verb whose postcondition cannot be proven on the recorded
#      backend is refused rather than performed blind.
#
# `resume` is deliberately NOT a verb. It is not deterministic across the
# verified adapters: codex and grok resume only from a session id printed at
# exit, opencode resumes the most recent session for the cwd with --continue,
# and claude, pi, pi-signed, and kimi have no verified pane-resume contract at
# all. `relaunch` covers the same need deterministically for every adapter,
# because the brief on disk - not a harness-private session - is the durable
# instruction.

# The complete control-plane verb allowlist, one per line.
fm_control_verbs() {
  cat <<'EOF'
interrupt
exit
relaunch
EOF
}

fm_control_verb_allowed() {  # <verb>
  case "${1-}" in
    interrupt|exit|relaunch) return 0 ;;
  esac
  return 1
}

# The harnesses whose control mechanics are verified. Mirrors AGENTS.md
# section 4's verified-adapter list; an unverified adapter is refused rather
# than guessed at, exactly as a spawn on it would be.
fm_control_harness_supported() {  # <harness>
  case "${1-}" in
    claude|codex|opencode|pi|pi-signed|grok|kimi|cursor|muse) return 0 ;;
  esac
  return 1
}

# The verified adapter a RECORDED harness value belongs to. Every table below
# is keyed by the exact verified adapter name, but a task launched from a raw
# command records the command's basename instead (bin/fm-spawn.sh derives
# harness= that way), which is why the spawn adapters match `claude*`, `muse*`,
# and friends. This is the one place that prefix rule is stated. `pi` and
# `pi-signed` are exact because a `pi*` prefix would swallow the signed adapter,
# and an unrecognized value returns nonzero rather than being guessed into a
# family.
fm_control_harness_family() {  # <recorded-harness>
  case "${1-}" in
    pi) printf 'pi' ;;
    pi-signed) printf 'pi-signed' ;;
    claude*) printf 'claude' ;;
    codex*) printf 'codex' ;;
    opencode*) printf 'opencode' ;;
    grok*) printf 'grok' ;;
    kimi*) printf 'kimi' ;;
    cursor*) printf 'cursor' ;;
    muse*) printf 'muse' ;;
    *) return 1 ;;
  esac
}

# Which task kinds an adapter is verified to run. muse is a crewmate/scout
# adapter only: it has no primary supervision protocol, and bin/fm-spawn.sh
# refuses a --secondmate launch on it. The control plane
# asks this BEFORE it stops anything, so an incompatible relaunch target is
# refused while the current agent is still running rather than after it has
# been stopped.
fm_control_harness_supports_kind() {  # <harness> <kind>
  local harness=${1-} kind=${2-}
  fm_control_harness_supported "$harness" || return 1
  case "$harness" in
    muse) [ "$kind" != secondmate ] || return 1 ;;
  esac
  return 0
}

# The key that cancels a running turn. Escape for every adapter except grok,
# whose Esc only moves focus to the scrollback; grok cancels on Ctrl+C.
fm_control_interrupt_key() {  # <harness>
  case "${1-}" in
    claude|codex|opencode|pi|pi-signed|kimi|cursor|muse) printf 'Escape' ;;
    grok) printf 'C-c' ;;
    *) return 1 ;;
  esac
}

# How many times the interrupt key must be delivered. OpenCode needs a double
# Escape; every other verified adapter interrupts on a single press.
fm_control_interrupt_repeat() {  # <harness>
  case "${1-}" in
    opencode) printf '2' ;;
    claude|codex|pi|pi-signed|grok|kimi|cursor|muse) printf '1' ;;
    *) return 1 ;;
  esac
}

# The key that must follow the interrupt key to leave the composer empty, or
# nothing when the adapter needs none. muse is the one verified adapter that
# RESTORES the cancelled prompt into its composer as real bright text, so an
# interrupt is not complete until Ctrl+U has cleared it; leaving it there would
# make the next submitted line - a steer, or this plane's own exit command -
# concatenate onto it. cursor was checked for exactly that behaviour and does
# NOT repollute: after a single Escape its composer shows only the `Add a
# follow-up` placeholder, so it needs no clear key. Prints the key or nothing;
# a harness with no verified mechanics returns nonzero, matching the tables
# above.
fm_control_interrupt_clear_key() {  # <harness>
  case "${1-}" in
    muse) printf 'C-u' ;;
    claude|codex|opencode|pi|pi-signed|grok|kimi|cursor) ;;
    *) return 1 ;;
  esac
}

fm_control_interrupt_ack_source() {  # <harness>
  case "${1-}" in
    muse) printf 'muse-session-terminal' ;;
    # cursor's transcript DOES type an aborted close, but its write latency
    # after an interrupt was measured as variable - sometimes seconds, sometimes
    # not within 20 - so a cancellation claim built on it would be unreliable.
    # Normal turn completion is prompt, which is what the busy fold depends on.
    claude|codex|opencode|pi|pi-signed|grok|kimi|cursor) printf 'none' ;;
    *) return 1 ;;
  esac
}

# The command that exits the agent from its own composer.
fm_control_exit_command() {  # <harness>
  case "${1-}" in
    claude|opencode|grok|kimi|cursor|muse) printf '/exit' ;;
    codex|pi|pi-signed) printf '/quit' ;;
    *) return 1 ;;
  esac
}

# Which named keys a backend adapter can deliver. Every session provider
# normalizes Enter, Ctrl+C, and the Ctrl+U composer clear; Orca's terminal API
# exposes only an interrupt and an Enter, so it can deliver neither Escape nor
# Ctrl+U (bin/backends/orca.sh's fm_backend_orca_send_key).
fm_control_backend_supports_key() {  # <backend> <key>
  local backend=${1-} key=${2-}
  case "$backend" in
    tmux|herdr|zellij|cmux)
      case "$key" in Escape|Enter|C-c|C-u) return 0 ;; esac
      ;;
    orca)
      case "$key" in Enter|C-c) return 0 ;; esac
      ;;
  esac
  return 1
}

# Whether <backend> has a recovery-grade agent-state classifier. Only tmux and
# herdr implement fm_backend_agent_state; zellij, orca, and cmux report
# `unverified`, so no reading of theirs can prove an agent stopped. The control
# plane refuses a stop-proving verb there instead of reporting an unprovable
# transition as success.
fm_control_backend_state_verified() {  # <backend>
  case "${1-}" in
    tmux|herdr) return 0 ;;
  esac
  return 1
}

# The per-task wiring artifacts a harness leaves behind, so a relaunch that
# changes harness (or re-arms the same one with a fresh busy generation) can
# clear the previous incarnation's wiring instead of leaving a stale hook
# pointing at a retired generation. Prints zero or more absolute paths, one per
# line: worktree-resident hook files and firstmate-owned state tokens only,
# never a harness's own managed config.
fm_control_harness_wiring_paths() {  # <harness> <worktree> <state-dir> <id>
  local harness=${1-} wt=${2-} state=${3-} id=${4-}
  [ -n "$wt" ] && [ -n "$state" ] && [ -n "$id" ] || return 1
  case "$harness" in
    claude) printf '%s\n' "$wt/.claude/settings.local.json" ;;
    opencode) printf '%s\n' "$wt/.opencode/plugins/fm-busy-state.js" ;;
    pi|pi-signed) printf '%s\n' "$state/$id.pi-ext.ts" ;;
    grok)
      printf '%s\n' "$wt/.fm-grok-turnend"
      printf '%s\n' "$state/$id.grok-turnend-token"
      ;;
    kimi)
      printf '%s\n' "$wt/.fm-kimi-turnend"
      printf '%s\n' "$state/$id.kimi-turnend-token"
      ;;
    muse)
      # muse installs no hook: its busy source is its own session event log,
      # bound to the pane by these two firstmate-owned sidecars. A relaunch
      # ONTO muse rewrites them, but a relaunch AWAY from muse must retire them
      # so no retired incarnation's session binding outlives the agent.
      printf '%s\n' "$state/$id.muse-session"
      printf '%s\n' "$state/$id.muse-session-current"
      ;;
    cursor) printf '%s\n' "$state/$id.cursor-session" ;;
  esac
}

# The firstmate-owned global turn-end registry entry a harness mints per task.
# grok and kimi are the two adapters whose turn-end hook is global and gated by
# a private token file; every other adapter's wiring is fully covered by
# fm_control_harness_wiring_paths. Prints the registry path or nothing.
fm_control_harness_turnend_token_path() {  # <harness> <state-dir> <id>
  local harness=${1-} state=${2-} id=${3-}
  [ -n "$state" ] && [ -n "$id" ] || return 1
  case "$harness" in
    grok) printf '%s\n' "$state/$id.grok-turnend-token" ;;
    kimi) printf '%s\n' "$state/$id.kimi-turnend-token" ;;
  esac
}

fm_control_harness_turnend_auth_path() {  # <harness> <token>
  local harness=${1-} token=${2-}
  case "$token" in ''|*[!A-Za-z0-9._-]*) return 0 ;; esac
  case "$harness" in
    grok) printf '%s\n' "${GROK_HOME:-$HOME/.grok}/hooks/fm-turn-end.d/$token" ;;
    kimi) printf '%s\n' "$HOME/.kimi-code/fm-turn-end.d/$token" ;;
    *) return 0 ;;
  esac
}

# --- claude settings.local.json wiring (merge in, prune out) ----------------
#
# Who owns <worktree>/.claude/settings.local.json depends on the worktree. In an
# ephemeral crew worktree firstmate creates and removes the whole file, so both
# helpers below stay a plain write and a plain rm ("owned") and need no jq -
# jq is optional for a tmux-only install (bin/fm-backend.sh's required tools).
# A secondmate's worktree IS a long-lived, captain-owned firstmate home whose
# settings can already carry the captain's own permissions and hooks, so there
# firstmate is a guest ("shared"): the lifecycle hooks are merged into whatever
# is present and retired by removing only the entries firstmate wrote,
# identified by the busy-event command every one of them runs. Only that mode
# needs jq, which stays optional: the whole "can this merge run at all" question
# is answered up front by fm_control_claude_shared_settings_mergeable, so a
# caller decides whether to arm instead of discovering a missing jq or an
# unusable captain file mid-write and refusing the launch. When it cannot run,
# the captain's file is left exactly as it was.
# Only the owned mode ever deletes the file: a guest never removes a path it did
# not create, and never rewrites one holding no firstmate entry at all. What
# counts as a firstmate entry is a question about the parsed hook COMMANDS, never
# about the document's text: the captain's own permissions, env values or status
# line can name the same script without firstmate owning anything in the file.
FM_CONTROL_CLAUDE_HOOK_MARKER='bin/fm-busy-event.sh'

# 0 when stdin is exactly one JSON object. jq exits 0 while printing nothing for
# an input it accepts but yields no value from, and a stream holding two
# concatenated documents merges into two, so neither an unusable captain file
# nor such a merge result may be written back over captain-owned settings.
_fm_control_claude_settings_is_one_object() {  # reads stdin
  jq -e -s 'length == 1 and (.[0] | type) == "object"' >/dev/null 2>&1
}

_fm_control_claude_owned_hook_program='
  [(.hooks // {}) | .[]? | select(type == "array") | .[]?
    | select((.hooks | type) == "array") | .hooks[] | .command // ""]
  | any(contains($marker))
'

# Firstmate owns individual hook COMMANDS, not the matcher entry holding them:
# its Stop entry carries no matcher, so a captain hand-editing that event adds
# their command beside firstmate's rather than in an entry of their own.
# Retirement therefore drops matching commands, and drops the entry and the
# event only when firstmate's own removal is what emptied them: an entry or an
# event that already declared nothing is the captain's and is left as it is.
_fm_control_claude_prune_program='
  def fm_entry:
    if (.hooks | type) != "array" or ((.hooks | length) == 0)
    then .
    else .hooks = (.hooks | map(select((.command // "") | contains($marker) | not)))
      | if (.hooks | length) == 0 then empty else . end
    end;
  .hooks = ((.hooks // {}) | with_entries(
      if (.value | type) != "array" or (.value | length) == 0 then .
      else .value |= map(fm_entry) | select((.value | length) > 0) end))
'

# Pruning and merging are different capabilities and each has its own gate, so
# neither is refused over a requirement it does not have.
#
# Prunable is what RETIREMENT needs: jq is present (optional for a tmux-only
# install, per bin/fm-backend.sh's required tools), the existing file, if any, is
# exactly one JSON object, and the prune program actually accepts it - a `hooks`
# value of an unexpected inner shape parses as one object but makes that program
# error. Proving it with the SAME program is what keeps this the single owner of
# the question, so a document firstmate cannot walk declines up front instead of
# failing mid-write.
#
# Mergeable is what ARMING needs, which is strictly more: the merge appends
# firstmate's own entries onto `.hooks[<event>]`, so every hook event present
# must be an array for that append to run. The prune leaves an event it cannot
# walk into untouched rather than deleting the captain's content, so an odd event
# firstmate never merges into still retires cleanly while arming warns and
# reports unknown. Such a file is the captain's to repair, never firstmate's to
# rewrite or to refuse a launch over.
# 0 when <settings-file> holds at least one hook command firstmate installed.
# Only meaningful once fm_control_claude_shared_settings_prunable has passed,
# which is what proves jq is present and the document walkable.
fm_control_claude_hooks_owned() {  # <settings-file>
  [ -s "${1-}" ] || return 1
  jq -e --arg marker "$FM_CONTROL_CLAUDE_HOOK_MARKER" \
    "$_fm_control_claude_owned_hook_program" "$1" >/dev/null 2>&1
}

fm_control_claude_shared_settings_prunable() {  # <settings-file>
  command -v jq >/dev/null 2>&1 || return 1
  [ -s "${1-}" ] || return 0
  _fm_control_claude_settings_is_one_object < "$1" || return 1
  jq --arg marker "$FM_CONTROL_CLAUDE_HOOK_MARKER" \
    "$_fm_control_claude_prune_program" "$1" >/dev/null 2>&1
}

fm_control_claude_shared_settings_mergeable() {  # <settings-file>
  fm_control_claude_shared_settings_prunable "${1-}" || return 1
  [ -s "${1-}" ] || return 0
  jq -e '[(.hooks // {}) | .[]?] | all(type == "array")' "$1" >/dev/null 2>&1
}

# The rename gives the target the temp file's umask-derived mode, so a
# captain-owned settings file the captain hardened would silently come back
# world-readable. Carry the existing mode over before the rename.
_fm_control_claude_settings_replace() {  # <settings-file> <content>
  local file=$1 content=$2 tmp=$1.tmp.$$ mode=
  if [ -f "$file" ]; then
    if [ "$(uname)" = Darwin ]; then
      mode=$(stat -f %Lp "$file" 2>/dev/null) || mode=
    else
      mode=$(stat -c %a "$file" 2>/dev/null) || mode=
    fi
  fi
  printf '%s\n' "$content" > "$tmp" || { rm -f -- "$tmp"; return 1; }
  if [ -n "$mode" ]; then
    chmod "$mode" "$tmp" || { rm -f -- "$tmp"; return 1; }
  fi
  mv -f -- "$tmp" "$file" || { rm -f -- "$tmp"; return 1; }
}

fm_control_claude_hooks_write() {  # <settings-file> <hooks-json> [owned|shared]
  local file=${1-} add=${2-} mode=${3:-owned} merged
  [ -n "$file" ] && [ -n "$add" ] || return 1
  mkdir -p "$(dirname "$file")" || return 1
  if [ "$mode" != shared ] || [ ! -s "$file" ]; then
    _fm_control_claude_settings_replace "$file" "$add" || return 1
    return 0
  fi
  fm_control_claude_shared_settings_mergeable "$file" || return 1
  merged=$(jq --argjson add "$add" --arg marker "$FM_CONTROL_CLAUDE_HOOK_MARKER" \
    "$_fm_control_claude_prune_program"'
      | ($add.hooks // {}) as $new
      | .hooks = (reduce ($new | keys_unsorted[]) as $k (.hooks; .[$k] = ((.[$k] // []) + $new[$k])))
    ' "$file") || return 1
  printf '%s\n' "$merged" | _fm_control_claude_settings_is_one_object || return 1
  _fm_control_claude_settings_replace "$file" "$merged" || return 1
}

fm_control_claude_hooks_clear() {  # <settings-file> [owned|shared]
  local file=${1-} mode=${2:-owned} pruned
  [ -n "$file" ] || return 1
  [ -e "$file" ] || return 0
  if [ "$mode" = shared ]; then
    fm_control_claude_shared_settings_prunable "$file" || return 0
    fm_control_claude_hooks_owned "$file" || return 0
    pruned=$(jq --arg marker "$FM_CONTROL_CLAUDE_HOOK_MARKER" \
      "$_fm_control_claude_prune_program"'
        | if (.hooks | length) == 0 then del(.hooks) else . end
      ' "$file") || return 1
    printf '%s\n' "$pruned" | _fm_control_claude_settings_is_one_object || return 1
    _fm_control_claude_settings_replace "$file" "$pruned" || return 1
    return 0
  fi
  rm -f -- "$file" || return 1
}

# Retire every firstmate-owned semantic lifecycle artifact a prior incarnation
# may have left in a secondmate's persistent, captain-owned home. The three
# semantic adapters' artifacts are read from the wiring table above so this
# stays one owner of where they live; the Claude settings file is the captain's
# and is only ever pruned, never removed. The prune reports success both when it
# ran and when it safely declined, so the outcome is reported here instead: 0
# when nothing firstmate-owned is left, 3 when one of the adapter artifacts could
# not be removed (the path is left in FM_CONTROL_RETIRE_FAILED_PATH and the
# Claude prune never ran), 2 when the captain's file cannot be pruned at all
# (no jq, or a document the prune program cannot walk) and nothing can be claimed
# about it either way, and 1 when the prune ran and a firstmate hook is still
# there - the only case that needs the captain to edit that file by hand.
FM_CONTROL_RETIRE_FAILED_PATH=

fm_control_secondmate_lifecycle_retire() {  # <home> <state-dir> <task-id>
  local home=${1-} state=${2-} id=${3-} settings adapter path
  FM_CONTROL_RETIRE_FAILED_PATH=
  [ -n "$home" ] && [ -n "$state" ] && [ -n "$id" ] || return 1
  settings=$home/.claude/settings.local.json
  for adapter in claude opencode pi; do
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      [ "$path" != "$settings" ] || continue
      rm -f -- "$path" || { FM_CONTROL_RETIRE_FAILED_PATH=$path; return 3; }
    done <<EOF
$(fm_control_harness_wiring_paths "$adapter" "$home" "$state" "$id")
EOF
  done
  [ -f "$settings" ] || return 0
  fm_control_claude_shared_settings_prunable "$settings" || return 2
  fm_control_claude_hooks_owned "$settings" || return 0
  fm_control_claude_hooks_clear "$settings" shared >/dev/null 2>&1 || true
  ! fm_control_claude_hooks_owned "$settings"
}
