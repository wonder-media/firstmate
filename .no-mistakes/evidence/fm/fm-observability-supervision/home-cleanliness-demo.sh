#!/usr/bin/env bash
# Evidence driver: what a captain's own `git status` shows in a secondmate home
# after firstmate wires that incarnation's lifecycle, in BOTH home shapes.
# Uses the SHIPPED tracked .gitignore and the shipped dirty_status helper.
# core.excludesFile=/dev/null so only the tracked rule can make it clean.
set -u
REPO=${1:?repo root}
. "$REPO/bin/fm-ff-lib.sh"
W=$(mktemp -d -t fm-homes)
git init -q -b main "$W/main"
cp "$REPO/.gitignore" "$W/main/.gitignore"
mkdir -p "$W/main/.claude" "$W/main/.opencode/plugins"
printf '{}\n' > "$W/main/.claude/settings.json"          # captain's tracked config
printf 'v1\n' > "$W/main/AGENTS.md"
git -C "$W/main" add -A && git -C "$W/main" commit -qm "captain repo" >/dev/null
git -C "$W/main" worktree add -q --detach "$W/linked" HEAD
git clone -q "$W/main" "$W/clone" && git -C "$W/clone" checkout -q --detach

for shape in linked clone; do
  h=$W/$shape
  mkdir -p "$h/.claude" "$h/.opencode/plugins"
  printf 'sm\n'          > "$h/.fm-secondmate-home"
  printf '{"hooks":{}}\n'> "$h/.claude/settings.local.json"
  printf '// fm\n'       > "$h/.opencode/plugins/fm-busy-state.js"
  printf '// fm\n'       > "$h/.opencode/plugins/fm-turn-end.js"
  printf 'g\n'           > "$h/.fm-grok-turnend"
  printf 'k\n'           > "$h/.fm-kimi-turnend"
  echo "=== $shape home, fully wired by firstmate ==="
  echo "\$ git status --short"
  git -C "$h" -c core.excludesFile=/dev/null status --short | sed 's/^/  /'
  echo "  (no output above = clean)"
  echo "\$ git check-ignore -v .claude/settings.local.json .fm-grok-turnend"
  git -C "$h" -c core.excludesFile=/dev/null check-ignore -v \
    .claude/settings.local.json .fm-grok-turnend | sed "s|$W|<tmp>|g;s/^/  /"
  echo "firstmate dirty_status verdict: '$(dirty_status "$h" yes)'  (empty = safe to sync)"
  echo
done

echo "=== a real captain edit is still dirty ==="
printf 'captain edit\n' >> "$W/clone/AGENTS.md"
echo "\$ git status --short"
git -C "$W/clone" -c core.excludesFile=/dev/null status --short | sed 's/^/  /'
echo "firstmate dirty_status verdict: '$(dirty_status "$W/clone" yes)'  (non-empty = sync refused)"
rm -rf "$W"
