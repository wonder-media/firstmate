---
name: council
description: >-
  Run a bounded multi-model review of an implementation plan when the captain invokes /council or asks for a council review.
  On request only; never run on simple tasks.
user-invocable: true
metadata:
  internal: true
---

# Council

## Triggers and boundaries

Invoke as `/council <plan-path> [--seats a,b,c] [--max-rounds N]`.
This captain-invocable skill runs only on request, never unasked and never on a simple task.
Firstmate may suggest it once at plan intake when a plan has more than two phases, adds a daemon, service, schema, or subsystem, or changes a captain-facing surface.
The council refines; the captain approves.
An invocation authorizes review, not implementation, a merge, or an expansion of scope.
A finding that expands scope, is destructive, irreversible, or security-sensitive, or contradicts a captain rule becomes a captain question registered through the decision-hold path, never a council decision.
Load [ask-user-authority](../ask-user-authority/SKILL.md) when classifying such a finding and [decision-hold-lifecycle](../decision-hold-lifecycle/SKILL.md) for registration and completion.
Reviewer labels are evidence, never authority.
No reviewer ever edits the plan.

## Roles and selection

Name one planner: firstmate for firstmate-repo plans, the owning secondmate otherwise.
A worker may author a project plan; that home's planner still merges and is the only author of the next version.
The planner writes a disposition with a reason for every finding, including nice items.
Counted seats are independent reviewers on different models, each in its own scout copy and a fresh context every round.
The default counted roster is architect, empiricist, economist; UX joins when the plan changes a captain-facing surface and may be selected explicitly.
The advisory seat is extra, not counted, in round 1 only unless the captain asks for it later.

Read captain-private `config/council.json` using the [Council configuration schema](../../../docs/configuration.md#council-configcounciljson) and [example roster](../../../bin/council/council.example.json).
Seat names map to dispatch rule names; `config/crew-dispatch.json` remains the single model-routing authority.
Resolve selection at every intake through the normal captain override, matching rule, default, and static harness precedence.
Load [harness-adapters](../harness-adapters/SKILL.md) before dispatch; for a matched profile array load [quota-array-dispatch](../quota-array-dispatch/SKILL.md) and consult current `quota-axi` output.
Pass the resolved concrete profile through the ordinary spawn path; never use an unverified harness for a counted seat.
Missing or malformed roster/rule configuration is reported for correction, not silently replaced with guessed models.
`--seats` selects a comma-separated roster from architect, empiricist, economist, ux, advisory; retain at least three distinct counted seats.
`--max-rounds N` may lower the configured cap, never raise the three-round hard cap; require an integer from 1 through 3.
Reviews are capped at 2000 words, or 1000 for the economist, with mandatory evidence citations.

## Finding-state model

Every atomic finding has a stable id from the round that first raised it, an original tag, and an effective tag.
The planner may lower an advisory-only must to should; it never raises a tag.
Existing findings keep their original severity in later rounds even when they concern untouched text; the changed-text-only rule applies to new ids.

| State | Meaning |
|---|---|
| open | Raised, no disposition yet; an acceptance awaiting application remains outstanding here |
| accepted-applied | Planner changed the plan and recorded the applied anchor; closed unless a later version undoes the change, which reopens the same id with a reason |
| rejected | Closed by the planner's documented judgment; the originating seat sees the rejection in its own rows if another round runs and may reassert it once |
| contested | A reasserted rejection, still closed; preserve both positions and list every contested must by id in delivery |
| deferred | Outstanding with an owner and destination, such as a follow-up item or later phase; a deferred must stays outstanding until the captain removes the requirement |
| captain-question | Registered as a decision hold with its key; outstanding until answered |

**Outstanding must** = a must whose state is open, deferred, or captain-question, or an accepted must not yet applied.
Rejected and accepted-applied are closed; a contested rejection is still closed.
Use effective tags for the outstanding-must calculation while retaining the original evidence.
Reviewer agreement is never a veto.
There is no rebuttal step; finding identity and the contested state carry a rejected must forward at no cost.

## Procedure

### 1. Prepare

Keep council records under the plan's task directory, never in the target project.
Freeze `plan-v1.md` with `## Non-negotiables` and `## Open choices` and record its full sha256 in `council/log.md`.
Record the named planner, selected roster, round cap, and input paths before dispatch.
Initialize the records from the [findings template](../../../bin/council/findings.template.md) and [log template](../../../bin/council/log.template.md).
Frozen versions are immutable; revisions produce the next numbered version.
Keep the review input free of peer reviews or findings, including embedded review summaries and linked paths that a seat would follow.

### 2. Round n: blind, parallel

Use [bin/fm-brief.sh](../../../bin/fm-brief.sh) `--scout` to scaffold one brief per counted seat.
Paste the common clauses and matching round variant from [rubric.md](../../../bin/council/rubric.md), plus exactly one role template, into its task section:

- [Architect](../../../bin/council/roles/architect.md)
- [Empiricist](../../../bin/council/roles/empiricist.md)
- [Economist](../../../bin/council/roles/economist.md)
- [UX](../../../bin/council/roles/ux.md)

Fill the plan path, round, copied captain non-negotiables, seat name, and evidence inputs before spawning with [bin/fm-spawn.sh](../../../bin/fm-spawn.sh) `--scout`.
Every counted seat receives the same frozen plan version by path, the non-negotiables, its role rubric, and repo read access from its own scout copy.
For round 2+, also supply only that seat's own prior rows with dispositions and the change set: a unified diff when smaller than the plan, otherwise a list of changed sections.
Review scope is the change set and regressions; the full plan is reference only.
Remove peer attributions and cross-references from the seat's disposition excerpt without losing its own issue or the planner's reason.
Never send the shared findings table, another seat's report, or advisory findings to a counted seat.
New ids in round 2+ are admissible as must only on changed text or as a regression of an accepted change; new findings on untouched text are should or nice.

Dispatch the seats in parallel and record each attempt's spawn time and 15-minute deadline.
At minute 5, check a seat that has no status line using ordinary current-state supervision; a quiet seat is not by itself proof of failure.
Use [bin/fm-send.sh](../../../bin/fm-send.sh) for necessary steering under its normal home and identity contract, preserving blindness.
A seat that misses its deadline, returns a malformed report, or sees another seat's findings is invalid and is replaced once against exactly the same input, with the same 15-minute deadline in a fresh isolated copy.
One replacement total per seat per round covers all invalidity causes; it does not add a round.
Validate report sections, citations, word cap, and round-specific admissibility before counting a report.
Record failures and replacement links even when no report exists.
After that replacement fails, proceed to collection and the incomplete check rather than retrying indefinitely.
Keep the home's existing supervision wake path active while seats and any advisory process run.

### 3. Collect

Reports stay at `data/<seat-task>/report.md`; copy valid reports verbatim into `council/v<n>/<seat>.md`.
Keep failed or replaced output under `council/v<n>/<seat>.attempt<k>.md`, never overwriting an earlier attempt.
Capture task metadata and original report file times before cleanup; an archive's copy time is not the report completion time.
Write each attempt's spawn time, report time, duration, words, actual model, effort, repo commit, task id, validity/reason, and replacement link into the log before any scout cleanup.
Each scout completes its decision inventory through [bin/fm-decision-hold.sh](../../../bin/fm-decision-hold.sh) `complete`, with keys or `--none` as appropriate.
Preserve originating hold keys when archiving and merging; do not duplicate a hold for a repeated finding.
Only after the archive and log row exist and the completion gate passes use [bin/fm-teardown.sh](../../../bin/fm-teardown.sh) normally.
An attempt that never wrote a report cannot be cleaned up by force: preserve its state and route through [stuck-crewmate-recovery](../stuck-crewmate-recovery/SKILL.md), with its replacement in a separate copy.

### 4. Merge

Build `council/v<n>/findings.md` from the full inventory of every report, not only the top eight or six.
Use one row per atomic finding, reusing ids for repeated issues and retaining all source anchors when multiple seats independently identify the same issue.
Carry prior findings forward so every round's dispositions and outstanding items remain visible.
Write one disposition and reason per finding, including should and nice items.
Register captain questions through the decision-hold path and record their keys before treating the review as complete.
Write `plan-v<n+1>.md` with an applied anchor for every accepted item, and record its sha256 and file time.
Keep post-review edits limited to dispositioned applications and editorial changes; unrelated revisions require their own review.
Check that previously applied fixes still hold; reopen the original id with a reason if a later version undoes one.
Reconcile conflicting repository observations against the logged seat commits and evidence instead of treating differing copies as identical.

### 5. Evaluate: numbered stop checklist

Evaluate in this order after completing the inventory and merge:

1. **incomplete** if fewer than three valid counted reports this round after the one replacement.
   Deliver the inventory anyway, even at the round cap and even if no must is outstanding.
2. **converged** if every finding from every round has a disposition, no must is outstanding, and this round accepted no must on changed text, so the delivered version is the reviewed version apart from editorial edits and should/nice applications.
3. **converged-with-applied-deltas** if every finding has a disposition, no must is outstanding, and the only difference between the reviewed and delivered versions is the planner's application of this round's accepted items.
   List those post-review changes by finding id; the captain approves them instead of a fourth reviewer.
   The planner may instead choose one more round when a delta is large or contested, provided the cap permits it.
4. **next round** on the new version otherwise, while below the selected cap.
   Apply step 2's change-set and new-id rule without demoting existing findings.
5. **capped-unresolved** at the selected cap, at most three rounds, with a must still outstanding.
   Deliver the last version plus every unresolved and contested item with both positions.

Log value density per round: accepted must+should per minute of file-backed round wall time.
It is the captain's diminishing-returns signal, not a gate.
Do not double-count a repeated id or an already-applied item as newly accepted value.

### 6. Deliver

Deliver the final version, all findings tables, and `council/log.md` next to the plan.
Use the delivery format below and complete the planner's decision inventory under the shared decision-hold lifecycle before declaring the review complete.
Neither convergence nor exhaustion grants implementation or merge approval.

## Records layout and fields

The following are generated paths under the plan's task directory, not tracked dependencies:

```text
plan-v1.md ... plan-vN.md
council/log.md
council/v<n>/<seat>.md
council/v<n>/<seat>.attempt<k>.md
council/v<n>/findings.md
```

The findings row carries `id`, `seat`, `tag (original / effective)`, source anchor, one-line summary, `state`, `reason`, applied anchor or deferred owner and destination, and hold key for captain questions.
The log names the planner and records every version's sha256.
Each seat-attempt row carries task id, model, effort, repo commit, spawn time, report time, duration, words, validity, and replacement link, bound to its round and reviewed version/hash.
Each round row records file-backed wall (spawn to next version), merge time (last report to next version), accepted and rejected counts, and value density.
Log the terminal outcome and post-review delta list.
The linked record templates provide fillable columns; write unknown measurements as unknown with a reason instead of inventing numbers.
Phase 1 is script-free: fill briefs and Markdown records using the existing tools and file-backed evidence.
Reconsider automation only after this procedure has run twice without edits.

## Advisory-seat contract

Use [advisory.md](../../../bin/council/roles/advisory.md) with the applicable common rubric; it is a second economist or generalist opinion from a model without a verified harness.
Firstmate runs the direct CLI in print mode in the background, from a scratchpad directory, never a home or project.
Use the pinned model and command template in the roster, with `--print-timeout 15m`; do not rely on the CLI's shorter default.
Add no repo directory.
The prompt contains everything the seat needs and explicitly states no tools and no filesystem are available, and asks it to answer directly in Markdown.
Embed the plan and any allowed change set and own prior rows; filesystem paths are not usable advisory inputs.
Use the existing [process-event-sources](../process-event-sources/SKILL.md) procedure for a durable background completion wake.
Validate the rubric's sections and limits before archiving, and label the attempt advisory in the log.
Advisory reports never count toward the three valid counted seats.
Never forward their findings to counted seats; an advisory-only must is recorded as original must / effective should unless an independent counted finding covers the same point.
Keep the same finding identity when independently corroborated and preserve each source's original tag rather than promoting an advisory label.
These operating restrictions do not claim an operating-system sandbox or a verified fleet harness.
Harness verification is separate follow-up work; only once verified does this seat become a counted scout through the normal path.

## Captain delivery format

- Final plan path and links to every round's findings and the log.
- Per-round summary of what changed, with valid counted coverage and measured wall time/value density.
- Rejected items by id with the planner's reasons, including musts rejected in the final round.
- Terminal outcome using the exact checklist label and its basis.
- Post-review deltas by finding id, with applied anchors for captain approval.
- Contested musts by id with both the seat's position and the planner's reason; say none when empty.
- Every unresolved item and captain question, preserving the decision key in durable records and presenting the concrete choice in captain-facing language.

## Tabletop verification traces

### Seat never reports

Three counted seats start round 1; the empiricist has no status at minute 5, so the planner checks it.
It misses minute 15; the planner logs invalidity and starts its one replacement against the same frozen input.
The replacement also misses its 15-minute deadline; both missing-report attempts retain their state for ordinary recovery, without forced teardown.
Archive the other two reports, log every attempt, merge their full inventory, and evaluate checklist item 1: **incomplete**.
Deliver the inventory even if its musts are all closed.

### Round cap

Three valid counted reports arrive in each round, but an open must R1-A1 survives rounds 1 and 2 and still has no applied resolution in round 3.
It keeps its id and severity even though its text is unchanged.
Items 2 and 3 fail on the outstanding must; item 4 cannot start round 4.
Item 5 yields **capped-unresolved** with the last plan, the complete inventory, and every unresolved and contested item with both positions.

### Planner rejects every must

Three valid reports arrive; the planner rejects every must with a documented reason and dispositions every should and nice.
With no substantive changes and no outstanding must, item 2 yields **converged**, even if reviewers disagree.
No extra rebuttal or round is required to obtain agreement.
If this happens in a later round after a seat has reasserted a previous rejection once, that id is contested but closed and appears in the delivery's contested-must list.
For a first-round reject-all result the contested list is empty, while all rejected items and reasons are still delivered.

### Deferred must

Round 1 defers R1-E1 to a later phase with an owner and destination.
That disposition does not remove the requirement: R1-E1 stays an outstanding must in later rounds, even on untouched text.
Convergence fails until it is applied, rejected with a reason, or the captain removes the requirement through the recorded decision path.
If it remains deferred at the cap, deliver **capped-unresolved** with its owner, destination, and unresolved requirement.
