#!/usr/bin/env bash
# fm-test-env-lib.sh - single owner of behavior-test process isolation.
#
# A suite entrypoint calls fm_test_env_prepare <private-root> before executing
# any test script. The function removes every inherited non-test FM_* value,
# installs a synthetic HOME and operational home, and verifies that all
# effective writable paths are inside the private root. FM_TEST_* values are
# test-runner controls rather than production overrides and remain available,
# as are the exact documented opt-in switches enumerated in
# FM_TEST_ENV_LIVE_SWITCHES and FM_TEST_ENV_RETAINED_SWITCHES; every other FM_*
# value is removed.
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
  (CDPATH='' cd -P -- "$1" && pwd)
}

# Exact enumeration of the documented opt-in live-lane switches: every control
# variable a guard passes to tests/lib.sh's fm_live_gate, plus the family-wide
# FM_LIVE. Each defaults to off and is consulted only by its own test; nothing
# here is read by production code. Enabling one keeps the inherited HOME, so a
# switch belongs here only when its lane launches a real harness binary that
# needs its login. A new fm_live_gate variable must be added here, or the
# isolation boundary removes it and the guard can never be turned on.
FM_TEST_ENV_LIVE_SWITCHES='
  FM_AFK_PI_HERDR_E2E
  FM_AGY_PRIMARY_LIVE
  FM_AGY_PRIMARY_LIVE_E2E
  FM_AGY_SIGNALS_LIVE
  FM_BEARINGS_LAVISH_LIVE
  FM_CALM_PI_QUEUE_RETENTION_LIVE
  FM_CLAUDE_CALM_LIVE_E2E
  FM_CLAUDE_CALM_PLUGIN_TEST
  FM_CLAUDE_LIVE_E2E
  FM_CMUX_CLAUDE_COMPOSER_LIVE
  FM_CODEX_HOOK_LAYER_LIVE
  FM_CODEX_LIVE_E2E
  FM_COMMANDCODE_SIGNALS_LIVE
  FM_COMPOSER_CODEX_IDLE_LIVE
  FM_COMPOSER_MATRIX_LIVE
  FM_CORTEX_SIGNALS_LIVE
  FM_CURSOR_PRIMARY_LIVE_E2E
  FM_DEVIN_SIGNALS_LIVE
  FM_GROK_LIVE_E2E
  FM_GROK_STOP_LIVE_E2E
  FM_HARNESS_ADAPTER_INSTRUCTION_EVAL
  FM_HARNESS_LIVENESS_DRIFT
  FM_HC_LIVENESS_DRIFT
  FM_HERDR_AGENT_EXIT_SHELL_E2E
  FM_HERDR_ATTACHED_VIEWER_LIVE_E2E
  FM_HERDR_PI_STALE_REGISTRATION_LIVE_E2E
  FM_HERDR_PROJECTED_CD_LIVE_E2E
  FM_HERDR_SMOKE_REAL_CLAUDE
  FM_HERDR_SUBMIT_CONFIRM_LIVE
  FM_HERDR_VERSION_FLOOR_LIVE_E2E
  FM_HERMES_GATEWAY_LIVE
  FM_HERMES_PROFILE_SAFETY_LIVE
  FM_HERMES_SIGNALS_LIVE
  FM_HOST_MIRROR_LIVE_E2E
  FM_KIMI_TRUST_PROMPT_LIVE
  FM_KIRO_SIGNALS_LIVE
  FM_LAUNCH_PROMPT_SIGNALS_LIVE
  FM_LIVE
  FM_MUSE_SIGNALS_LIVE
  FM_OMP_LIVE_E2E
  FM_OPENCODE_ABS_CWD_LIVE
  FM_OPENCODE_LIVE_E2E
  FM_OPENCODE_V2_OFFLINE_LIVE
  FM_PI_BRANCH_LIVE_E2E
  FM_PI_BRANCH_RESPONSIVENESS_E2E
  FM_PI_CODEX_NATIVE_LIVE
  FM_PI_LIVE_E2E
  FM_PI_SEEDED_HOME_TRUST_LIVE
  FM_PI_SESSIONSTART_RACE_LIVE_E2E
  FM_PI_WORKER_STREAM_LIVE
  FM_POLYTOKEN_SIGNALS_LIVE
  FM_PR_STATE_LIVE_E2E
  FM_QUOTA_ARRAY_DISPATCH_LIVE_E2E
  FM_READ_REPETITION_LIVE
  FM_REX_COMPOSER_LIVE
  FM_ROVO_SIGNALS_LIVE
  FM_SECONDMATE_BUSY_LIVE
  FM_SEND_INBOX_LIVE_E2E
  FM_SEND_MARKER_HERDR_E2E
  FM_SESSIONSTART_HOOK_LIVE_E2E
  FM_SESSIONSTART_INSTRUCTION_REFRESH_LIVE_E2E
  FM_SUPERVISION_HOST_ATTENDED_LIVE_E2E
  FM_SUPERVISION_HOST_LIVE_E2E
  FM_T3CODE_LIVE_E2E
  FM_T3CODE_PR_TOOLS_LIVE
  FM_T3_CODEX_CONFIG_LIVE
  FM_WARM_COMPACT_LIVE_E2E
  FM_WATCH_WEDGE_CAP_LIVE
  FM_WORKER_ACCOUNT_LIVE_E2E
'

# Exact enumeration of documented opt-ins and lane inputs that only a test or
# its lab tooling reads and that need no login home. They survive the boundary
# but never grant the inherited HOME. FM_FAKE_LIVE and FM_FAKE_ALT_LIVE are
# tests/fm-live-gate.test.sh's stand-in gate variables.
FM_TEST_ENV_RETAINED_SWITCHES='
  FM_AGY_BIN
  FM_AGY_LIVE_MODEL
  FM_BOARD_BROWSER_SIZE
  FM_BOARD_BROWSER_TEST
  FM_CHROME_BIN
  FM_COMMANDCODE_MODEL
  FM_COMPOSER_CODEX_IDLE_LIVE_POLLS
  FM_COMPOSER_MATRIX_LIVE_POLLS
  FM_CONTAINER_RUNTIME
  FM_CORTEX_MODEL
  FM_CURSOR_BIN
  FM_DEVIN_MODEL
  FM_EXTENSION_BINDING_COORDINATOR_TIMEOUT_SECONDS
  FM_FAKE_ALT_LIVE
  FM_FAKE_LIVE
  FM_GROK_AUTH_FILE
  FM_GROK_STOP_LIVE_TIMEOUT
  FM_HARNESS_ADAPTER_EVAL_TIMEOUT_SECONDS
  FM_HARNESS_ADAPTER_LOCAL_MODEL
  FM_HERDR_LAB_FLEET_SESSION
  FM_HERMES_LIVE_HOME
  FM_HERMES_LIVE_KEEP
  FM_HERMES_LIVE_PROFILE
  FM_HERMES_PYTHON
  FM_HOST_MIRROR_LIVE_HARNESSES
  FM_LANE_CAPACITY_BASELINE_REF
  FM_OMP_LIVE_KEEP
  FM_OMP_LIVE_MODEL
  FM_OPENCODE_LIVE_BINS
  FM_PI_BIN
  FM_PI_LIVE_WATCH_ONLY
  FM_PI_PACKAGE_DIR
  FM_PI_TYPES_ARTIFACT_DIR
  FM_REX_COMPOSER_LIVE_POLLS
  FM_SECONDMATE_CONVERGENCE_TIMEOUT
  FM_SEND_INBOX_LIVE_HARNESSES
  FM_SEND_INBOX_LIVE_TIMEOUT
  FM_SESSIONSTART_INSTRUCTION_REFRESH_EXPECT
  FM_SESSIONSTART_INSTRUCTION_REFRESH_REF
  FM_STANDALONE_CALM_SHIP
  FM_SUPERVISION_HOST_ATTENDED_LIVE_CONTROL_REF
  FM_SUPERVISION_HOST_ATTENDED_LIVE_CONTROL_SECONDS
  FM_SUPERVISION_HOST_ATTENDED_LIVE_MODEL
  FM_SUPERVISION_HOST_ATTENDED_LIVE_POLLS
  FM_SUPERVISION_HOST_LIVE_POLLS
  FM_T3CODE_LIVE_CLAUDE_INSTANCE
  FM_T3CODE_LIVE_CLAUDE_MODEL
  FM_T3CODE_LIVE_TOKEN_FILE
  FM_TMUX_ISOLATION_PROBE_SECONDS
  FM_WARM_COMPACT_LIVE_MODEL
  FM_WARM_COMPACT_LIVE_POLLS
  FM_WARM_COMPACT_LIVE_TRACE
'

# Retained across the boundary: test controls, both enumerations above, and the
# executable-path inputs the grok stop and hc lanes document beside their
# switches.
fm_test_env_retained_name() {
  local switch
  case "$1" in
    FM_TEST_*|FM_GROK_NATIVE_BIN|FM_GROK_LEGACY_BIN|FM_HC_BIN) return 0 ;;
  esac
  for switch in $FM_TEST_ENV_LIVE_SWITCHES $FM_TEST_ENV_RETAINED_SWITCHES; do
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
