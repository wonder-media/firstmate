#!/usr/bin/env bash
# Shared marker-or-plain-checkout predicate for tracked hooks that must act only
# in a genuine firstmate primary home.
# This file is sourced by hook entrypoints and has no side effects on source.

# Return 0 when $1 carries a genuine secondmate-home marker.
fm_root_is_secondmate_home() {
  local marker="$1/.fm-secondmate-home" id LC_ALL=C
  [ -L "$marker" ] && return 1
  [ -f "$marker" ] || return 1
  IFS= read -r id < "$marker" 2>/dev/null || return 1
  id=${id//[[:space:]]/}
  [ -n "$id" ] || return 1
  case "$id" in
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

# Return 0 when $1 is a genuine primary checkout.
# A valid secondmate marker force-includes a linked secondmate home.
# Otherwise only a plain checkout is primary, never a linked task worktree.
fm_primary_checkout_matches() {
  local root=$1 git_dir git_common_dir
  if ! fm_root_is_secondmate_home "$root"; then
    git_dir=$(git -C "$root" rev-parse --git-dir 2>/dev/null) || return 1
    git_common_dir=$(git -C "$root" rev-parse --git-common-dir 2>/dev/null) || return 1
    [ "$git_dir" = "$git_common_dir" ] || return 1
  fi
  [ -f "$root/AGENTS.md" ] || return 1
  [ -d "$root/bin" ] || return 1
}

# Return 0 when $1 is a genuine primary root whose effective state dir is $2.
fm_primary_scope_matches() {
  local root=$1 state=$2
  fm_primary_checkout_matches "$root" || return 1
  [ -d "$state" ] || return 1
}

# Bind a primary-session or primary-hook entrypoint to the checkout that carries
# the running script.
#
# Return 0 with FM_ROOT, FM_HOME, STATE, and CONFIG bound to that checkout.
# Return 1 silently for an unmarked linked task worktree or another non-primary
# checkout, because tracked hooks propagate there and must stay inert.
# Return 2 after printing a diagnostic when inherited home identity disagrees
# with the running checkout, because reading or mutating either home would be
# unsafe.
fm_primary_home_bind() {  # <running-checkout>
  local checkout=$1 checkout_real inherited inherited_name inherited_real override_real
  checkout_real=$(CDPATH='' cd -- "$checkout" 2>/dev/null && pwd -P) || return 1
  fm_primary_checkout_matches "$checkout_real" || return 1

  inherited_name=FM_HOME
  inherited=${FM_HOME:-}
  if [ -z "$inherited" ]; then
    inherited_name=FM_ROOT_OVERRIDE
    inherited=${FM_ROOT_OVERRIDE:-$checkout_real}
  fi
  inherited_real=$(CDPATH='' cd -- "$inherited" 2>/dev/null && pwd -P) || {
    printf 'error: firstmate home mismatch: running checkout %s; inherited %s %s is unavailable; refusing to read, lock, or mutate either home\n' \
      "$checkout_real" "$inherited_name" "$inherited" >&2
    return 2
  }
  if [ "$inherited_real" != "$checkout_real" ]; then
    printf 'error: firstmate home mismatch: running checkout %s; inherited %s resolves to %s; refusing to read, lock, or mutate either home\n' \
      "$checkout_real" "$inherited_name" "$inherited_real" >&2
    return 2
  fi

  if [ -n "${FM_ROOT_OVERRIDE:-}" ]; then
    override_real=$(CDPATH='' cd -- "$FM_ROOT_OVERRIDE" 2>/dev/null && pwd -P) || {
      printf 'error: firstmate checkout mismatch: running checkout %s; inherited FM_ROOT_OVERRIDE %s is unavailable; refusing to read, lock, or mutate either home\n' \
        "$checkout_real" "$FM_ROOT_OVERRIDE" >&2
      return 2
    }
    if [ "$override_real" != "$checkout_real" ]; then
      printf 'error: firstmate checkout mismatch: running checkout %s; inherited FM_ROOT_OVERRIDE resolves to %s; refusing to read, lock, or mutate either home\n' \
        "$checkout_real" "$override_real" >&2
      return 2
    fi
  fi

  # Compare physical identities, but preserve the caller's matching spelling.
  # Watcher ownership records intentionally use exact path strings, so
  # canonicalizing an otherwise-valid /var versus /private/var spelling here
  # would make a healthy existing watcher look foreign.
  FM_ROOT=$checkout
  FM_HOME=$inherited
  # shellcheck disable=SC2034 # Function outputs consumed by sourcing entrypoints.
  STATE=${FM_STATE_OVERRIDE:-$FM_HOME/state}
  # shellcheck disable=SC2034 # Function outputs consumed by sourcing entrypoints.
  CONFIG=${FM_CONFIG_OVERRIDE:-$FM_HOME/config}
  export FM_ROOT FM_HOME
  return 0
}
