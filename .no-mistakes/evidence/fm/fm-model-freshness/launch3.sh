#!/bin/bash
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
export FM_HOME="$PWD/.h" HOME="$PWD/.h/user" CODEX_HOME="$PWD/.h/codex" TMPDIR="$PWD/.h/tmp" TREEHOUSE_ROOT="$PWD/.h/pool"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=Validation GIT_AUTHOR_EMAIL=validation@example.invalid GIT_COMMITTER_NAME=Validation GIT_COMMITTER_EMAIL=validation@example.invalid
printf 'codex\n' > "$FM_HOME/config/crew-harness"
printf 'tmux\n' > "$FM_HOME/config/runtime-backend"
bash bin/fm-brief.sh fresh3 .h/project --scout
python3 - <<'PY'
import os,pathlib,json,datetime
h=pathlib.Path(os.environ['FM_HOME']); p=h/'data/fresh3/brief.md';s=p.read_text().replace('{TASK}','Local launch verification. Wait for instructions. Do not edit files.').replace('{FIRSTMATE_SPEC}','Wait without running commands.');p.write_text(s)
(h/'codex/models_cache.json').write_text(json.dumps({'fetched_at':datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),'models':[{'slug':'gpt-6.2-sol','visibility':'list'},{'slug':'gpt-6.2-astra','visibility':'list'}]}))
PY
bash bin/fm-spawn.sh fresh3 "$PWD/.h/project" --scout --harness codex --model gpt-6.1-sol --effort high --backend tmux --dispatch-override 'effort routing override'
printf 'SPAWN_EXIT=%s\n' "$?"
