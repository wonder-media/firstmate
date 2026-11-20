#!/usr/bin/env bash
# Compare a pinned model with its harness's local model catalogs.
# Usage: fm-model-freshness.sh <harness> <model>
#        fm-model-freshness.sh <harness> <model> --launch <task-id> <upgrade|advisory>
# Audit mode prints only a strictly newer same-family slug, if found.
# Launch mode prints the effective model. Upgrade, pin, and catalog notices
# share one stderr line per comparison.
# The bundled Codex query is local and bounded to five seconds.
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

check_codex_catalogs() {
  local pin=$1 cache cache_input=/dev/null bundled result
  [[ "$pin" =~ ^gpt-[0-9]+(\.[0-9]+)*-(sol|astra|terra|luna)$ ]] || return 0
  cache="${CODEX_HOME:-${HOME:-}/.codex}/models_cache.json"
  [ ! -f "$cache" ] || [ ! -r "$cache" ] || cache_input=$cache
  # shellcheck source=bin/fm-timeout-lib.sh
  . "$(dirname "${BASH_SOURCE[0]}")/fm-timeout-lib.sh"
  if ! bundled=$(fm_run_timed 5 codex debug models --bundled </dev/null 2>/dev/null); then
    catalog_notice='The bundled Codex catalog could not be read. Keeping the configured model.'
    return 0
  fi

  if ! result=$(jq -ers --arg pin "$pin" --arg cache_path "$cache" \
    --rawfile cache_json <(cat "$cache_input" 2>/dev/null) '
    def valid_catalog:
      type == "object" and (.models | type == "array" and
        all(.[]; type == "object" and (.slug | type) == "string" and (.visibility | type) == "string"));

    def slug_parts:
      capture("^gpt-(?<version>[0-9]+(?:\\.[0-9]+)*)-(?<family>sol|astra|terra|luna)$")
      | .version |= (sub("(\\.0+)+$"; "") | split(".") | map(tonumber));

    (if length != 1 or (.[0] | valid_catalog | not)
     then error("invalid bundled Codex catalog") else .[0].models end) as $bundled
    | (($cache_json | try fromjson catch null)
      | if valid_catalog then . else null end) as $cached
    | (try ($cached.fetched_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | (now - .) | floor)
       catch null) as $age
    | (if $cached == null then
        "The Codex cache at \($cache_path) could not be read or parsed. Compared the bundled catalog only."
      elif $age == null or $age < 0 or $age > 604800 then
        "The Codex cache age is \($age // "unknown") seconds (maximum 604800). Compared the bundled catalog only."
      else "" end) as $notice
    | ($pin | slug_parts) as $pinned
    | $bundled + (if $notice == "" then $cached.models else [] end)
    | map(select(.visibility == "list") | .slug as $slug | .slug | slug_parts
      | select(.family == $pinned.family and .version > $pinned.version)
      | {slug: $slug, version})
    | (max_by(.version) | .slug // ""), $notice
  ' <<<"$bundled" 2>/dev/null); then
    catalog_notice='The bundled Codex catalog could not be parsed. Keeping the configured model.'
    return 0
  fi
  { IFS= read -r newer; IFS= read -r catalog_notice; } <<<"$result" || true
}

newer=
catalog_notice=
notice=
case "$harness" in
  codex) check_codex_catalogs "$model" ;;
esac

case "$mode" in
  upgrade)
    if [ -n "$newer" ]; then
      notice="Codex model for $task: $model -> $newer for this launch."
      model=$newer
    fi
    printf '%s\n' "$model"
    ;;
  advisory)
    if [ -n "$newer" ]; then
      notice="Codex model for $task: $model -> $newer available. Keeping the explicit model pin."
    fi
    printf '%s\n' "$model"
    ;;
  *) [ -z "$newer" ] || printf '%s\n' "$newer" ;;
esac
if [ -n "$catalog_notice" ]; then
  notice="${notice:-Model freshness for $model:} $catalog_notice"
fi
[ -z "$notice" ] || printf '%s\n' "$notice" >&2
