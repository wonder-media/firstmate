---
name: 1by1
description: >-
  Walk fresh items needing captain feedback one at a time when the captain invokes $1by1 or /1by1, optionally followed by a project selector.
  $1by1 wok isolates Wonderok; collect current decisions, approvals, reviews, and human prerequisites across registered homes without a separate queue or dashboard.
user-invocable: true
metadata:
  internal: true
---

# 1by1

Give the captain one concrete item to answer, wait for the actual answer, and record its accepted outcome through the existing owner before continuing.
This skill owns the conversational walk only; it does not change Bearings, Ahoy, lifecycle policy, or approval authority.

## Gather and select

1. Follow `AGENTS.md`'s session-start and lock requirements before operating, without repeating an already visible startup digest.
   An invocation authorizes gathering and presentation, not answering, approving, archiving, or closing anything.
2. Gather fresh structured state through [`bin/fm-fleet-snapshot.sh`](../../../bin/fm-fleet-snapshot.sh) or its [`bin/fm-bearings-snapshot.sh`](../../../bin/fm-bearings-snapshot.sh) projection, using their headers and current help for fields and bounds.
   Inspect pending feedback across the root and every registered home, preserving the snapshot's owning-home identity, provenance, freshness, and omitted-source disclosures.
   Reveal truncated decision and home surfaces through the supported bounds or targeted owning-home snapshot reads; do not mistake a bounded page for the whole inventory.
   Use the canonical snapshot for fields dropped by the compact projection, including project and task identities.
   Read the configured Bridge's authenticated state API for registered question details, options, revisions, project tags, pending answers, and lifecycle/archive state; [`bin/fm-board.py`](../../../bin/fm-board.py)'s header owns that interface and configuration.
   Its config file is private and holds the bearer secret: read only the non-secret fields you need (such as `lan_host`, `port`, and `repo_tags`) with a targeted query, never by printing the whole file.
   Pass the secret to `curl` only through a restricted temporary header or config file created with `umask 077` and removed after use, as [`bin/fm-x-lib.sh`](../../../bin/fm-x-lib.sh)'s `fmx_auth_header_file` does for Relay; never place it in a command argument, echo it, or record it in transcripts or reports.
   Do not print authentication secrets or bypass the API by editing its database.
   Reconcile Bridge freshness with the owning home's current structured records; a cached card, parent escalation, raw status tail, old report, or chat recollection cannot override readable owner state.
   Disclose inaccessible, stale, partial, or unexpanded sources briefly, and continue only with independently verified items; never call the overall inventory complete while coverage is uncertain.
3. Resolve an optional selector case-insensitively against current `data/projects.md` registries and Bridge repository aliases/project tags, retaining canonical repository identity where a tag groups projects.
   [`bin/fm-project-mode.sh`](../../../bin/fm-project-mode.sh)'s header owns registry syntax; Bridge owns alias interpretation.
   `wok` means Wonderok/WOK, never every project managed by the MF second mate.
   Match each item's project, not its owning home's name or charter.
   An unknown, ambiguous, conflicting, or unverifiable selector needs clarification before presenting or acting on any item; never fall back to the whole fleet or a guessed substring match.
   Without a selector, include every verified item from the root and each registered home regardless of its project tag, including Firstmate-owned `FM`-tagged work and repositories absent from the registry; registry membership is a selector-matching aid, not a default inclusion gate.
4. Keep actual open decisions and approvals, requests for captain review, and prerequisites that require the captain personally.
   A recorded PR alone is not a review request, and ordinary running work, automatic waits, and action-free integrity warnings are not feedback items.
   Exclude resolved/completed feedback, already accepted answers awaiting delivery, and archived or explicitly do-not-resurface work unless the captain explicitly asks to revisit it.
   An origin's completion does not close its independently open captain decision; use [`decision-hold-lifecycle`](../decision-hold-lifecycle/SKILL.md) for that distinction.
   Bridge lifecycle filtering applies to the origin and its decisions; do not resurrect an archived item from the snapshot's still-open underlying hold.
   Revisiting permits inspection, not automatic reopening or resuming.
5. Deduplicate by canonical owning home, originating task, and decision key, following owner-provided origin/hold mappings rather than constructing new identities.
   A root projection and its owning-home record represent one item; identical task/key strings in unrelated homes are not duplicates without ownership evidence.
   Prefer the readable owning record and retain separate keys on the same task.
   For unkeyed reviews or prerequisites, use their exact existing source identity and request; do not invent a key or close a neighboring decision.
6. Choose one eligible item by practical impact and urgency, using oldest unanswered first when otherwise tied.
   Keep selection and skipped identities in conversation only; do not persist a queue, cursor, copied decision ledger, or new walk-state file.

## Item reference and walk progress

Give every presented item a compact deterministic **Ref** derived from its existing canonical owning-home/task/key identity, never from its display position or current sort order.
Use the existing decision key with stable owner/task qualifiers needed to make it unique, for example `mf:receipt-cta/passes-vs-token`; for unkeyed items use the exact existing source identity from the gathering step.
Keep that same reference for the same identity across reordering and question revisions, retaining the revision separately for answer validation.
Never recycle a reference for another item, collapse distinct owners, or omit a qualifier merely because a competing item closed or left the selected scope.
References are readable aliases for existing identities, not a new registry or permission to act.

Show **Progress** as the distinct item's position in this conversational walk, such as `2/10`, not the number of answers accepted or implementation tasks completed.
Assign the next position only when first presenting a different eligible item; a clarification, repeated card, referenced return to an earlier item, or pending answer keeps that item's original position.
Skip allows the next distinct item to be presented; an accepted answer allows it only after the existing durable recording/routing requirement is met.
Compute the total as the distinct items already presented in this scoped walk plus the refreshed eligible items not yet presented, deduplicated by canonical identity.
Thus answered or skipped positions remain part of walk history, while new eligible arrivals increase the total and unpresented items that close or leave scope decrease it; briefly explain a changed total.
Count only items that passed this skill's eligibility and selector filters when presented or included as pending, never raw rows, duplicate projections, or ordinary running work.
Refresh eligibility before each selection rather than freezing a queue; use `2 of at least 10 (partial)` when ten distinct items are verified but coverage is incomplete, or `2/?` when no reliable total is available.
Keep the reference bindings, presented positions, and count history in conversation only.
After context loss, recover positions only from visible conversational evidence; otherwise say the count is restarting from refreshed records and start at `1`, preserving the existing selector and answer-binding clarification rules.

## Present one item and wait

Present exactly one feedback item per response, without an inventory dump or previews of later items.
Use this compact shape in plain language, with enough context to decide without opening an internal record:

> Captain, **Project: [project] | Ref: [stable reference] | Progress: [position/total]**
>
> **Title:** [short ELI5 title]
>
> **Description:** [what is happening and why your input is needed]
>
> **What your choice changes:** [concrete consequence, including task-wide scope when relevant]
>
> A. [meaningful option] - [brief reason; mark Recommended only when justified]
>
> B. [meaningful alternative] - [brief reason]
>
> [Optional C. meaningful third option and reason]
>
> **Hold (archive for later)** | **Discard (close task)** | **Skip (leave open, continue this walk)** | **Stop**
>
> Reply with your choice or your own answer, and add any free-text notes.

Example header: `Captain, Project: Wonderok | Ref: mf:receipt-cta/passes-vs-token | Progress: 2/10`.
Keep the source's 2-3 registered options and their meaning when available; otherwise offer 2-3 relevant choices supported by the request, without registering invented factual answers.
Recommend a supported course of action with a brief reason, never a guessed fact.
For factual unknowns preserve the factual alternatives and recommend verification before answering, without marking an unknown value as recommended.
Include a full PR URL when the item concerns a PR.
Explain that Hold and Discard concern the task identified by Bridge's `lifecycle_task_id`, including sibling decisions when they share that origin, so a choice about one card cannot silently become a wider action.
Always offer the four controls; if the owning lifecycle interface is unavailable, say Hold/Discard cannot yet be applied rather than pretending a fallback is equivalent.
Wait for the actual captain answer; a recommendation, silence, elapsed time, unrelated message, or tool default is not an answer.
Clarification, Stop, and an empty inventory are the only cases needing no feedback card: respond briefly without fabricating an item.
For an empty inventory say no verified pending items remain in the selected scope, retaining any coverage uncertainty and noting when skipped items remain open.

## Apply the answer through its owner

1. Bind the response to the presented owning home, task/origin, key or exact source identity, and decision revision where supported.
   If the captain names a reference, resolve it to that exact existing identity and its presented question/revision, not whichever item now occupies its old position; clarify an unknown or ambiguous reference instead of guessing.
   Preserve the captain's wording and notes, not just the option letter; ambiguous notes or competing choices require clarification on this same item.
   Refresh the owner record and Bridge decision/lifecycle state immediately before mutation, verifying identity, open status, question/options, scope, and revision.
   If anything material changed or closed, do not apply the old answer to the new revision or another item; explain the change and obtain a fresh answer if still needed.
2. Load [`decision-hold-lifecycle`](../decision-hold-lifecycle/SKILL.md) before recording or routing a decision answer, and [`ask-user-authority`](../ask-user-authority/SKILL.md) for an ask-user finding.
   Use the owner's current header/help for the supported route: Bridge's revision-checked answer interface for its cards, the decision-hold owner's keyed intake and routed-work procedures, or [`bin/fm-send.sh`](../../../bin/fm-send.sh)'s keyed answer path for live task decisions.
   Use one delivery route per answer; do not submit through Bridge and separately send the same decision.
   Set the exact owning `FM_HOME` for home-local operations, and route secondmate-owned work through its registered second mate or Bridge's existing owner transport rather than steering its child from the root.
   Preserve the existing pending-reply protocol: a successful send proves delivery, not that the second mate recorded or completed the requested action.
   Follow the normal lifecycle and configured approval rules for reviews, merges, and follow-up work; invocation of this skill supplies no standing approval.
3. Distinguish an authorization from evidence that a human prerequisite is complete.
   Permission to check a setting, send something, or verify access does not prove the setting, message, or access exists.
   Route authorized verification through the owner while leaving the original factual prerequisite open until the required evidence or explicit factual confirmation arrives.
4. Interpret the controls through their existing owners:
   - **Hold (archive for later):** request Bridge's `hold` lifecycle action for the displayed lifecycle task, using its current lifecycle revision and request identity.
     Bridge owns preservation of existing holds and worker handling; do not substitute a new captain decision hold or mark the decision resolved.
   - **Discard (close task):** request Bridge's `discard` lifecycle action for that same task scope.
     Bridge and the decision-hold owner retain their decline, dependency, and completion guards; this choice does not authorize deleting source files, history, or unlanded work.
   - **Skip:** make no source or lifecycle change; omit this identity for the remainder of the visible walk and continue with a fresh selection.
   - **Stop:** end the walk without changing any outstanding item; accepted actions already routed keep their actual recorded state.
5. Treat rejection, revision conflict, uncertain delivery, and partial lifecycle failure as unresolved outcomes.
   Explain the concrete failure on the same item and preserve recovery through existing records; do not force, retry through a weaker route, clear a dependency, or claim success.
   A queued Bridge request is pending, not completed; check the existing answer/lifecycle result and durable owning record before advancing as accepted.
   For other routes, verify the owner's durable answer and any routed follow-up records before advancing; never close an item by hand just to remove it from the walk.
6. After verified recording, acknowledge the outcome briefly and present only the next freshly selected item.
   Skipped and otherwise unresolved items remain recoverable in their original records.
   After context loss, refresh authoritative state and resume within the last visibly confirmed selector; if that selector or an answer's binding is missing, ask for clarification instead of broadening or replaying it.
   Lost conversational Skip history may cause an open item to appear again; disclose that limitation instead of inventing persisted walk state.
