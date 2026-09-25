#!/usr/bin/env bash
# Structural regression tests for the tracked documentation audience inventory.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHECK="$ROOT/bin/fm-doc-audience-check.sh"
INVENTORY="$ROOT/docs/documentation-audiences.json"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-doc-audiences.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

run_expect_failure() {
  local expected=$1
  shift
  local out rc
  set +e
  out=$("$@" 2>&1)
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "expected failure containing '$expected'"
  assert_contains "$out" "$expected" "failure did not explain '$expected'"
}

mutate_inventory() {
  local source=$1 destination=$2 mode=$3
  python3 - "$source" "$destination" "$mode" <<'PY'
import json
import sys
from pathlib import Path

source, destination, mode = map(Path, sys.argv[1:])
data = json.loads(source.read_text(encoding="utf-8"))
if mode.name == "duplicate":
    data["surfaces"].append(dict(data["surfaces"][0]))
elif mode.name == "bad-setup-audience":
    for entry in data["surfaces"]:
        if entry["path"] == "docs/tmux-backend.md":
            entry["audience"] = "maintainer-verification"
            break
elif mode.name == "missing-owner-pointer":
    data["requiredOwnerPointers"][0] = {
        "source": "README.md",
        "target": "docs/sessionstart-nudge.md",
    }
elif mode.name == "shrink-scope":
    data["scope"]["trackedPatterns"] = ["README.md"]
else:
    raise SystemExit(f"unknown mode: {mode.name}")
destination.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
}

test_repository_inventory_passes() {
  local out
  out=$("$CHECK") || fail "repository documentation audience check failed"
  assert_contains "$out" "fm-doc-audience-check: ok surfaces=" \
    "audience check did not report exact surface coverage"
  assert_contains "$out" "local_links=" \
    "audience check did not report local-link validation"
  pass "documentation inventory classifies every maintained prose surface exactly once"
}

test_council_skill_metadata_and_references() {
  command -v ruby >/dev/null 2>&1 \
    || fail "ruby is required to parse Council skill frontmatter as YAML"
  ruby -ryaml -e '
path = ARGV.fetch(0)
text = File.read(path)
frontmatter = text.match(/\A---\n(.*?)\n---\n/m)
raise "missing Council YAML frontmatter" unless frontmatter
metadata = YAML.safe_load(frontmatter[1])
raise "Council must be user-invocable" unless metadata.fetch("user-invocable") == true
raise "Council must be internal" unless metadata.fetch("metadata").fetch("internal") == true
links = text.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten
raise "Council has no resource references" if links.empty?
links.each do |link|
  target = File.expand_path(link.split("#", 2).first, File.dirname(path))
  raise "missing Council resource: #{link}" unless File.file?(target)
end
' "$ROOT/.agents/skills/council/SKILL.md" \
    || fail "Council frontmatter or a referenced resource is invalid"
  pass "Council frontmatter parses and every linked skill resource exists"
}

# The Council roster is a machine-consumed declarative artifact: the skill reads
# config/council.json (shaped by bin/council/council.example.json) and dispatches
# one scout per counted seat, pasting that seat's role template into the brief. A
# roster seat with no template, or a template the skill never links, leaves a
# counted seat undispatchable at intake. This resolves the roster the way the
# skill does and proves the resolver rejects an unresolvable seat.
resolve_council_roster() {
  python3 - "$ROOT" "$1" <<'PY'
import json
import re
import sys
from pathlib import Path

root, roster_path = Path(sys.argv[1]), Path(sys.argv[2])
roster = json.loads(roster_path.read_text(encoding="utf-8"))
skill = (root / ".agents/skills/council/SKILL.md").read_text(encoding="utf-8")
linked = {
    Path(m).stem
    for m in re.findall(r"\]\(([^)]*bin/council/roles/[^)#]+)\)", skill)
}

seats = roster["seats"]
counted = roster["default_roster"]
floor = roster["caps"]["minimum_counted_reports"]
problems = []

for seat in counted:
    if seat not in seats:
        problems.append("default roster seat %s has no seat definition" % seat)
for seat in seats:
    if not (root / "bin/council/roles" / ("%s.md" % seat)).is_file():
        problems.append("seat %s has no role template" % seat)
    elif seat not in linked:
        problems.append("seat %s role template is not linked from the council skill" % seat)
if len(counted) < floor:
    problems.append("default roster has %d counted seats, below the floor of %d" % (len(counted), floor))

if problems:
    sys.exit("council roster does not resolve: " + "; ".join(problems))

print("counted=" + ",".join(counted))
print("minimum_counted_reports=%d" % floor)
for seat in counted:
    print("brief=%s -> bin/council/roles/%s.md" % (seat, seat))
PY
}

test_council_roster_resolves_to_dispatchable_seats() {
  local resolved unknown
  resolved=$(resolve_council_roster "$ROOT/bin/council/council.example.json") \
    || fail "the example council roster does not resolve to dispatchable seats"
  assert_contains "$resolved" "brief=security -> bin/council/roles/security.md" \
    "security is not a counted default seat with its own linked role template"

  # Negative control: an unresolvable seat is reported, never silently dispatched.
  unknown="$TMP_ROOT/unknown-seat.json"
  python3 - "$ROOT/bin/council/council.example.json" "$unknown" <<'MUTATE'
import json
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
data = json.loads(source.read_text(encoding="utf-8"))
data["default_roster"] = [s if s != "security" else "netsec" for s in data["default_roster"]]
destination.write_text(json.dumps(data), encoding="utf-8")
MUTATE
  run_expect_failure "default roster seat netsec has no seat definition" \
    resolve_council_roster "$unknown"
  pass "every counted council seat resolves to a linked role template, and an unknown seat fails"
}

test_duplicate_and_setup_classification_fail() {
  local duplicate="$TMP_ROOT/duplicate.json"
  local bad_setup="$TMP_ROOT/bad-setup.json"
  local shrink_scope="$TMP_ROOT/shrink-scope.json"
  mutate_inventory "$INVENTORY" "$duplicate" duplicate
  mutate_inventory "$INVENTORY" "$bad_setup" bad-setup-audience
  mutate_inventory "$INVENTORY" "$shrink_scope" shrink-scope
  run_expect_failure "surfaces classified more than once" \
    "$CHECK" --inventory "$duplicate"
  run_expect_failure "README setup target docs/tmux-backend.md has disallowed audience" \
    "$CHECK" --inventory "$bad_setup"
  run_expect_failure "scope.trackedPatterns must match the fixed maintained-prose scope" \
    "$CHECK" --inventory "$shrink_scope"
  pass "classification, setup routing, and maintained-prose scope fail safely"
}

test_required_pointer_fails() {
  local missing_pointer="$TMP_ROOT/missing-pointer.json"
  mutate_inventory "$INVENTORY" "$missing_pointer" missing-owner-pointer
  run_expect_failure "required owner pointer missing" \
    "$CHECK" --inventory "$missing_pointer"
  pass "required documentation owner pointers cannot silently disappear"
}

write_fixture_inventory() {
  local repo=$1
  cat > "$repo/docs/documentation-audiences.json" <<'JSON'
{
  "version": 1,
  "scope": {"trackedPatterns": ["*.md", "*.mdx", "*.rst", "*.txt", "docs/examples/*"]},
  "allowedAudiences": ["public-product", "operator-current", "maintainer-verification"],
  "setupAudiences": ["public-product", "operator-current"],
  "readmeSetupTargets": ["docs/setup.md"],
  "requiredOwnerPointers": [
    {"source": "README.md", "target": "docs/policy.md"}
  ],
  "surfaces": [
    {"path": "README.md", "audience": "public-product"},
    {"path": "docs/evidence.md", "audience": "maintainer-verification"},
    {"path": "docs/policy.md", "audience": "operator-current"},
    {"path": "docs/setup.md", "audience": "operator-current"}
  ]
}
JSON
}

test_local_links_and_no_keyword_heuristic() {
  local repo="$TMP_ROOT/fixture"
  mkdir -p "$repo/docs"
  git -C "$repo" init -q
  printf '%s\n' '[Setup](docs/setup.md) [Policy](docs/policy.md)' > "$repo/README.md"
  printf '%s\n' '# Setup' > "$repo/docs/setup.md"
  printf '%s\n' '# Policy' > "$repo/docs/policy.md"
  cat > "$repo/docs/evidence.md" <<'MD'
# Incident verification on 2026-07-23

```sh
/tmp/task-worktree/bin/tool --version
```

Observed version 1.2.3 on branch `fm/example`.
MD
  write_fixture_inventory "$repo"
  git -C "$repo" add README.md docs
  "$CHECK" --root "$repo" >/dev/null \
    || fail "structural checker rejected legitimate maintainer evidence prose"

  printf '%s\n' '[Setup](docs/setup.md) [Policy](docs/policy.md) [Broken](docs/missing.bin)' \
    > "$repo/README.md"
  git -C "$repo" add README.md
  run_expect_failure "unresolved local link" "$CHECK" --root "$repo"
  pass "local links resolve while dates, versions, commands, and incident prose remain semantically reviewed"
}

test_repository_inventory_passes
test_council_skill_metadata_and_references
test_council_roster_resolves_to_dispatchable_seats
test_duplicate_and_setup_classification_fail
test_required_pointer_fails
test_local_links_and_no_keyword_heuristic
