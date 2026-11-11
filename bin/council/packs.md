# Council domain packs and intake

The [council skill](../../.agents/skills/council/SKILL.md) owns the review loop and finding states.
This file owns domain selection, packet handling, coverage, and lens assignment.
Use only `software`, `deal`, or `marketing`; add another pack only after two concrete requests need it.

## Intake and compatibility

Select `--pack software|deal|marketing` and optionally `--research none|light|deep` at intake and log both.
Without these flags, use `software` and that pack's research default.
Existing software `seats`, `default_roster`, and caps retain their meanings; new fields are additive.
For an older roster, use the [example](council.example.json) as a proposed migration, never silently add dispatch rules or choose models.
If research is requested but its configuration is absent, request configuration before making paid calls.
The minimum family coverage below applies even to an older roster.
In packet reviews, the packet/proposal inputs and output rules below replace single-plan freeze, revision and change-set instructions in the skill; all safety and finding-state semantics remain shared.

For software, use the five existing role files and [software rubric](rubric.md), plus the [common supplement](review-supplement.md).
For deal and marketing, use [rubric-neutral.md](rubric-neutral.md) and the role files assigned by `packs.<pack>.seats.<seat>.lenses`.
A lens is a role file, a seat is one counted report: paste every assigned lens into that seat's instructions, never count lenses as separate reports.
Resolve `--seats` against the selected pack's seats, plus optional `advisory`; software uses the top-level mapping.
Each pack seat's `rule` names a dispatch rule, not a concrete profile.
Require every lens in `required_lenses` to have a counted owner; `cross_family_lenses` must each have at least two owners from different families.
Pair lenses to keep the selected report count bounded; the example shows four counted seats covering six lenses.
No advisory-only lens satisfies counted coverage.

## Lens files

| Purpose | Deal | Marketing |
|---|---|---|
| Structure | [Structure and governance](roles/deal/structure.md) | [Strategy](roles/marketing/strategy.md) |
| Verify | [Fact-check and consistency](roles/deal/fact-check.md) | [Measurement](roles/marketing/measurement.md) |
| Money | [Money and tax](roles/deal/money.md) | [Channel economics](roles/marketing/economics.md) |
| Risk | [Risk and enforceability](roles/deal/risk.md) | [Claims and compliance](roles/marketing/claims.md) |
| People | [Operator and plain language](roles/deal/operator.md) | [Audience voice](roles/marketing/audience.md) |
| Other side | [Counterparty](roles/deal/counterparty.md) | [Competitor](roles/marketing/competitor.md) |

## Frozen document packets

Use [packet.template.md](packet.template.md) for deal reviews and any multi-document review.
Freeze `packet-v1.md` with a manifest containing each document's stable id, absolute path, full sha256, version/date, drafter and drafter's model family (or unknown with reason).
Include the captain's non-negotiables and open choices, document precedence if known, and the allowed evidence list.
Log the packet's own hash as well as every document hash; verify hashes before each dispatch.
Freeze immutable copies in the task directory if originals may change.
A changed original requires a newly numbered packet, never a silent edit to frozen evidence.
If an input is binary, supply a faithful readable extraction and log both hashes and any extraction limits.
Give every counted seat the identical packet, readable documents, current proposed changes, and frozen research brief when present.
Paths and excerpts must contain no peer findings or linked reviews.

For deal reviews, the next version is `proposed-changes-v<n+1>.md`, with finding ids, document/clause anchors, proposed wording or negotiation questions, and reasons.
Never edit a negotiated original or present proposed wording as agreed terms.
`accepted-applied` means applied to that proposal, not to the underlying agreement.
Later rounds review changes to the proposal and regressions against the frozen originals; record both hashes as the reviewed input.
For other document sets, select proposal-only output at intake when the documents belong to others.

## Family coverage and rotation

Resolve profiles using the existing dispatch and quota procedure, then check the complete resolved roster before spawning and again on valid reports each round.
Count actual model provider families, never CLI names: OpenAI, Anthropic, xAI and Google are distinct examples; two models from one provider are one family.
Record planner model/family and document drafter families, including unknowns with reasons.
Require at least three distinct counted seats and three provider families, with no family owning more than half of valid counted reports.
`caps.minimum_provider_families` may require more than three and `caps.max_family_share` may be stricter than 0.5, never weaker.
A seat may share the planner's family only when the captain explicitly names it for that run; log the authorization without inventing it.
A known document-author family cannot hold that document's counterparty lens; unknown authorship must be disclosed and verified before assigning that lens.
For software, assign architect and security to different provider families without changing either role.
Check the configured cross-family lenses too; missing lens ownership or family coverage makes stop-checklist item 1 `incomplete`, even with three reports.
Name missing families/lenses and unavailable profiles; do not silently concentrate, substitute a model, or count an advisory report to meet the rule.
If a full assignment cannot resolve, deliver the available inventory as incomplete or request a concrete roster correction through the normal decision path.

In round 2, rotate lens assignments to different provider families where the same coverage and author/planner exclusions permit; log any impossible rotation and its reason.
Keep stable logical seat ids and their original finding rows: a new family inherits only that seat's own sanitized rows and dispositions, never rows belonging to another seat.
A rotation reassigns lenses, not finding ownership; the new reviewer rechecks inherited rows as well as its assigned lenses within the ordinary change-set scope.
Do not add reports or another rebuttal step for rotation, and preserve the reassert-once and new-id severity rules.

## Caps and advisory promotion

Single software plans retain 2000 words (1000 for economist) and a 15-minute attempt deadline.
Document sets use `caps.document_set_review_words` within 2000-3000 and `caps.document_set_deadline_minutes` within 15-25, defaulting to 3000 and 25 in the example.
Apply the selected deadline to a replacement too; the quiet-seat check and one-replacement limit remain unchanged.
The advisory cap remains 1000 words.

The advisory reader receives embedded packet/plan and its own allowed history, without the research brief, coverage map, research answers, or peer findings.
It is a domain-neutral cold read; log disagreements with briefed seats as a possible anchoring signal.
A newer model pin does not prove harness verification.
To promote Gemini to a counted seat, first confirm the agy verification applies to the running host through [harness-adapters](../../.agents/skills/harness-adapters/SKILL.md), then add an explicit pack seat and dispatch rule using the verified profile and spawn it as an ordinary scout.
The counted seat receives the same frozen brief as all counted seats and obeys all coverage and exclusion rules; a separately selected advisory cold read remains uncounted.
Never relabel a direct CLI advisory response as counted.
