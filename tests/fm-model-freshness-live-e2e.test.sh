#!/usr/bin/env bash
# Verify the freshness reader against catalog JSON emitted by the installed
# Codex CLI in an isolated home, without refreshing the network or using tokens.
set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=tests/lib.sh
. "$TESTS_DIR/lib.sh"

fm_live_gate default-on FM_CODEX_MODEL_FRESHNESS_LIVE codex jq

version=$(codex --version)
catalog_home=$(fm_test_tmproot fm-model-freshness-live)
catalog="$catalog_home/models_cache.json"
CODEX_HOME="$catalog_home" codex debug models --bundled > "$catalog" \
  || fail "$version could not emit its bundled model catalog"

mv "$catalog" "$catalog_home/bundled.json"
fresh_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
checked=0
for scenario in fresh stale undated; do
  case "$scenario" in
    fresh) jq --arg timestamp "$fresh_timestamp" '.fetched_at = $timestamp' "$catalog_home/bundled.json" > "$catalog" ;;
    stale) jq '.fetched_at = "2000-01-01T00:00:00Z"' "$catalog_home/bundled.json" > "$catalog" ;;
    undated) jq 'del(.fetched_at)' "$catalog_home/bundled.json" > "$catalog" ;;
  esac
  for family in sol astra terra luna; do
    listed=$(jq -er --arg family "$family" '
      [.models[] | select(.visibility == "list" and (.slug | test("^gpt-[0-9.]+-" + $family + "$"))) | .slug] | join("\n")
    ' "$catalog") || fail "$version emitted an unreadable model catalog"
    [ -n "$listed" ] || continue
    newer=$(CODEX_HOME="$catalog_home" bash "$TESTS_DIR/../bin/fm-model-freshness.sh" codex "gpt-0-$family" 2> "$catalog_home/notice")
    if [ "$scenario" = fresh ]; then
      grep -Fxq -- "$newer" <<<"$listed" \
        || fail "$version did not resolve a listed $family model from a fresh catalog"
      [ ! -s "$catalog_home/notice" ] || fail "$version reported uncertainty for a fresh catalog"
      checked=$((checked + 1))
    else
      [ -z "$newer" ] || fail "$version trusted a $scenario catalog for $family"
      grep -q 'catalog age is' "$catalog_home/notice" || fail "$version omitted $scenario catalog age uncertainty for $family"
      [ "$(wc -l < "$catalog_home/notice")" -eq 1 ] || fail "$version emitted more than one $scenario uncertainty line"
    fi
  done
done
[ "$checked" -gt 0 ] || fail "$version listed no supported model families in its bundled catalog"
pass "$version bundled catalog checked $checked model families against fresh, stale, and undated timestamps"
