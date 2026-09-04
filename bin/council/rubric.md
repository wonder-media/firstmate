# Council common rubric

Template: the planner pastes the common clauses and exactly one round variant below into a scout brief's task section, followed by one seat section from `roles/`.
Replace brace placeholders before dispatch; retain the scout scaffold's canonical report, status, isolation, and completion instructions.
For direct advisory use, the advisory role replaces filesystem/report-writing instructions with an embedded-input, Markdown-only response.
The [council skill](../../.agents/skills/council/SKILL.md) owns orchestration and finding-state semantics.

## Common clauses: paste every round

You are the {seat} seat on a review COUNCIL for an implementation plan, round {round}.
Your deliverable is a written review, not code; do not modify the repository or the plan.
You are BLIND to the other seats: do not look for, read, or guess their reviews or findings.
Review the same frozen version supplied to every seat: {plan-path}.
Captain non-negotiables, not to be relitigated: {paste-non-negotiables}.
Evidence inputs you may inspect from your scout copy: {allowed-evidence-paths-or-excerpts-without-peer-findings}.
The captain approves; the council never does.

Every finding must cite a plan phrase, a file:line, or a measurement with its method and result.
Use [must], [should], or [nice] on every atomic finding, including items outside the top-changes summary.
Rank findings most important first within each seat section and propose at most one alternative per finding.
Assign an id to each finding, reusing supplied ids for the same issue; propose new ids as R{round}-{seat}-{number}.
The top-changes list is a ranking, not a substitute for the full finding inventory in the seat sections.
No generic advice or flattery; distinguish measured evidence from assumptions and estimates.
Keep the entire report within 2000 words, or the stricter role cap.
Close with `converged from this seat: yes/no, why` and `captain choice: none` or the specific finding ids and choices requiring the captain.
Do not treat a seat verdict as approval or decide a captain choice yourself.

## Round 1 variant: paste for the initial review

Read the frozen plan in full and assess it through your seat's sections.
Use this report shape:

1. **Verdict in five lines:** is the plan sound, its single biggest risk, and the one change with the most leverage.
2. **Seat sections:** the sections in your role template, ranked and evidence-backed.
3. **Top 8 concrete changes:** up to eight one-liners, each with id and [must], [should], or [nice]; do not pad the list.
4. **Convergence and captain choice:** the closing lines from the common clauses.

## Round 2+ variant: paste for each later review

Read the supplied change set: {unified-diff-if-smaller-than-plan-otherwise-changed-sections}.
Use the frozen full plan by path for reference only; review scope is the change set and regressions introduced by accepted changes.
Your own prior finding rows and the planner's dispositions: {only-this-seats-rows-and-reasons}.
Reuse existing ids when the issue is the same, including a previously applied change that has been undone.
Existing findings retain their original severity even on untouched text.
For NEW ids, [must] is admissible only on changed text or as a regression of an accepted change; a new finding on untouched text is [should] or [nice] at most.
Identify the changed phrase or regressed accepted id when raising a new must.
A rejection of your own finding may be reasserted once under its existing id with evidence; do not create a new id to bypass that limit.
Use this report shape:

1. **Verdict in five lines:** is the change sound, which prior musts of yours remain open after disposition by id, and the highest-value change now.
2. **Seat sections:** ranked findings on changed text and regressions, with evidence and retained ids.
3. **Top 6 concrete changes:** up to six tagged one-liners with ids; do not pad the list.
4. **Convergence and captain choice:** the closing lines from the common clauses.
