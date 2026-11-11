# Council log: {run id}

Copy this template to the plan task's `council/log.md` and replace placeholders.
The [council skill](../../.agents/skills/council/SKILL.md#records-layout-and-fields) owns record semantics and collection order.

Planner: {name and authoritative home}; model/provider family: {actual model/family}; plan task: {id}.
Domain pack: {software/deal/marketing}; input/output type: {plan/packet/proposal}; research tier: {none/light/deep}.
Document authors and model/provider families: {manifest anchors or unknown with reasons}.
Planner-family seat exception: {captain authorization for this run or none}; data-sharing permission: {record reference}.
Selected roster: {counted seats and advisory}; round cap: {1-3}.
Times use {timezone/UTC offset} and full dates; missing evidence is `unknown: {reason}`, never a guessed value.

## Versions

| version | plan path | sha256 (full) | frozen/written time | file-time evidence |
|---|---|---|---|---|
| {vN} | {path} | {sha256} | {timestamp} | {path and observed mtime} |

## Seat attempts

| round | seat / counted or advisory | attempt | reviewed version / sha256 | task id | model | effort | repo commit | spawn time | report time | duration | words | validity / reason | replacement link | archive | timing evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| {n} | {seat; kind} | {k} | {version; sha256} | {task id or direct-process identity} | {actual model} | {effort} | {commit or not applicable for advisory} | {timestamp} | {original report timestamp or missing} | {elapsed} | {count or missing} | {valid, advisory-valid, or invalid with reason} | {replaces/replaced-by attempt or -} | {report or attempt archive, or no output} | {metadata spawn evidence; original report mtime} |

## Seat usage and family coverage

| round | seat/attempt | actual provider family | assigned lenses | inherited logical seat rows | input tokens | output tokens | USD | evidence or unknown reason |
|---|---|---|---|---|---|---|---|---|
| {n} | {seat/k} | {family} | {lenses} | {seat id} | {count} | {count} | {cost} | {billing/runtime evidence} |

| round | valid families and report counts | largest family share | required lens owners/families | missing families/lenses | rotation or reason impossible | cold-read divergence |
|---|---|---|---|---|---|---|
| {n} | {family: count} | {count/valid total} | {lens: owners and families} | {missing or none} | {assignments and constraints} | {anchors or none} |

## Research and spend

Whole-run budget USD: {numeric cap or uncapped}; deep submission limit/used: {limit/used}; query de-identification: {on/off and permission reference}.
Shared brief versions: {paths/full hashes/frozen times, or none}; coverage map: {anchor or provisional/no research}.
Research tier, cost limits and per-response accounting follow [research.md](research.md).

| question | phase | endpoint/preset | response id | start/end | seconds | input/output tokens | sources | reserved USD | usage.cost components/currency/total | cumulative settled USD | billing evidence or unknown reason |
|---|---|---|---|---|---|---|---|---|---|---|---|
| {Qid} | {discover/answer/deepen/claim/between} | {path/effort} | {id} | {times} | {elapsed} | {counts} | {count} | {bound or uncapped} | {returned fields or unknown} | {total} | {evidence} |

Outstanding reservations/uncertain charges: {response ids, USD and reason, or none}.
Skipped/unanswered questions and moderator passes: {artifact anchors and reason}.
Totals: {seat tokens/USD and research tokens/USD separately, unknowns with reasons; no double counting}.

## Rounds

| round | first counted spawn | last report | next version written | wall (spawn to next version) | merge (last report to next version) | valid counted reports | accepted must / should / nice | rejected count | value density (accepted must+should / wall minutes) | outcome / basis | timing evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| {n} | {timestamp} | {timestamp} | {timestamp} | {duration} | {duration} | {count} | {unique newly applied counts} | {count} | {numerator / denominator = value} | {checklist result} | {file and metadata sources} |

Use original report times, not archive-copy times; when a replacement fails without output, record that deadline separately in its attempt row.

## Terminal delivery

Terminal outcome: {exact checklist label and basis}.
Counted seats of the selected roster with no valid report: {seat names or none}.
Family/lens coverage: {complete or missing with reasons}; research/claim-check limitations: {anchors or none}.
Final version: {path and sha256}; last reviewed version: {path and sha256}.
Post-review deltas for captain approval: {finding ids and applied anchors or none}.
Rejected findings and reasons: {ids and reasons or findings-table anchors}.
Contested musts with both positions: {ids and positions or none}.
Unresolved findings and captain questions: {ids, owner/destination or originating hold keys, or none}.
