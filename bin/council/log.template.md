# Council log: {run id}

Copy this template to the plan task's `council/log.md` and replace placeholders.
The [council skill](../../.agents/skills/council/SKILL.md#records-layout-and-fields) owns record semantics and collection order.

Planner: {name and authoritative home}; plan task: {id}.
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

## Rounds

| round | first counted spawn | last report | next version written | wall (spawn to next version) | merge (last report to next version) | valid counted reports | accepted must / should / nice | rejected count | value density (accepted must+should / wall minutes) | outcome / basis | timing evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| {n} | {timestamp} | {timestamp} | {timestamp} | {duration} | {duration} | {count} | {unique newly applied counts} | {count} | {numerator / denominator = value} | {checklist result} | {file and metadata sources} |

Use original report times, not archive-copy times; when a replacement fails without output, record that deadline separately in its attempt row.

## Terminal delivery

Terminal outcome: {exact checklist label and basis}.
Final version: {path and sha256}; last reviewed version: {path and sha256}.
Post-review deltas for captain approval: {finding ids and applied anchors or none}.
Rejected findings and reasons: {ids and reasons or findings-table anchors}.
Contested musts with both positions: {ids and positions or none}.
Unresolved findings and captain questions: {ids, owner/destination or originating hold keys, or none}.
