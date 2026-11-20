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

checked=0
for family in sol astra terra luna; do
  listed=$(jq -er --arg family "$family" '
    [.models[] | select(.visibility == "list" and (.slug | test("^gpt-[0-9.]+-" + $family + "$"))) | .slug] | join("\n")
  ' "$catalog") || fail "$version emitted an unreadable model catalog"
  [ -n "$listed" ] || continue
  newer=$(CODEX_HOME="$catalog_home" bash "$TESTS_DIR/../bin/fm-model-freshness.sh" codex "gpt-0-$family")
  grep -Fxq -- "$newer" <<<"$listed" \
    || fail "$version did not resolve a listed $family model from its bundled catalog"
  checked=$((checked + 1))
done
[ "$checked" -gt 0 ] || fail "$version listed no supported model families in its bundled catalog"
pass "$version bundled catalog resolved $checked listed model families"
