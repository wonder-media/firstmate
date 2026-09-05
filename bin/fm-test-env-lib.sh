#!/usr/bin/env bash
# fm-test-env-lib.sh - single owner of behavior-test process isolation.
#
# A suite entrypoint calls fm_test_env_prepare <private-root> before executing
# any test script. The function removes every inherited non-test FM_* value,
# installs a synthetic HOME and operational home, and verifies that all
# effective writable paths are inside the private root. FM_TEST_* values are
# test-runner controls rather than production overrides and remain available.
# Tests may deliberately replace fixture overrides after this boundary.

fm_test_env_error() {
  printf 'fm-test-env: %s\n' "$*" >&2
  return 1
}

fm_test_env_canonical_dir() {
  [ -d "$1" ] || return 1
  (CDPATH= cd -P -- "$1" && pwd)
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
    case "$name" in
      FM_TEST_*|FM_HOME) ;;
      *) fm_test_env_error "inherited production variable survived isolation: $name" || return 1 ;;
    esac
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
  # from silently reaching tests. FM_TEST_* is the reserved test-control
  # namespace and is intentionally retained.
  while IFS= read -r name; do
    case "$name" in
      FM_TEST_*) ;;
      *) unset "$name" ;;
    esac
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
