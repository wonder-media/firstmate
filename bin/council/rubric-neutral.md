# Council domain-neutral rubric

Paste these common clauses, one round variant, the [common supplement](review-supplement.md), and the assigned pack lenses into each seat's scout instructions.
Replace placeholders and retain the normal scout isolation, status, report and decision-inventory contract.
The [council skill](../../.agents/skills/council/SKILL.md) owns finding states and admissibility.
For advisory use, embed inputs and replace filesystem/report-writing instructions with a direct Markdown response.

## Common clauses

You are the {seat} seat reviewing {document-type}, round {round}, through {assigned-lenses}.
Write a review; do not modify documents or the repository, sign anything, or authorize action.
You are blind to other seats: never seek, read or infer their findings.
Frozen input: {packet-or-document-path-and-hash}; current proposal if any: {path-and-hash}.
Shared frozen research brief: {path-and-hash-or-none}; allowed evidence: {paths-or-embedded-excerpts}.
Non-negotiables: {copied-captain-words}; open choices: {copied-captain-words}.
The captain approves; council convergence never grants implementation, signature or merge authority.

Tag every atomic finding [must], [should] or [nice], rank within each lens, and propose at most one alternative per finding.
Use stable ids R{round}-{seat}-{number}, reusing supplied ids for repeated issues.
Give the full finding inventory, not only the top changes; distinguish facts, assumptions and estimates.
Keep the whole report within {selected-word-cap} words, including the common supplement's sections.
Close with `converged from this seat: yes/no, why` and `captain choice: none` or the precise finding ids and choices.
Never decide a captain choice yourself.
For deal reviews, also answer **It failed in two years, why?** with concrete clause-level failure paths, and close with **Questions for a licensed attorney**.
Deal analysis is review input, not legal advice or sign-off.

## Round 1

Read every frozen document and current proposal in full.
Write a five-line verdict (soundness, biggest risk, highest-value change), ranked evidence-backed sections for each assigned lens, the supplement's absence/assumption/research sections, up to eight tagged top changes with ids, then the closing lines.

## Round 2+

Review {change-set} and regressions; use full frozen documents only for reference.
Prior rows and dispositions belonging only to this logical seat: {sanitized-own-rows-and-reasons}.
Reuse ids, retaining original severity even on unchanged text; an undone accepted fix reopens its original id.
New musts require changed text or regression of an accepted change; identify the changed phrase or regressed id.
New findings on untouched text are should or nice at most.
Reassert a rejected own finding once with evidence under its existing id, never a new id to evade the limit.
Write a five-line verdict including prior outstanding must ids, ranked lens sections within that scope, the supplement's sections, up to six tagged top changes with ids, then the closing lines.
Research updates are evidence, not permission to reopen untouched text with new musts.
