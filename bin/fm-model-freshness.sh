#!/usr/bin/env bash
# Compare a pinned model with its harness's local model catalog.
# Usage: fm-model-freshness.sh <harness> <model>
#        fm-model-freshness.sh <harness> <model> --launch <task-id> <upgrade|advisory>
# Audit mode prints only a strictly newer same-family slug, if found.
# Launch mode prints the effective model and sends one notice to stderr when
# a newer model is found. Catalog errors go to stderr and leave the pin usable.
set -euo pipefail

usage='usage: fm-model-freshness.sh <harness> <model> [--launch <task-id> <upgrade|advisory>]'
if [ "$#" -eq 1 ] && [ "$1" = --help ]; then
  printf '%s\n' "$usage"
  exit 0
fi

harness=${1:-}
model=${2:-}
task=
mode=
case $# in
  2) ;;
  5)
    if [ "$3" = --launch ] && [ -n "$4" ] && { [ "$5" = upgrade ] || [ "$5" = advisory ]; }; then
      task=$4
      mode=$5
    fi
    ;;
esac
if [ "$#" -ne 2 ] && [ -z "$mode" ]; then
  printf '%s\n' "$usage" >&2
  exit 2
fi

codex_newer_model() {
  local pin=$1 cache newer
  [[ "$pin" =~ ^gpt-[0-9]+(\.[0-9]+)*-(sol|astra|terra|luna)$ ]] || return 0
  cache="${CODEX_HOME:-${HOME:-}/.codex}/models_cache.json"
  if [ -f "$cache" ] && [ -r "$cache" ] && newer=$(jq -ers --arg pin "$pin" '
    def slug_parts:
      capture("^gpt-(?<version>[0-9]+(?:\\.[0-9]+)*)-(?<family>sol|astra|terra|luna)$")
      | .version |= (sub("(\\.0+)+$"; "") | split(".") | map(tonumber));

    if length != 1 or (.[0].models | type) != "array"
      or (.[0].models | any(type != "object" or (.slug | type) != "string"
        or (.visibility | type) != "string"))
    then error("invalid Codex model catalog")
    else .[0].models end
    | ($pin | slug_parts) as $pinned
    | map(select(.visibility == "list") | .slug as $slug | .slug | slug_parts
      | select(.family == $pinned.family and .version > $pinned.version)
      | {slug: $slug, version})
    | max_by(.version) | .slug // ""
  ' "$cache" 2>/dev/null); then
    printf '%s' "$newer"
  else
    printf 'Model freshness for %s is unknown because the Codex catalog at %s could not be read or parsed.\n' "$pin" "$cache" >&2
  fi
}

newer=
case "$harness" in
  codex) newer=$(codex_newer_model "$model") ;;
esac

case "$mode" in
  upgrade)
    if [ -n "$newer" ]; then
      printf 'Codex model for %s: %s -> %s for this launch.\n' "$task" "$model" "$newer" >&2
      model=$newer
    fi
    printf '%s\n' "$model"
    ;;
  advisory)
    if [ -n "$newer" ]; then
      printf 'Codex model for %s: %s -> %s available. Keeping the explicit override.\n' "$task" "$model" "$newer" >&2
    fi
    printf '%s\n' "$model"
    ;;
  *) [ -z "$newer" ] || printf '%s\n' "$newer" ;;
esac
