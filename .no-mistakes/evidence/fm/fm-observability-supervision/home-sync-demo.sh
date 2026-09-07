#!/usr/bin/env bash
# Operator-view demo: a secondmate home carrying firstmate's own lifecycle
# wiring still fast-forwards; a real captain edit still blocks the sync.
set -u
ROOT=${FM_DEMO_ROOT:?}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-sync-demo.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=fmdemo GIT_AUTHOR_EMAIL=fmdemo@example.invalid
export GIT_COMMITTER_NAME=fmdemo GIT_COMMITTER_EMAIL=fmdemo@example.invalid

R="$TMP/code-root"; mkdir -p "$R"
git init -q -b main "$R"
printf 'projects/\nstate/\ndata/\n.no-mistakes/\n' > "$R/.gitignore"
printf 'instructions v1\n' > "$R/AGENTS.md"
printf 'r1\n' > "$R/README.md"
mkdir -p "$R/bin" "$R/.agents/skills" "$R/.claude" "$R/.opencode/plugins"
printf 'echo a\n' > "$R/bin/tool.sh"
printf 's1\n' > "$R/.agents/skills/note.md"
printf '{}\n' > "$R/.claude/settings.json"
printf '// primary\n' > "$R/.opencode/plugins/fm-primary.js"
git -C "$R" add -A; git -C "$R" commit -qm v1
HOME_DIR="$TMP/remote-home"
git -C "$R" worktree add -q --detach "$HOME_DIR" HEAD
printf 'ios\n' > "$HOME_DIR/.fm-secondmate-home"
printf 'instructions v2\n' > "$R/AGENTS.md"; git -C "$R" add -A; git -C "$R" commit -qm v2

mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/.opencode/plugins"
printf '{"hooks":{"Stop":[]}}\n' > "$HOME_DIR/.claude/settings.local.json"
printf '// firstmate lifecycle plugin\n' > "$HOME_DIR/.opencode/plugins/fm-busy-state.js"

echo "=== The home, as git sees it ==========================================="
git -C "$HOME_DIR" status --porcelain | sed 's/^/  /'
echo
echo "=== 1. firstmate's own wiring must not strand the home ================="
echo '$ bin/fm-remote-secondmate-control.sh sync ios'
FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$R" "$ROOT/bin/fm-remote-secondmate-control.sh" sync ios 2>&1 | sed 's/^/  /'
echo "  exit: $?"
echo "  home HEAD == code root HEAD: $([ "$(git -C "$HOME_DIR" rev-parse HEAD)" = "$(git -C "$R" rev-parse HEAD)" ] && echo yes || echo NO)"
echo "  AGENTS.md now reads: $(cat "$HOME_DIR/AGENTS.md")"
echo "  firstmate settings still present: $([ -f "$HOME_DIR/.claude/settings.local.json" ] && echo yes || echo NO)"
echo
echo "=== 2. A real captain edit must still block the sync ==================="
printf 'captain was editing this\n' >> "$HOME_DIR/AGENTS.md"
printf 'instructions v3\n' > "$R/AGENTS.md"; git -C "$R" add -A; git -C "$R" commit -qm v3
echo '$ bin/fm-remote-secondmate-control.sh sync ios'
FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$R" "$ROOT/bin/fm-remote-secondmate-control.sh" sync ios 2>&1 | sed 's/^/  /'
echo "  exit: ${PIPESTATUS[0]:-?} (non-zero = refused)"
echo "  captain's edit preserved: $(tail -1 "$HOME_DIR/AGENTS.md")"
echo
echo "=== end ================================================================"
