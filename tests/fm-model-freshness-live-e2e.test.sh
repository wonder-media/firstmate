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

catalog_current=0
jq -e '.fetched_at | strings | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | now - . | . >= 0 and . <= 604800' "$catalog" >/dev/null 2>&1 && catalog_current=1
checked=0
for family in sol astra terra luna; do
  listed=$(jq -er --arg family "$family" '
    [.models[] | select(.visibility == "list" and (.slug | test("^gpt-[0-9.]+-" + $family + "$"))) | .slug] | join("\n")
  ' "$catalog") || fail "$version emitted an unreadable model catalog"
  [ -n "$listed" ] || continue
  newer=$(CODEX_HOME="$catalog_home" bash "$TESTS_DIR/../bin/fm-model-freshness.sh" codex "gpt-0-$family" 2> "$catalog_home/notice")
  if [ "$catalog_current" = 1 ]; then
    grep -Fxq -- "$newer" <<<"$listed" \
      || fail "$version did not resolve a listed $family model from its bundled catalog"
  else
    [ -z "$newer" ] || fail "$version trusted an undated or stale bundled catalog"
    grep -q 'catalog age is' "$catalog_home/notice" || fail "$version omitted catalog age uncertainty"
  fi
  checked=$((checked + 1))
done
[ "$checked" -gt 0 ] || fail "$version listed no supported model families in its bundled catalog"
pass "$version bundled catalog checked $checked model families with freshness enforcement"
