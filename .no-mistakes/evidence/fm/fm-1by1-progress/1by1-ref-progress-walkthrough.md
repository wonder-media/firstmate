# 1by1 Ref/Progress — bounded synthetic walkthrough

Applies the updated `.agents/skills/1by1/SKILL.md` rules by hand against a synthetic
inventory, to check the new Ref/Progress instructions are internally consistent and
produce the behavior the intent requires. No live Bridge/decision state was touched.

Synthetic eligible inventory at walk start (3 items):

- `wok:receipt-cta/passes-vs-token` (Project Wonderok)
- `mf:booking-flow/timezone-default` (Project Matt Fraser)
- `csls:og-migration/db-password-rotate` (Project CSLS)

## 1. First presentation

> Captain, **Project: Wonderok | Ref: wok:receipt-cta/passes-vs-token | Progress: 1/3**

Position 1 assigned on first presentation of a distinct item. Total = 3 (all eligible, dedup'd).

## 2. Repeated question (captain asks for clarification on the same card)

> Captain, **Project: Wonderok | Ref: wok:receipt-cta/passes-vs-token | Progress: 1/3**

Same Ref, same position — a clarification/repeated card does not advance progress, per rule.

## 3. Skip

Captain replies "Skip". Next distinct item presented:

> Captain, **Project: Matt Fraser | Ref: mf:booking-flow/timezone-default | Progress: 2/3**

Skip made the item 1 identity available again for a later selection cycle but advanced the
walk to a new distinct item, so position 2 is assigned. wok:receipt-cta keeps its original
Ref/position in walk history if it resurfaces.

## 4. New eligible item arrives mid-walk

A fresh snapshot pull surfaces `csls:new-hotfix/rollback-window`. Total updates with a note:

> (Total updated to 4 — a new eligible item arrived: csls:new-hotfix/rollback-window.)

Next presentation (csls:og-migration, oldest remaining unanswered):

> Captain, **Project: CSLS | Ref: csls:og-migration/db-password-rotate | Progress: 3/4**

## 5. Referenced answer after reorder

Before answering item 3, urgency re-sorts the remaining inventory so
`csls:new-hotfix/rollback-window` now sorts ahead of `wok:receipt-cta/passes-vs-token`.
Captain then answers by name: "For wok:receipt-cta/passes-vs-token, go with option A."

Per "Apply the answer through its owner" step 1, the reference resolves to that exact
identity and its presented question/revision — not whichever item now occupies position 1
in the reordered inventory. The owner record and Bridge revision are refreshed and
re-verified before applying, exactly as for a non-referenced answer. Reorder did not
disturb the Ref-to-identity binding, and Ref stayed distinct from display position.

## 6. Item closes before being presented (unpresented, leaves scope)

`mf:booking-flow/timezone-default` (skipped earlier, never re-presented) is independently
resolved/archived outside the walk. Total decreases with a note:

> (Total updated to 3 — mf:booking-flow/timezone-default closed before being resurfaced.)

Its already-assigned position 2 remains valid walk history; it is simply not re-presented.

## 7. Partial inventory (one home unreachable)

If, at any presentation, one registered home's snapshot could not be freshly verified,
the total is expressed as `2 of at least 10 (partial)` (or `2/?` if no reliable total
exists at all) instead of asserting a false precise denominator.

## 8. Resumed conversation after context loss

A new conversation window opens with none of the above turns visible. Per the rule,
positions can only be recovered from visible conversational evidence; since none exists,
the walk states it is restarting the count from refreshed records and begins at 1:

> Captain, **Project: Wonderok | Ref: wok:receipt-cta/passes-vs-token | Progress: 1/3**
> (Note: walk position restarting from refreshed records — no prior count was visible in
> this conversation.)

Ref is unchanged (still derived from stable identity, not position), confirming Ref
survives context loss even though Progress resets.

## Result

All eight bounded scenarios (repeated question, Skip, referenced answer after reorder,
growing inventory, shrinking/partial inventory, and resumed conversation) produce
behavior consistent with the SKILL.md text: Ref stays stable and reorder-proof, Progress
advances only on distinct-item presentation, and totals are honestly qualified rather
than invented. No contradiction between the new "Item reference and walk progress"
section and the pre-existing selector/answer/lifecycle sections was found.
