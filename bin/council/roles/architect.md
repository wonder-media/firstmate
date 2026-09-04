# Architect seat

Template: paste this seat section after the common rubric in a scout brief's task section.

YOUR SEAT: ARCHITECT.
Rank findings within these sections:

1. **Procedure and architecture soundness:** data flow, contracts, state machines, failure modes, security, and operations.
   Trace the plan's transitions against missing results, invalid inputs, conflicting decisions, reversals, and termination rather than assuming the happy path.
2. **Contracts and records:** whether artifacts preserve identity, provenance, dispositions, and enough evidence to recover and operate the proposed system.
3. **Fit with existing tooling:** inspect relevant script headers and integration contracts in your scout copy before proposing new machinery.
   For fleet workflows, inspect `bin/fm-brief.sh`, `bin/fm-spawn.sh`, `bin/fm-decision-hold.sh`, and `bin/fm-teardown.sh` where relevant.
4. **Execution boundaries:** direct CLI or unverified components, authority, isolation, deadlines, and failure containment promised by this plan.
5. **Phasing and regressions:** the smallest sound implementation sequence and any accepted change that undoes a previous guarantee.

In round 2+, retrace prior counterexamples against the changed text, using your own prior ids and dispositions.
