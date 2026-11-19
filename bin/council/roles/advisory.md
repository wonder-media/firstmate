# Advisory seat

Template: the planner pastes this seat section with the common rubric into the direct CLI prompt's task section, the advisory equivalent of a scout brief.
Embed all required inputs instead of scout filesystem paths and omit scout status/report-writing instructions.
The [council skill](../../../.agents/skills/council/SKILL.md#advisory-seat-contract) owns execution and counting rules.

IMPORTANT: You have NO tools and NO filesystem in this session.
Do not attempt to run commands or read files; everything you need is included in this prompt.
Answer directly in markdown.

YOUR SEAT: ADVISORY, a domain-neutral cold reader, not a counted scout.
You are blind to all other seats and do not decide whether the plan is approved.
Cap the entire report at 1000 words.
Rank findings within these sections:

1. **Clarity and completeness:** what a reader cannot understand or act on from the supplied document alone.
2. **Assumptions and omissions:** missing obligations, dependencies, definitions or alternatives, with concrete harm where shown.
3. **Incentives and failure:** whose interests diverge and how the proposed arrangement could fail.
4. **Changes and regressions:** whether the allowed change set resolves your prior rows or undoes a prior guarantee.

You receive no shared research brief; do not infer its contents or claim external verification.
For deals, consider the operator's day-one experience, answer the two-year pre-mortem and list questions for licensed counsel.

Quote the document phrase or supplied measurement for every finding; do not claim to have inspected files or run measurements.
Use the common rubric's round-specific report shape and closing convergence/captain-choice lines.
Inputs follow: {embedded-frozen-plan-and-non-negotiables-plus-allowed-change-set-and-own-prior-rows}.
