#!/usr/bin/env bash
# shellcheck disable=SC2034 # Public result globals are consumed by sourcing callers.
# Shared Treehouse path and slot-identity helpers for spawn and teardown.
#
# `treehouse status --json` is the authority for the managed spelling of a
# pooled worktree path. Callers compare its path with a recorded or observed
# path through physical resolution, then keep the managed spelling for every
# Treehouse command and durable metadata record.
#
# fm_treehouse_lookup_slot <path>
#   Sets FM_TREEHOUSE_SLOT_PATH, FM_TREEHOUSE_SLOT_STATUS,
#   FM_TREEHOUSE_SLOT_LEASE_HOLDER, and FM_TREEHOUSE_SLOT_LEASE_ID for the
#   status entry whose physical path matches <path>.
#   Returns 0 for a match, 1 for a valid status document with no match, 2 when
#   the installed Treehouse has no JSON status surface, and 3 when Treehouse
#   advertises JSON status but that authoritative read failed or was invalid.
#
# fm_treehouse_paths_match <left> <right>
#   Compares existing paths through physical resolution and missing leaf paths
#   through their physically resolved parent directories.
#
# fm_treehouse_write_owner <worktree> <task-id> <spawn-generation>
#   Atomically writes the ignored `.fm-treehouse-owner` slot binding used by
#   teardown to distinguish a stale task record from a reissued live slot.

FM_TREEHOUSE_SLOT_PATH=
FM_TREEHOUSE_SLOT_STATUS=
FM_TREEHOUSE_SLOT_LEASE_HOLDER=
FM_TREEHOUSE_SLOT_LEASE_ID=

fm_treehouse_path_for_compare() {
  local path=$1 parent
  [ -n "$path" ] || return 1
  if [ -d "$path" ]; then
    ( CDPATH='' cd -- "$path" 2>/dev/null && pwd -P )
    return
  fi
  parent=$(dirname "$path")
  if [ -d "$parent" ]; then
    printf '%s/%s\n' "$(CDPATH='' cd -- "$parent" 2>/dev/null && pwd -P)" "$(basename "$path")"
    return
  fi
  printf '%s\n' "$path"
}

fm_treehouse_paths_match() {
  local left right left_real right_real
  left=$1
  right=$2
  left_real=$(fm_treehouse_path_for_compare "$left") || return 1
  right_real=$(fm_treehouse_path_for_compare "$right") || return 1
  [ "$left_real" = "$right_real" ]
}

fm_treehouse_status_unavailable_rc() {
  local help
  help=$(treehouse status --help 2>&1 || true)
  if printf '%s\n' "$help" | grep -F -- '--json' >/dev/null 2>&1; then
    return 3
  fi
  return 2
}

fm_treehouse_lookup_slot() {
  local requested=$1 json rows row managed
  FM_TREEHOUSE_SLOT_PATH=
  FM_TREEHOUSE_SLOT_STATUS=
  FM_TREEHOUSE_SLOT_LEASE_HOLDER=
  FM_TREEHOUSE_SLOT_LEASE_ID=

  json=$(treehouse status --json 2>/dev/null) || {
    fm_treehouse_status_unavailable_rc
    return $?
  }
  [ -n "$json" ] || {
    fm_treehouse_status_unavailable_rc
    return $?
  }
  command -v jq >/dev/null 2>&1 || return 3
  printf '%s\n' "$json" \
    | jq -e 'type == "array" and all(.[]; (.path | type == "string") and (.status | type == "string"))' \
      >/dev/null 2>&1 || return 3
  rows=$(printf '%s\n' "$json" | jq -c '.[]') || return 3
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    managed=$(printf '%s\n' "$row" | jq -r '.path') || return 3
    if fm_treehouse_paths_match "$requested" "$managed"; then
      FM_TREEHOUSE_SLOT_PATH=$managed
      FM_TREEHOUSE_SLOT_STATUS=$(printf '%s\n' "$row" | jq -r '.status') || return 3
      FM_TREEHOUSE_SLOT_LEASE_HOLDER=$(printf '%s\n' "$row" | jq -r '.lease_holder // ""') || return 3
      FM_TREEHOUSE_SLOT_LEASE_ID=$(printf '%s\n' "$row" | jq -r '.lease_id // ""') || return 3
      return 0
    fi
  done <<EOF
$rows
EOF
  return 1
}

fm_treehouse_write_owner() {
  local worktree=$1 task_id=$2 spawn_gen=$3 marker tmp
  [ -d "$worktree" ] || return 1
  marker="$worktree/.fm-treehouse-owner"
  tmp="$worktree/.fm-treehouse-owner.tmp.${BASHPID:-$$}"
  {
    printf 'task_id=%s\n' "$task_id"
    printf 'spawn_gen=%s\n' "$spawn_gen"
  } > "$tmp" || return 1
  mv -f "$tmp" "$marker"
}
