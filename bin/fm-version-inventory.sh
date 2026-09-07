#!/usr/bin/env bash
# Print an explicit read-only maintenance inventory for Firstmate-owned tools.
#
# Usage: fm-version-inventory.sh
#
# This command is deliberately separate from bootstrap. Bootstrap performs only
# offline presence, feature, and compatibility-floor checks; it never asks a
# release channel what is newest. This opt-in command reads installed versions
# and makes one hard-bounded request per owning release channel. It never
# installs, upgrades, starts, stops, or configures a tool. Herdr is limited to `--version`; its live protocol is not queried.
#
# Output is tab-separated with distinct installed, minimum-supported,
# available-stable, compatibility, freshness, intentionally-pinned, and channel
# fields. unknown/offline is an ordinary maintenance result, not a compatibility
# failure.
#
# Bounds:
#   FM_VERSION_INVENTORY_TIMEOUT  seconds per local probe or release request
#                                 (default 8, positive integer, maximum 30)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-timeout-lib.sh
. "$SCRIPT_DIR/fm-timeout-lib.sh"
# shellcheck source=bin/fm-tool-versions-lib.sh
. "$SCRIPT_DIR/fm-tool-versions-lib.sh"

usage() {
  printf 'usage: fm-version-inventory.sh\n' >&2
}

case "${1:-}" in
  "") ;;
  --help|-h) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac
[ $# -le 1 ] || { usage; exit 2; }

TIMEOUT=${FM_VERSION_INVENTORY_TIMEOUT:-8}
case "$TIMEOUT" in
  ''|*[!0-9]*|0)
    printf 'error: FM_VERSION_INVENTORY_TIMEOUT must be a positive integer\n' >&2
    exit 2
    ;;
esac
[ "$TIMEOUT" -le 30 ] || {
  printf 'error: FM_VERSION_INVENTORY_TIMEOUT must not exceed 30 seconds\n' >&2
  exit 2
}

normalize_version() {
  printf '%s\n' "$1" |
    sed -nE 's/(^|.*[^0-9.])[vV]?([0-9]+)\.([0-9]+)\.([0-9]+).*/\2.\3.\4/p' |
    head -n 1
}

installed_version() {
  local tool=$1 output version
  command -v "$tool" >/dev/null 2>&1 || { printf 'not-installed\n'; return 0; }
  output=$(fm_run_timed "$TIMEOUT" "$tool" --version </dev/null 2>/dev/null) \
    || { printf 'unknown\n'; return 0; }
  version=$(normalize_version "$output")
  printf '%s\n' "${version:-unknown}"
}

github_stable() {
  local repo=$1 output version
  command -v gh-axi >/dev/null 2>&1 || { printf 'unknown/offline\n'; return 0; }
  output=$(fm_run_timed "$TIMEOUT" env GH_REPO="$repo" gh-axi release list \
    --exclude-drafts --exclude-pre-releases --limit 1 </dev/null 2>/dev/null) \
    || { printf 'unknown/offline\n'; return 0; }
  version=$(printf '%s\n' "$output" |
    sed -nE 's/^[[:space:]]*v?([0-9]+\.[0-9]+\.[0-9]+),.*/\1/p' |
    head -n 1)
  printf '%s\n' "${version:-unknown/offline}"
}

npm_stable() {
  local package=$1 output version
  command -v npm >/dev/null 2>&1 || { printf 'unknown/offline\n'; return 0; }
  output=$(fm_run_timed "$TIMEOUT" npm view "$package" version </dev/null 2>/dev/null) \
    || { printf 'unknown/offline\n'; return 0; }
  version=$(normalize_version "$output")
  printf '%s\n' "${version:-unknown/offline}"
}

version_relation() {  # <installed> <available>: older|equal|newer|unknown
  local installed=$1 available=$2 i_major i_minor i_patch a_major a_minor a_patch
  case "$installed:$available" in
    *[!0-9.:]*) printf 'unknown\n'; return 0 ;;
  esac
  IFS=. read -r i_major i_minor i_patch <<< "$installed"
  IFS=. read -r a_major a_minor a_patch <<< "$available"
  if [ "$i_major" -lt "$a_major" ] \
    || { [ "$i_major" -eq "$a_major" ] && [ "$i_minor" -lt "$a_minor" ]; } \
    || { [ "$i_major" -eq "$a_major" ] && [ "$i_minor" -eq "$a_minor" ] && [ "$i_patch" -lt "$a_patch" ]; }; then
    printf 'older\n'
  elif [ "$installed" = "$available" ]; then
    printf 'equal\n'
  else
    printf 'newer\n'
  fi
}

semver_compatibility() {  # <installed> <floor>
  local installed=$1 floor=$2 relation
  case "$installed" in
    not-installed) printf 'not-installed\n'; return 0 ;;
    unknown) printf 'unknown\n'; return 0 ;;
  esac
  relation=$(version_relation "$installed" "$floor")
  case "$relation" in
    older) printf 'below-minimum\n' ;;
    equal|newer) printf 'supported\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

treehouse_compatibility() {
  local installed=$1 output
  [ "$installed" != not-installed ] || { printf 'not-installed\n'; return 0; }
  [ "$installed" != unknown ] || { printf 'unknown\n'; return 0; }
  output=$(fm_run_timed "$TIMEOUT" treehouse get --help </dev/null 2>/dev/null) \
    || { printf 'unknown\n'; return 0; }
  if fm_treehouse_help_declares_lease "$output"; then
    printf 'supported\n'
  else
    printf 'below-minimum\n'
  fi
}

freshness() {  # <installed> <available> <pin>
  local installed=$1 available=$2 pin=$3 relation
  case "$installed" in
    not-installed) printf 'not-installed\n'; return 0 ;;
    unknown) printf 'unknown\n'; return 0 ;;
  esac
  [ "$available" != unknown/offline ] || { printf 'unknown/offline\n'; return 0; }
  if [ "$pin" != none ] && [ "$installed" = "${pin#CI=}" ]; then
    printf 'intentionally-pinned\n'
    return 0
  fi
  relation=$(version_relation "$installed" "$available")
  case "$relation" in
    older) printf 'update-available\n' ;;
    equal) printf 'current-stable\n' ;;
    newer) printf 'ahead-of-stable\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

inventory_row() {  # <tool> <minimum> <pin> <channel-kind> <channel-id>
  local tool=$1 minimum=$2 pin=$3 channel_kind=$4 channel_id=$5 installed available compatibility state
  installed=$(installed_version "$tool")
  case "$channel_kind" in
    github) available=$(github_stable "$channel_id") ;;
    npm) available=$(npm_stable "$channel_id") ;;
    *) available=unknown/offline ;;
  esac
  case "$tool" in
    treehouse) compatibility=$(treehouse_compatibility "$installed") ;;
    herdr)
      if [ "$installed" = not-installed ]; then compatibility=not-installed
      else compatibility='unknown (protocol not probed)'
      fi
      ;;
    chrome-devtools-axi)
      if [ "$installed" = not-installed ]; then compatibility=not-installed
      elif [ "$installed" = unknown ]; then compatibility=unknown
      else compatibility=supported
      fi
      ;;
    *) compatibility=$(semver_compatibility "$installed" "$minimum") ;;
  esac
  state=$(freshness "$installed" "$available" "$pin")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$tool" "$installed" "$minimum" "$available" "$compatibility" "$state" "$pin" "$channel_kind:$channel_id"
}

printf 'tool\tinstalled\tminimum-supported\tavailable-stable\tcompatibility\tfreshness\tintentionally-pinned\trelease-channel\n'
inventory_row no-mistakes "$FM_NO_MISTAKES_MIN" none github "$FM_NO_MISTAKES_RELEASE_REPO"
inventory_row treehouse lease-capable "CI=$FM_TREEHOUSE_CI_VERSION" github "$FM_TREEHOUSE_CI_REPO"
inventory_row herdr "protocol>=$FM_BACKEND_HERDR_MIN_PROTOCOL" "CI=$FM_HERDR_CI_VERSION" github "$FM_HERDR_CI_REPO"
inventory_row gh-axi "$FM_GH_AXI_MIN" none npm gh-axi
inventory_row chrome-devtools-axi present none npm chrome-devtools-axi
inventory_row lavish-axi "$FM_LAVISH_AXI_MIN" none npm lavish-axi
inventory_row tasks-axi "$FM_TASKS_AXI_MIN" none npm tasks-axi
inventory_row quota-axi "$FM_QUOTA_AXI_MIN" none npm quota-axi
