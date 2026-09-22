# fm-brief.sh scaffold transcript (Item 2 + Item 3)

$ FM_HOME=/tmp/fmbrief-home.7BJW6w bin/fm-brief.sh demo-ship-001 wonder-media/firstmate --mode no-mistakes
scaffolded: /tmp/fmbrief-home.7BJW6w/data/demo-ship-001/brief.md (ship, mode=no-mistakes; replace {TASK})
$ FM_HOME=/tmp/fmbrief-home.7BJW6w bin/fm-brief.sh demo-scout-002 wonder-media/firstmate --scout
scaffolded: /tmp/fmbrief-home.7BJW6w/data/demo-scout-002/brief.md (scout; replace {TASK})

## Generated SHIP brief - new standing rules 8 and 9
8. Attribute authority in durable records, commit messages, PR bodies, issue comments, status lines, and reports to its actual source; only a quote of the captain's own words may be recorded as the captain's decision.
   Record everything relayed through firstmate or a second mate as "firstmate decided" or "the second mate decided", defaulting to "firstmate decided" when the source is uncertain.
9. Reference any firstmate-home artifact handed to you - a scout report, evidence directory, or directive file - by ABSOLUTE path, because a relative `data/` path resolves inside this worktree, not the firstmate home.
   The resolved absolute firstmate-home data directory is `/tmp/fmbrief-home.7BJW6w/data`; this task's artifacts live in `/tmp/fmbrief-home.7BJW6w/data/demo-ship-001`.

## Generated SCOUT brief - same shared rule text, task-specific resolved path
8. Attribute authority in durable records, commit messages, PR bodies, issue comments, status lines, and reports to its actual source; only a quote of the captain's own words may be recorded as the captain's decision.
   Record everything relayed through firstmate or a second mate as "firstmate decided" or "the second mate decided", defaulting to "firstmate decided" when the source is uncertain.
9. Reference any firstmate-home artifact handed to you - a scout report, evidence directory, or directive file - by ABSOLUTE path, because a relative `data/` path resolves inside this worktree, not the firstmate home.
   The resolved absolute firstmate-home data directory is `/tmp/fmbrief-home.7BJW6w/data`; this task's artifacts live in `/tmp/fmbrief-home.7BJW6w/data/demo-scout-002`.

## FM_DATA_OVERRIDE: printed path follows the real resolved firstmate-home data dir
$ FM_HOME=/tmp/fmbrief-ovr.DmPolj/home FM_DATA_OVERRIDE=/tmp/fmbrief-ovr.DmPolj/altdata bin/fm-brief.sh ovr-003 wonder-media/firstmate --mode local-only
   The resolved absolute firstmate-home data directory is `/tmp/fmbrief-ovr.DmPolj/altdata`; this task's artifacts live in `/tmp/fmbrief-ovr.DmPolj/altdata/ovr-003`.

## bin/fm-brief.sh --help records the same absolute-path rule
$ bin/fm-brief.sh --help
Scaffold a crewmate brief or persistent secondmate charter at
data/<task-id>/brief.md under the active firstmate home.
For ordinary tasks, the standard Setup/Rules/Definition-of-done contract is
filled in. Firstmate then replaces the {TASK} placeholder with the task
description, acceptance criteria, and context, and may adjust other sections
when the task genuinely deviates (e.g. working an existing external PR instead
of shipping a new one).
Reference firstmate-home artifacts in task text by absolute path; a relative
data/ path resolves inside the worker's worktree, not the firstmate home.
Usage: fm-brief.sh <task-id> <repo-name> --mode <no-mistakes|direct-PR|local-only> [--herdr-lab]
       fm-brief.sh <task-id> <repo-name> --scout [--herdr-lab]
       fm-brief.sh <task-id> --secondmate {<project>...|--no-projects}
