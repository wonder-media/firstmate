#!/usr/bin/env bash
# fm-test-env-lib.sh - single owner of behavior-test process isolation.
#
# A suite entrypoint calls fm_test_env_prepare <private-root> before executing
# any test script. The function removes every inherited non-test FM_* value,
# installs a synthetic HOME and operational home, and verifies that all
# effective writable paths are inside the private root. FM_TEST_* values are
# test-runner controls rather than production overrides and remain available,
# as are the exact documented opt-in live-lane switches enumerated in
# fm_test_env_retained_name; every other FM_* value is removed.
# Tests may deliberately replace fixture overrides after this boundary.

fm_test_env_error() {
  printf 'fm-test-env: %s\n' "$*" >&2
  return 1
}

fm_test_env_canonical_dir() {
  [ -d "$1" ] || return 1
  (CDPATH= cd -P -- "$1" && pwd)
}

# Exact enumeration of the documented opt-in live-lane switches (each defaults
# to off and is consulted only by its own test) plus the two executable-path
# inputs the grok stop lane documents alongside its switch. Nothing here is
# read by production code.
fm_test_env_retained_name() {
  case "$1" in
    FM_TEST_*) return 0 ;;
    FM_AFK_PI_HERDR_E2E|\
    FM_CLAUDE_LIVE_E2E|\
    FM_CMUX_CLAUDE_COMPOSER_LIVE|\
    FM_CODEX_LIVE_E2E|\
    FM_COMPOSER_MATRIX_LIVE|\
    FM_CURSOR_PRIMARY_LIVE_E2E|\
    FM_GROK_LIVE_E2E|\
    FM_GROK_STOP_LIVE_E2E|\
    FM_GROK_NATIVE_BIN|\
    FM_GROK_LEGACY_BIN|\
    FM_HARNESS_LIVENESS_DRIFT|\
    FM_HERDR_SMOKE_REAL_CLAUDE|\
    FM_HERDR_VERSION_FLOOR_LIVE_E2E|\
    FM_MUSE_SIGNALS_LIVE|\
    FM_OPENCODE_LIVE_E2E|\
    FM_PI_LIVE_E2E|\
    FM_QUOTA_ARRAY_DISPATCH_LIVE_E2E|\
    FM_SEND_MARKER_HERDR_E2E|\
    FM_SESSIONSTART_HOOK_LIVE_E2E|\
    FM_SESSIONSTART_INSTRUCTION_REFRESH_LIVE_E2E) return 0 ;;
    *) return 1 ;;
  esac
}

fm_test_env_assert_within() {
  local candidate=$1 root=$2 canonical
  canonical=$(fm_test_env_canonical_dir "$candidate") || return 1
  case "$canonical" in
    "$root"|"$root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

fm_test_env_assert() {
  local root canonical name
  root=${FM_TEST_ENV_ROOT:-}
  [ "${FM_TEST_ENV_ISOLATED:-}" = 1 ] \
    || fm_test_env_error 'isolation marker is absent' || return 1
  [ -n "$root" ] || fm_test_env_error 'synthetic root is absent' || return 1
  canonical=$(fm_test_env_canonical_dir "$root") \
    || fm_test_env_error "synthetic root is not a directory: $root" || return 1
  [ "$canonical" = "$root" ] \
    || fm_test_env_error "synthetic root is not canonical: $root" || return 1

  for name in HOME FM_HOME; do
    [ -n "${!name:-}" ] \
      || fm_test_env_error "$name is absent at the test boundary" || return 1
    fm_test_env_assert_within "${!name}" "$root" \
      || fm_test_env_error "$name escapes the synthetic root: ${!name}" || return 1
  done

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

fm_test_env_prepare() {
  local requested_root=$1 name root
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

  # Dynamic enumeration prevents a newly introduced production FM_* control
  # from silently reaching tests. Only FM_TEST_* controls and the exact
  # documented live-lane switches survive.
  while IFS= read -r name; do
    fm_test_env_retained_name "$name" || unset "$name"
  done < <(compgen -e FM_)

  export HOME="$root/user-home"
  export FM_HOME="$root/fm-home"
  export FM_TEST_ENV_ROOT="$root"
  export FM_TEST_ENV_ISOLATED=1

  fm_test_env_assert
}

fm_test_env_run() (
  local synthetic_root=$1
  shift
  fm_test_env_prepare "$synthetic_root" || exit 1
  "$@"
)
