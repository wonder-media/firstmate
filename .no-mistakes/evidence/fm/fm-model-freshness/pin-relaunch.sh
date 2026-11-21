#!/bin/bash
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
bash bin/fm-control.sh pinned relaunch --note 'Local validation: continue waiting without tools.'
printf 'RELAUNCH_EXIT=%s\n' "$?"
