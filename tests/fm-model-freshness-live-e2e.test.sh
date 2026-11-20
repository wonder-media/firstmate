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
bundled="$catalog_home/bundled.json"
CODEX_HOME="$catalog_home" codex debug models --bundled > "$bundled" \
  || fail "$version could not emit its bundled model catalog"

fresh_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
checked=0
for scenario in fresh stale undated; do
  case "$scenario" in
    fresh) jq -n --arg timestamp "$fresh_timestamp" '{fetched_at: $timestamp, models: []}' > "$catalog" ;;
    stale|undated)
      jq -n --arg scenario "$scenario" '
        {models: ["sol", "astra", "terra", "luna"] | map({slug: ("gpt-999-" + .), visibility: "list"})}
        | if $scenario == "stale" then .fetched_at = "2000-01-01T00:00:00Z" else . end
      ' > "$catalog"
      ;;
  esac
  for family in sol astra terra luna; do
    listed=$(jq -er --arg family "$family" '
      [.models[] | select(.visibility == "list" and (.slug | test("^gpt-[0-9.]+-" + $family + "$"))) | .slug] | join("\n")
    ' "$bundled") || fail "$version emitted an unreadable model catalog"
    [ -n "$listed" ] || continue
    newer=$(CODEX_HOME="$catalog_home" bash "$TESTS_DIR/../bin/fm-model-freshness.sh" codex "gpt-0-$family" 2> "$catalog_home/notice")
    grep -Fxq -- "$newer" <<<"$listed" \
      || fail "$version did not resolve a bundled $family model with a $scenario cache"
    if [ "$scenario" = fresh ]; then
      [ ! -s "$catalog_home/notice" ] || fail "$version reported uncertainty for a fresh cache"
      checked=$((checked + 1))
    else
      grep -q 'cache age is' "$catalog_home/notice" || fail "$version omitted $scenario cache age uncertainty for $family"
      [ "$(wc -l < "$catalog_home/notice")" -eq 1 ] || fail "$version emitted more than one $scenario uncertainty line"
    fi
  done
done
[ "$checked" -gt 0 ] || fail "$version listed no supported model families in its bundled catalog"
pass "$version bundled catalog resolved $checked model families with fresh, stale, and undated caches"
