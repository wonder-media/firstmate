# Instruction text as an agent reads it (Item 1 + Item 4)

## .agents/skills/harness-adapters/SKILL.md - grok startup-dialog paragraphs
```
Startup dialog on verified 0.2.x versions: the "Run Grok Build in a project directory?" project picker appears only when grok is launched from a non-project directory (home, Desktop, Downloads, `/tmp`).
`fm-spawn` launches inside the treehouse worktree (a git repo root), which avoided that picker and required no post-launch keystroke on those versions.
Pin `[hints] project_picker_disabled = true` in `~/.grok/config.toml` if a non-project launch ever needs to skip it.

Grok CLI 1.0.5 and later can show a directory-TRUST dialog on first launch in a worktree whose parent repo is not yet trusted; trust persists per parent repo, so the 0.2.x picker observation does not cover every first-run case.
Both the directory-trust and data-sharing first-run dialogs block queued input: messages sent while either is up are swallowed, and key sends do not reliably clear them.
Recover with `bin/fm-control.sh <task-id> relaunch`, not more key sends; the first relaunch's exit may report unconfirmed, and a second relaunch may be needed.
```

## The documented recovery command is real, not fiction
```
$ bin/fm-control.sh --help
Usage: fm-control.sh <task-id> interrupt
       fm-control.sh <task-id> relaunch [--harness <name>] [--model <name>]
```

## .agents/skills/1by1/SKILL.md - stored-option order rule
```
91:When a card carries registered options, present them in the card's own stored order, with the stored letters and meaning; otherwise offer 2-3 relevant choices supported by the request, without registering invented factual answers.
```

## .agents/skills/1by1/SKILL.md - recording step 1 (re-read + mapping)
```
   Refresh the owner record and Bridge decision/lifecycle state immediately before mutation, verifying identity, open status, question/options, scope, and revision.
   Re-read the stored options before recording an answer.
   When firstmate deliberately offers a better option the card does not carry, the recorded answer note must explicitly name which stored option the captain's letter resolves to and explain the mapping.
```
