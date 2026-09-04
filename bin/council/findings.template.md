# Council round {n} findings and dispositions

Copy this template to the plan task's `council/v<n>/findings.md` and replace placeholders.
The [council skill](../../.agents/skills/council/SKILL.md#finding-state-model) owns finding identity, severity, state, and disposition semantics.

Planner: {name and home}.
Reviewed input: {version and full sha256}; delivered version: {version and full sha256}.
Counted seats: {valid seats}; advisory: {seat or none}; invalid attempts: {attempt ids or none}.

| id | seat | tag (original / effective) | source anchor | one-line summary | state | reason | applied anchor | deferred owner and destination | hold key |
|---|---|---|---|---|---|---|---|---|---|
| {stable id} | {originating seat(s)} | {original / effective} | {archived report:anchor} | {atomic finding} | {state} | {disposition or reopening reason; both positions if contested} | {plan version:anchor or -} | {owner; follow-up or later phase, or -} | {origin and decision key, or -} |

Carry prior findings forward and retain all source anchors for equivalent findings under the same id.
Record every finding, including nice items outside each report's top-changes list.

Tally by effective tag: {must}, {should}, {nice}.
Newly accepted-applied: {ids}; rejected: {ids}; contested musts: {ids}; outstanding musts: {ids}.
Captain questions: {ids and keys or none}.
Post-review deltas: {ids and applied anchors or none}.
