# Council shared research procedure

The [council skill](../../.agents/skills/council/SKILL.md) owns orchestration; this file owns research, paid-call accounting, and merge claim checks.
Use one uncounted research desk scout through the existing dispatch path, not the planner or a counted reviewer.
Do not use the separate `pplx` agent, register an MCP server, or add scripts or a daemon.
The desk writes only task evidence under the parent task's `council/research/`; it never edits the reviewed input and never receives seat reports or dispositions.

## Authorization and credential handling

At intake record permission to send the selected documents to the selected model providers and research queries to Perplexity; a review request alone does not settle a new confidentiality choice.
Route missing permission through the council's ordinary decision path before transmission.
Use `PERPLEXITY_API_KEY` from the existing credential loader, sourced by name from `~/Library/Mobile Documents/com~apple~CloudDocs/Claude-Config/credentials/global/perplexity/perplexity.env`.
Refer to that file by name only: do not read or copy its contents into prompts, logs, tracked files or task artifacts.
Never print, log or commit the key, fragments, authorization headers, environment dumps or request diagnostics containing credentials.
Read the environment inside the HTTP client; avoid expanded secrets in process arguments and disable shell tracing and verbose HTTP logs.
An unset or rejected credential stops paid research and reports the concrete error; do not substitute another credential or rotate it yourself.
Keep any existing vault rotation note unchanged; this procedure does not verify rotation or block solely on that note.

`research.deidentify_queries` defaults to true.
When enabled, replace people/entities with generic roles, remove unique amounts, dates and identifiers unless essential and authorized, and never combine party names with deal terms.
Ask general factual questions, not requests to analyze a private agreement; manually inspect each outgoing payload, including follow-ups and URL parameters, for re-identification.
With explicit per-run permission the option can be false; log the choice, but never send secrets, credentials or whole private documents as research queries under either setting.
De-identification controls research queries, not permission to distribute the review packet to model providers.

## Named API path

Use direct HTTPS JSON requests with environment-backed Bearer authentication and `Content-Type: application/json`.
Discovery uses `POST https://api.perplexity.ai/search` with `query` (string or up to five queries) and a bounded `max_results`.
Answers use `POST https://api.perplexity.ai/v1/agent` with `input` containing the approved factual question and `effort` set to `fast` for a single fact or `medium` for a multi-hop question.
Do not use the legacy Sonar chat-completions endpoint or assume `choices[0]` exists.
Read answer text from message entries of `output[].content[]` with type `output_text`, and retain citation annotations and retrieved source metadata.
Use `high` only on tier deep, when conflicting medium sources concern an answer that could change the document structure.
For high, submit with `background: true`, retain the returned response id, and retrieve `GET https://api.perplexity.ai/v1/agent/{id}` until terminal.
A client timeout is not proof that a billed job stopped; retrieve its existing id rather than resubmitting it.
Use normal source monitoring for long waits, never another daemon.

Confirm current request controls and pricing from the official [Agent API](https://docs.perplexity.ai/docs/agent-api/quickstart), [effort](https://docs.perplexity.ai/docs/agent-api/effort), [background mode](https://docs.perplexity.ai/docs/agent-api/background-mode), [Search API](https://docs.perplexity.ai/docs/search/quickstart), and [pricing](https://docs.perplexity.ai/docs/getting-started/pricing) before spending.
Presets and rates can change; do not treat the scout report's estimates as measured prices or a spending bound.

## Spend ledger

Read `research.budget_usd` and `research.max_deep_runs` from the live roster at intake and log the resolved values.
A nonnegative numeric budget is a hard per-council-run USD cap; null or absent means uncapped, still with per-response accounting.
The tracked example uses $5 and at most two deep submissions across the entire council, not per round; light never makes high calls and deep requires an explicit request.
Include discovery, answers, follow-ups, merge claim checks, failed/retried billable requests and background jobs in the same ledger.
Never hide research fees inside seat costs or reset the budget when a round changes.

For a capped run, reserve a documented worst-case charge before submitting each request, checking settled spend plus all outstanding reservations plus the new reservation against the cap.
Use current published rates and enforceable input/output/tool/step limits, or a provider-side hard billing limit, to establish that upper bound; a typical price or estimate is insufficient.
If a call's maximum charge cannot be bounded within the remaining allowance, skip it and log the unanswered question rather than claiming the cap is enforceable after billing.
Keep uncertain or timed-out charges reserved; no further call may spend that reservation.
Uncapped runs do not require a dollar reservation, but retain call-count and tier limits.

For each response record question id, phase, endpoint/preset, response id, start/end time, seconds, input/output tokens, source count, reserved USD, actual `usage.cost` components/currency/total, and cumulative settled USD in the council log.
For background retrievals update the original call row rather than charging repeatedly.
If Search or another response omits `usage.cost`, write unknown with reason and separately record the current published fixed fee and evidence as an estimate, never as returned cost.
Settle from provider billing evidence before releasing its reservation; if unavailable, preserve the reservation and report the accounting gap.
Stop at the cap or deep-run allowance and list skipped questions; expanding a configured allowance needs authorization through the normal decision path.

## Pre-phase: none, light, deep

Software defaults to none; deal and marketing default to light; deep is opt-in only.
For none, make no pre-phase calls and log no shared brief; seats still perform the common absence check.
Defer spawning the desk until a required merge claim check or a permitted between-round request needs it.
A later external-fact must can require a bounded merge claim check even when pre-phase research was none.

1. Survey comparable outlines/checklists with one or two Search requests; discover up to five perspectives plus a standing basic-facts perspective in `research/perspectives.md`.
2. Write `research/questions.md`, with stable question ids and why each answer could change the document: at most three questions per perspective on light and five on deep.
3. Answer through the named API path, preferring primary sources such as statutes, regulators, official documentation and original data; distinguish jurisdiction, dates, conflicts and unknowns.
4. Perform one moderator pass on retrieved but uncited sources: check relevance/quality and ask what no perspective asked, without feeding low-quality material into the brief merely to use it.
5. Deepen only qualifying questions, within the whole-run allowance, or record why skipped.
6. Build the expected-section coverage map with packet anchors tagged present, thin or absent, then freeze `research/brief-v1.md` from [research-brief.template.md](research-brief.template.md) and record its full sha256 in the log.

The brief contains facts, sources with access dates/question ids/confidence, uncertainty and the coverage map, never recommendations, severity tags, issue lists, reviewer identities or attributions.
Supply exactly the same frozen version/hash to every counted seat; the advisory reader stays cold under [packs.md](packs.md#caps-and-advisory-promotion).
Paste the [common supplement](review-supplement.md) so the verify lens receives its shared-brief audit duty.
A source citation alone does not make a claim true; mark unsupported links between facts explicitly.

## Between rounds

Each seat may submit up to three factual research requests.
The planner strips finding ids, severity, recommendations, seat identity and identifying phrasing, then sends only de-identified factual questions to the desk.
The desk never reads the originating review.
Merge duplicate questions and answer within the same budget/tier limits; include another moderator pass over unused sources.
Freeze `brief-v<n+1>.md` with an unattributed fact/source change record and log its hash; never mutate a brief already reviewed.
Give that same version to all counted seats at the next round, together with only their own prior rows.
If no facts change, reuse the prior hash and explain why; unresolved requests stay visible in delivery.

## Merge claim check

Before applying any must that rests on an external fact (law, tax, market rate, policy or other outside claim), the planner sends its factual proposition without seat identity or finding context to the desk for one independent Search/fast lookup.
Record `verified`, `unverified` or `contradicted` plus source URL, access date, scope and reason in the finding's claim-check column; use `not-applicable` for claims based solely on packet/repository evidence or non-must findings.
Cap checks at ten per round and charge the same spend ledger.
A previous shared brief assertion alone is not independent verification.
Only verified external-fact musts may be applied on that factual basis; unresolved/contradicted claims remain open or deferred, or are rejected with a documented evidence-based reason, retaining original severity.
When authorization, the lookup allowance, evidence or budget prevents verification, record unverified, never infer the answer or claim convergence with an outstanding must.
Check exact jurisdiction/date/applicability and distinguish a factual result from a legal interpretation; a lookup is not legal advice.
Deliver the brief, coverage map, accounting and unanswered questions, adding consolidated questions for licensed counsel on deal reviews.
