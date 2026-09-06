# 1by1 instruction skill validation

Date: 2026-09-05
Branch: fm/fm-1by1-skill
Worktree: /Volumes/2TB/Firstmate/treehouse/firstmate-59d3a9/3/firstmate
Scope: new internal user-invocable skill, one AGENTS trigger, documentation audience inventory entry.
No runtime scripts, Ahoy/Bearings behavior, live decisions, lifecycle records, emails, or browser sessions were changed.

## Method and owner inspection

Bounded manual synthetic walkthroughs, performed inline against the completed instructions; not independent agent evals or live integration tests.
The task explicitly excludes self-review subagents and live decision/lifecycle testing, so the global skill-creator's baseline/viewer loop was not run.
Inspected Ahoy and Bearings skills; canonical fleet and Bearings snapshot headers; decision-hold policy and command header; fm-send header; Bridge API/configuration header, lifecycle revision validation, state projection, and lifecycle routing; project registry owner pointer; documentation audience policy.
The implementation references existing owners instead of copying their schemas or creating a new queue.

## Walkthrough 1: mixed projects and duplicate records

Synthetic input to `$1by1`:

| Source | Owning identity | Project | Current evidence | Result |
| --- | --- | --- | --- | --- |
| Root projection | mf / wok-release / timing | WOK | Open, revision 7 | Same item as owner row |
| MF home | mf / wok-release / timing | WOK | Open, revision 7 | Keep once |
| MF home | mf / mf-review / approve | MF | Actual captain review request | Keep separately |
| Main home | main / access / login | CES | Human prerequisite | Keep separately |
| MF home | mf / old-proposal / choice | WOK | Bridge archived; underlying captain hold still open | Exclude |
| MF home | mf / finished / choice | WOK | Resolved decision | Exclude |
| Main home | main / running / none | FM | Ordinary worker progress; bare recorded PR | Exclude |
| MF home | mf / retired-idea / choice | WOK | Explicit do-not-resurface | Exclude |
| Main home | main / wok-release / timing | WOK | Distinct owner, no shared-origin evidence | Keep separately |
| MF home | mf / scout-decision-next / next | WOK | Origin scout completed; decision remains open | Keep decision |
| Bridge | mf / submitted / choice | WOK | Captain answer already queued for routing | Do not ask again |

Observed instruction walkthrough: select the urgent WOK release question once; do not enumerate the remaining inventory in chat.
The owner/home/key tuple prevents both duplicate root projections and accidental collapsing of unrelated same-named tasks.
An origin's completion is distinguished from completion of its feedback.

Synthetic first response:

> Captain, **Project: Wonderok**
>
> **Title:** Choose when to release
>
> **Description:** The release is ready, and we need your preferred timing.
>
> **What your choice changes:** Customers get the update now or after tomorrow's check; Hold and Discard apply to this release task and its other decisions.
>
> A. Release now - Customers receive the update sooner.
>
> B. Wait for tomorrow's check - Recommended because one more check lowers the risk.
>
> **Hold (archive for later)** | **Discard (close task)** | **Skip (leave open, continue this walk)** | **Stop**
>
> Reply with your choice or your own answer, and add any free-text notes.

Result: one card, two meaningful options, supported recommendation, four controls, free-text notes, no auto-submission.

## Walkthrough 2: project selector, missing data, and empty state

Synthetic registries map Wonderok repository aliases to WOK and unrelated Matthew Fraser work to MF; both are managed by the MF second mate.
`$1by1 wok` and `$1by1 WoK` select only the WOK rows above, excluding mf-review and CES access.
An exact repository selector preserves repository scope if its Bridge tag also groups other repositories.
`$1by1 unknown-brand` produces one clarification, no card, and no mutation.
An alias mapped inconsistently by current sources also requires clarification; it does not expand to MF or the full fleet.
With all selected feedback closed, output is: "Captain, no verified pending items remain for Wonderok."
With an inaccessible home, the same empty read retains a missing-coverage disclosure rather than claiming the inventory is complete.
A truncated decision or home surface calls for supported expansion/targeted owner reads; until covered, the result remains partial.
Result: selector isolation, clarification, and honest empty/partial-state behavior preserved.

## Walkthrough 3: stale answer and factual prerequisite

Present mf / wok-release / timing at revision 7; captain selects A with note "after the check"; refresh returns revision 8 with changed options.
Observed: no submission of A at revision 8; explain changed question and request a fresh answer on that item.
If refresh instead says the item is closed, do not reopen it or transfer A to the next question.
If the choice and notes contradict each other, clarify that same item rather than guessing.
Present a login prerequisite with factual Yes/No/Not sure alternatives and no verified fact.
Observed: recommend checking access rather than marking Yes as recommended.
Captain says "verify access": authorize an owner verification request while keeping the original prerequisite unresolved.
Only returned evidence or explicit factual confirmation can satisfy that prerequisite; delivery of the verification instruction alone cannot.
Result: identity/revision binding and authorization-versus-evidence distinction preserved.

## Walkthrough 4: lifecycle controls and durable continuation

- Hold: refresh the task's lifecycle revision, explain shared origin scope, and request Bridge hold; underlying captain/external/dated holds remain under Bridge's preservation policy.
  Queued is pending; advance as accepted only after the existing lifecycle result and owning record confirm it.
  Future default walks exclude the archived origin and its sibling decisions, without resolving their underlying captain holds.
- Discard: request Bridge discard for the displayed task scope; a mocked dependent-work decline rejection remains an unresolved failure on that same item.
  Do not mark done manually, remove a blocker, switch transports, delete source material, or claim success after partial routing.
- Skip: no authoritative write; select another eligible item from fresh state and remember only the skipped identity in this visible walk.
  If only skipped items remain, say so; a later invocation or context loss can recover them from source records.
- Stop: no new mutation and no next card; previously queued actions retain their real state.
- Accepted ordinary answer: use one owner route, preserve free-text notes, verify durable answer and any routed work, then briefly acknowledge and show only the next card.
- Lost context: refresh records, preserve a visible selector, and clarify a lost selector or missing answer binding instead of widening scope or replaying an answer.
- Bridge unavailable: disclose unavailable Hold/Discard, do not simulate lifecycle state with new local records.

Result: all requested control semantics and rejection boundaries are represented; none were exercised on live state.

## Automated checks and delivery boundary

- `no-mistakes doctor`: system/database/daemon and gate validation healthy; doctor did not request initialization.
- `/Users/patrick/firstmate/bin/fm-ensure-agents-md.sh .`: unchanged AGENTS.md and canonical CLAUDE.md pointer.
- `bin/fm-doc-audience-check.sh`: `fm-doc-audience-check: ok surfaces=78 local_links=298`.
  First invocation before staging reported the new skill as untracked; after staging the new file, the one applicable check completed successfully.
- `git diff --cached --check`: passed.
- Ruby standard-library YAML validation: `Skill frontmatter: valid name/description/user-invocable/internal metadata`.
  Python's environment lacks PyYAML; no dependency was installed.
  The global quick validator also excludes Firstmate's existing `user-invocable` extension, so metadata was validated with YAML parsing against this repo's required fields instead of changing that schema.
- Reviewed the complete staged diff: the new skill and AGENTS are agent-runtime; the JSON file remains the classification owner; current orchestration instructions stay in the skill and task-specific evidence stays here.
- Harness/backend behavior: no launch, rendering, vendor-signal classification, runtime code, or backend changes; live harness tests and broad runtime suites are not relevant to this instruction-only change.
- Closing reflection: no additional project-wide knowledge needs an AGENTS expansion; validator compatibility/dependency observations are retained here because edits outside the authorized worktree are out of scope.

Ready for Firstmate's independent no-mistakes instruction after commit; no PR push or merge performed by this task stage.
