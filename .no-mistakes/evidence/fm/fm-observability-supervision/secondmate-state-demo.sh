#!/usr/bin/env bash
# Operator-view demo: what `bin/fm-crew-state.sh <id>` prints for a secondmate
# coordinator across every current-state situation the change covers.
set -u
ROOT=${FM_DEMO_ROOT:?}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-sm-demo.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

fakebin() {
  local fb=$1/fakebin; mkdir -p "$fb"
  cat > "$fb/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  list-windows)
    [ "${FM_FAKE_TMUX_MISSING:-0}" = 1 ] && { printf "can't find session: fm\n" >&2; exit 1; }
    printf '%s\n' "${FM_FAKE_TMUX_WINDOW:-fm-mate}" ;;
  display-message)
    [ "${FM_FAKE_TMUX_MISSING:-0}" = 1 ] && exit 1
    case "${*: -1}" in
      '#{pane_current_command}') printf '%s\n' "${FM_FAKE_TMUX_COMMAND:-claude}" ;;
      '#{pane_tty}') : ;;
      *) printf '%%1\n' ;;
    esac ;;
  capture-pane)
    [ "${FM_FAKE_TMUX_MISSING:-0}" = 1 ] && exit 1
    printf 'all quiet\n> \n' ;;
esac
exit 0
SH
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  status) [ "${2:-}" = --json ] && { printf '{"client":{"version":"0.7.1","protocol":14},"server":{"running":true}}\n'; exit 0; } ;;
  server) exit 0 ;;
  pane)
    case "${2:-}" in
      get)
        if [ "${FM_FAKE_HERDR_MISSING:-0}" = 1 ]; then printf '{"error":{"code":"pane_not_found"}}\n'
        else printf '{"result":{"pane":{"pane_id":"%s"}}}\n' "${3:-w1:p1}"; fi; exit 0 ;;
      read) [ "${FM_FAKE_HERDR_MISSING:-0}" = 1 ] && exit 1; printf 'all quiet\n> \n'; exit 0 ;;
    esac ;;
  agent)
    case "${2:-}" in
      get)
        if [ "${FM_FAKE_HERDR_NO_AGENT:-0}" = 1 ]; then printf '{"error":{"code":"agent_not_found"}}\n'; exit 0; fi
        [ -n "${FM_FAKE_HERDR_AGENT_STATUS:-}" ] || exit 1
        printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$FM_FAKE_HERDR_AGENT_STATUS"; exit 0 ;;
    esac ;;
esac
exit 0
SH
  chmod +x "$fb/tmux" "$fb/herdr"
}

# make_case <name> <lifecycle busy|idle> <backend tmux|herdr> [source] [harness]
make_case() {
  local name=$1 lifecycle=$2 backend=$3 source=${4:-claude-hook} harness=${5:-claude} d gen
  d="$TMP/$name"; mkdir -p "$d/state" "$d/wt"; fakebin "$d"
  gen=$("$ROOT/bin/fm-busy-event.sh" arm "$d/state" mate)
  "$ROOT/bin/fm-busy-event.sh" apply "$d/state" mate "$lifecycle" --gen "$gen" --source "$source" --event demo >/dev/null
  if [ "$backend" = herdr ]; then
    printf 'window=lab:w1:p1\nendpoint_task_id=mate\nworktree=%s/wt\nproject=%s/wt\nkind=secondmate\nharness=%s\nbackend=herdr\nbusy_gen=%s\nhome=%s/wt\n' "$d" "$d" "$harness" "$gen" "$d" > "$d/state/mate.meta"
  else
    printf 'window=fm:fm-mate\nendpoint_task_id=mate\nworktree=%s/wt\nproject=%s/wt\nkind=secondmate\nharness=%s\nbusy_gen=%s\nhome=%s/wt\n' "$d" "$d" "$harness" "$gen" "$d" > "$d/state/mate.meta"
  fi
  printf '%s\n' "$d"
}

show() {  # <label> <case-dir>
  local label=$1 d=$2 out
  out=$(PATH="$d/fakebin:$PATH" FM_STATE_OVERRIDE="$d/state" "$ROOT/bin/fm-crew-state.sh" mate)
  printf '%-46s $ fm-crew-state.sh mate\n%-46s   %s\n\n' "$label" "" "$out"
}

export FM_FAKE_TMUX_MISSING=0 FM_FAKE_TMUX_WINDOW=fm-mate FM_FAKE_TMUX_COMMAND=claude
export FM_FAKE_HERDR_MISSING=0 FM_FAKE_HERDR_NO_AGENT=0 FM_FAKE_HERDR_AGENT_STATUS=idle

echo "=== Secondmate current-state, as the captain reads it ==================="
echo

d=$(make_case busy busy tmux);           show "1. coordinator busy (tmux, claude hook)" "$d"
d=$(make_case idle idle tmux);           show "2. healthy idle, nothing declared" "$d"
d=$(make_case idle-oc idle herdr opencode-plugin opencode)
                                          show "3. healthy idle (herdr, opencode plugin)" "$d"
d=$(make_case decision idle tmux)
printf 'needs-decision: pick the rollout window [key=rollout]\n' > "$d/state/mate.status"
                                          show "4. idle + open decision -> parked" "$d"
d=$(make_case resolved idle tmux)
printf 'needs-decision: pick the rollout window [key=rollout]\nresolved: rollout [key=rollout]\n' > "$d/state/mate.status"
                                          show "5. decision resolved -> healthy idle again" "$d"
d=$(make_case declared-paused idle tmux)
printf 'paused: waiting on the vendor release\n' > "$d/state/mate.status"
                                          show "6. coordinator declared paused" "$d"
d=$(make_case declared-blocked idle tmux)
printf 'blocked: no API credentials\n' > "$d/state/mate.status"
                                          show "7. coordinator declared blocked" "$d"
d=$(make_case declared-then-note idle tmux)
printf 'paused: waiting on the vendor release\nnote: picked up the release notes\n' > "$d/state/mate.status"
                                          show "8. later informational note -> idle again" "$d"
d=$(make_case declared-then-busy busy tmux)
printf 'paused: waiting on the vendor release\n' > "$d/state/mate.status"
                                          show "9. declared paused but live busy -> working" "$d"
d=$(make_case stale-gen idle tmux)
sed -i.bak 's/^busy_gen=.*/busy_gen=GEN-FROM-A-DEAD-INCARNATION/' "$d/state/mate.meta"; rm -f "$d/state/mate.meta.bak"
                                          show "10. stale lifecycle generation -> unknown" "$d"
d=$(make_case dead idle herdr)
FM_FAKE_HERDR_NO_AGENT=1 show "11. dead endpoint, nothing declared -> unknown" "$d"
d=$(make_case dead-declared idle herdr)
printf 'paused: waiting on the vendor release\n' > "$d/state/mate.status"
FM_FAKE_HERDR_NO_AGENT=1 show "12. dead endpoint + declared paused -> paused" "$d"
d="$TMP/unsupported"; mkdir -p "$d/state" "$d/wt"; fakebin "$d"
printf 'window=fm:fm-mate\nendpoint_task_id=mate\nworktree=%s/wt\nproject=%s/wt\nkind=secondmate\nharness=cursor\nhome=%s/wt\n' "$d" "$d" "$d" > "$d/state/mate.meta"
                                          show "13. unsupported harness, no lifecycle -> unknown" "$d"
d=$(make_case remote idle tmux)
printf 'remote_host=mate@lab.invalid\n' >> "$d/state/mate.meta"
                                          show "14. remote secondmate unreachable -> unknown" "$d"
echo "=== end ================================================================"
