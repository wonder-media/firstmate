#!/usr/bin/env bash
# fm-test-env-lib.sh - single owner of behavior-test process isolation.
#
# A suite entrypoint calls fm_test_env_prepare <private-root> before executing
# any test script. The function removes every inherited non-test FM_* value,
# installs a synthetic HOME and operational home, and verifies that all
# effective writable paths are inside the private root. FM_TEST_* values are
# test-runner controls rather than production overrides and remain available,
# as are the exact documented opt-in live-lane switches enumerated in
# FM_TEST_ENV_LIVE_SWITCHES; every other FM_* value is removed.
#
# A live lane that is explicitly enabled (switch value 1) keeps the inherited
# HOME so the real harness binaries it launches find their existing logins; its
# operational home and every FM_* production value are still synthetic.
#
# Tests may deliberately replace fixture overrides after this boundary. A
# nested child that re-enters the boundary (fm_test_env_assert_inherited) keeps
# those fixtures and only proves that every effective path stays inside the
# synthetic root or the temp root recorded at isolation time.

fm_test_env_error() {
  printf 'fm-test-env: %s\n' "$*" >&2
  return 1
}

fm_test_env_canonical_dir() {
  [ -d "$1" ] || return 1
  (CDPATH= cd -P -- "$1" && pwd)
}

# Exact enumeration of the documented opt-in live-lane switches. Each defaults
# to off and is consulted only by its own test; nothing here is read by
# production code.
FM_TEST_ENV_LIVE_SWITCHES='
  FM_AFK_PI_HERDR_E2E
  FM_CLAUDE_LIVE_E2E
  FM_CMUX_CLAUDE_COMPOSER_LIVE
  FM_CODEX_LIVE_E2E
  FM_COMPOSER_MATRIX_LIVE
  FM_CURSOR_PRIMARY_LIVE_E2E
  FM_GROK_LIVE_E2E
  FM_GROK_STOP_LIVE_E2E
  FM_HARNESS_LIVENESS_DRIFT
  FM_HERDR_SMOKE_REAL_CLAUDE
  FM_HERDR_VERSION_FLOOR_LIVE_E2E
  FM_MUSE_SIGNALS_LIVE
  FM_OPENCODE_LIVE_E2E
  FM_PI_LIVE_E2E
  FM_QUOTA_ARRAY_DISPATCH_LIVE_E2E
  FM_SEND_MARKER_HERDR_E2E
  FM_SESSIONSTART_HOOK_LIVE_E2E
  FM_SESSIONSTART_INSTRUCTION_REFRESH_LIVE_E2E
'

# Retained across the boundary: test controls, the live switches above, and the
# two executable-path inputs the grok stop lane documents beside its switch.
fm_test_env_retained_name() {
  local switch
  case "$1" in
    FM_TEST_*|FM_GROK_NATIVE_BIN|FM_GROK_LEGACY_BIN) return 0 ;;
  esac
  for switch in $FM_TEST_ENV_LIVE_SWITCHES; do
    [ "$1" = "$switch" ] && return 0
  done
  return 1
}

fm_test_env_live_lane_enabled() {
  local switch
  for switch in $FM_TEST_ENV_LIVE_SWITCHES; do
    [ "${!switch:-}" = 1 ] && return 0
  done
  return 1
}

# Canonicalize an absolute path that may not exist yet by resolving its deepest
# existing ancestor and re-appending the remainder.
fm_test_env_canonical_path() {
  local path=$1 rest="" head
  case "$path" in
    /*) ;;
    *) return 1 ;;
  esac
  while [ ! -d "$path" ]; do
    rest="/${path##*/}$rest"
    path=${path%/*}
    [ -n "$path" ] || path=/
  done
  head=$(fm_test_env_canonical_dir "$path") || return 1
  [ "$head" != / ] || head=""
  [ -n "$head$rest" ] || rest=/
  printf '%s%s\n' "$head" "$rest"
}

fm_test_env_assert_within() {
  local candidate=$1 root=$2 canonical
  canonical=$(fm_test_env_canonical_dir "$candidate") || return 1
  case "$canonical" in
    "$root"|"$root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

fm_test_env_assert_root() {
  local root canonical
  root=${FM_TEST_ENV_ROOT:-}
  [ "${FM_TEST_ENV_ISOLATED:-}" = 1 ] \
    || fm_test_env_error 'isolation marker is absent' || return 1
  [ -n "$root" ] || fm_test_env_error 'synthetic root is absent' || return 1
  canonical=$(fm_test_env_canonical_dir "$root") \
    || fm_test_env_error "synthetic root is not a directory: $root" || return 1
  [ "$canonical" = "$root" ] \
    || fm_test_env_error "synthetic root is not canonical: $root" || return 1
  [ -n "${FM_TEST_ENV_TMP:-}" ] \
    || fm_test_env_error 'isolated temp root is absent' || return 1
  [ -n "${HOME:-}" ] || fm_test_env_error 'HOME is absent at the test boundary' || return 1
  [ -n "${FM_HOME:-}" ] || fm_test_env_error 'FM_HOME is absent at the test boundary' || return 1
}

# Strict post-preparation contract: the operational home and every effective
# path live inside the synthetic root and no production FM_* value survived.
fm_test_env_assert() {
  local root name
  fm_test_env_assert_root || return 1
  root=$FM_TEST_ENV_ROOT

  if ! fm_test_env_live_lane_enabled; then
    fm_test_env_assert_within "$HOME" "$root" \
      || fm_test_env_error "HOME escapes the synthetic root: $HOME" || return 1
  fi
  fm_test_env_assert_within "$FM_HOME" "$root" \
    || fm_test_env_error "FM_HOME escapes the synthetic root: $FM_HOME" || return 1

  for name in FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE \
    FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE; do
    [ -z "${!name+x}" ] \
      || fm_test_env_error "inherited override survived isolation: $name" || return 1
  done
  for name in state data config projects; do
    fm_test_env_assert_within "$FM_HOME/$name" "$root" \
      || fm_test_env_error "effective $name path escapes the synthetic root" || return 1
  done

  while IFS= read -r name; do
    [ "$name" = FM_HOME ] && continue
    fm_test_env_retained_name "$name" \
      || fm_test_env_error "inherited production variable survived isolation: $name" || return 1
  done < <(compgen -e FM_)
}

fm_test_env_assert_disposable() {  # <label> <path>
  local canonical
  canonical=$(fm_test_env_canonical_path "$2") \
    || fm_test_env_error "$1 is not an absolute path: $2" || return 1
  case "$canonical" in
    "$FM_TEST_ENV_ROOT"|"$FM_TEST_ENV_ROOT"/*|"$FM_TEST_ENV_TMP"|"$FM_TEST_ENV_TMP"/*) return 0 ;;
  esac
  fm_test_env_error "$1 escapes the isolated fixture roots: $2"
}

# Nested contract for a child of an already isolated process: fixtures the
# parent installed after isolation are kept, and every effective path must
# still be disposable.
fm_test_env_assert_inherited() {
  local data
  fm_test_env_assert_root || return 1
  if ! fm_test_env_live_lane_enabled; then
    fm_test_env_assert_disposable HOME "$HOME" || return 1
  fi
  data=${FM_DATA_OVERRIDE:-$FM_HOME/data}
  fm_test_env_assert_disposable FM_HOME "$FM_HOME" || return 1
  fm_test_env_assert_disposable 'effective state path' "${FM_STATE_OVERRIDE:-$FM_HOME/state}" || return 1
  fm_test_env_assert_disposable 'effective data path' "$data" || return 1
  fm_test_env_assert_disposable 'effective config path' "${FM_CONFIG_OVERRIDE:-$FM_HOME/config}" || return 1
  fm_test_env_assert_disposable 'effective projects path' "${FM_PROJECTS_OVERRIDE:-$FM_HOME/projects}" || return 1
  fm_test_env_assert_disposable 'secondmate registry' "$data/secondmates.md" || return 1
}

fm_test_env_prepare() {
  local requested_root=$1 name root tmp
  case "$requested_root" in
    /*) ;;
    *) fm_test_env_error "synthetic root must be absolute: $requested_root" || return 1 ;;
  esac

  mkdir -p "$requested_root/user-home" "$requested_root/fm-home/state" \
    "$requested_root/fm-home/data" "$requested_root/fm-home/config" \
    "$requested_root/fm-home/projects" || return 1
  chmod 0700 "$requested_root" "$requested_root/user-home" \
    "$requested_root/fm-home" "$requested_root/fm-home/state" \
    "$requested_root/fm-home/data" "$requested_root/fm-home/config" \
    "$requested_root/fm-home/projects" || return 1
  root=$(fm_test_env_canonical_dir "$requested_root") || return 1
  tmp=$(fm_test_env_canonical_dir "${TMPDIR:-/tmp}") \
    || fm_test_env_error "temp root is not a directory: ${TMPDIR:-/tmp}" || return 1

  # Dynamic enumeration prevents a newly introduced production FM_* control
  # from silently reaching tests. Only FM_TEST_* controls and the exact
  # documented live-lane switches survive.
  while IFS= read -r name; do
    fm_test_env_retained_name "$name" || unset "$name"
  done < <(compgen -e FM_)

  fm_test_env_live_lane_enabled || export HOME="$root/user-home"
  export FM_HOME="$root/fm-home"
  export FM_TEST_ENV_ROOT="$root"
  export FM_TEST_ENV_TMP="$tmp"
  export FM_TEST_ENV_ISOLATED=1

  fm_test_env_assert
}

fm_test_env_run() (
  local synthetic_root=$1
  shift
  fm_test_env_prepare "$synthetic_root" || exit 1
  "$@"
)
