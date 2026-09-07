#!/usr/bin/env bash
# Opt-in credentialed Codex regression proving the bounded foreground-checkpoint
# path. All Codex and Firstmate writable roots are pinned inside the throwaway
# worktree fixture so inherited fleet overrides cannot reach a live home.
set -u

if [ "${FM_CODEX_LIVE_E2E:-0}" != 1 ]; then
  echo "skip: set FM_CODEX_LIVE_E2E=1 to run the Codex continuity regression"
  exit 0
fi

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

command -v codex >/dev/null 2>&1 || fail "codex not found"

LAB="$ROOT/.codex-live-e2e.$$"
PROJECT="$LAB/project"
HOME_DIR="$LAB/fmhome"
CODEX_HOME_DIR="$LAB/codex-home"
TRANSCRIPT="$LAB/codex.jsonl"
CODEX_VERSION=$(codex --version)

cleanup() {
  rm -rf "$LAB"
}
trap cleanup EXIT

mkdir -p "$LAB"
git clone -q "$ROOT" "$PROJECT"
mkdir -p "$HOME_DIR/state" "$HOME_DIR/data" "$HOME_DIR/config" \
  "$HOME_DIR/projects" "$CODEX_HOME_DIR"
ln -s "$HOME/.codex/auth.json" "$CODEX_HOME_DIR/auth.json"
printf '[features]\nhooks = true\n' > "$CODEX_HOME_DIR/config.toml"

LAB_REAL=$(cd "$LAB" && pwd -P) || fail "could not resolve the isolated fixture root"
for candidate in "$PROJECT" "$HOME_DIR" "$HOME_DIR/state" "$HOME_DIR/data" \
  "$HOME_DIR/config" "$HOME_DIR/projects" "$CODEX_HOME_DIR"; do
  resolved=$(cd "$candidate" && pwd -P) || fail "could not resolve live-test path: $candidate"
  case "$resolved/" in
    "$LAB_REAL"/*) ;;
    *) fail "resolved live-test path escaped the isolated fixture: $candidate -> $resolved" ;;
  esac
done

# shellcheck disable=SC2016 # Backticks are literal prompt markup.
PROMPT='Run exactly `bin/fm-watch-checkpoint.sh --seconds 1` as one foreground shell call. Do not use a background task and do not run fm-watch-arm.sh. After the checkpoint returns, reply briefly.'

(
  cd "$PROJECT" || exit 1
  printf '%s\n' "$$" > "$HOME_DIR/state/.lock"
  env CODEX_HOME="$CODEX_HOME_DIR" FM_HOME="$HOME_DIR" \
    FM_ROOT_OVERRIDE="$PROJECT" FM_STATE_OVERRIDE="$HOME_DIR/state" \
    FM_DATA_OVERRIDE="$HOME_DIR/data" FM_CONFIG_OVERRIDE="$HOME_DIR/config" \
    FM_PROJECTS_OVERRIDE="$HOME_DIR/projects" \
    codex exec --dangerously-bypass-hook-trust \
      --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check \
      -c 'model_reasoning_effort="low"' --json "$PROMPT"
) > "$TRANSCRIPT" 2>&1 \
  || fail "Codex credentialed checkpoint turn failed: $(tail -20 "$TRANSCRIPT")"

grep -F 'checkpoint: no actionable wake within 1s' "$TRANSCRIPT" >/dev/null \
  || fail "Codex transcript omitted the real foreground checkpoint result"
if grep -F 'watcher: started pid=' "$TRANSCRIPT" >/dev/null; then
  fail "Codex switched to the background arm path"
fi

printf 'ok - %s live E2E preserved the one-second foreground checkpoint path with isolated writable roots\n' "$CODEX_VERSION"
