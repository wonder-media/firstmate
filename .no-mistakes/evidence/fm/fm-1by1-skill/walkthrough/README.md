# 1by1 synthetic walkthroughs (test phase evidence)

Method: the committed `.agents/skills/1by1/SKILL.md` text plus one synthetic fixture (`inventory.md`: 9 rows across root/mf/main homes with a root/home duplicate, an archived hold, a resolved decision, ordinary running work, a do-not-resurface item, and an answer already queued) were fed to `claude -p --restricted --tools "" --no-session-persistence --model sonnet`. No live records, Bridge, or lifecycle state were touched.

| Scenario | Prompt | Response | Observed |
| --- | --- | --- | --- |
| A `$1by1` (no selector) | A-no-selector.prompt.md | A-no-selector.response.md | Exactly one card (WOK wok-release/timing). Root projection and mf owner row deduplicated to one item. Archived, resolved, running, do-not-resurface, and already-answered rows excluded. Four controls offered, free-text invited, task-wide Hold/Discard scope explained via lifecycle_task_id, no auto-submission, no full inventory dump. |
| B `$1by1 wok` | B-wok.prompt.md | B-wok.response.md | Only the WOK item presented; MF review request and CES prerequisite excluded. |
| C `$1by1 unknown-brand` | C-unknown.prompt.md | C-unknown.response.md | Clarification only, no card, no fallback to whole fleet or substring guess. |
| D stale answer | D-stale-answer.prompt.md | D-stale-answer.response.md | Captain's revision-7 answer not applied to revision 8; change explained, fresh answer requested on the same item. |

Automated checks run in the worktree: `bin/fm-doc-audience-check.sh` (ok, 78 surfaces, 299 local links), `tests/fm-documentation-audiences.test.sh` (all ok), Ruby YAML parse of the skill frontmatter (name=1by1, user-invocable=true, metadata.internal=true), every relative link in SKILL.md resolves, and the Bridge/snapshot/auth interfaces the skill names exist with the described semantics (LIFECYCLE_ACTIONS hold/discard/resume, lifecycle_task_id, repo_tags, fmx_auth_header_file with umask 077).
