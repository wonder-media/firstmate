#!/bin/bash
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
bash bin/fm-brief.sh pinned .h/project --scout
python3 - <<'PY'
from pathlib import Path
p=Path('.h/data/pinned/brief.md');p.write_text(p.read_text().replace('{TASK}','Wait for instructions.').replace('{FIRSTMATE_SPEC}','Do not execute tools.'))
PY
bash bin/fm-spawn.sh pinned "$PWD/.h/project" --scout --harness codex --model gpt-6.1-sol --effort high --backend tmux --keep-model
printf 'PIN_SPAWN_EXIT=%s\n' "$?"
