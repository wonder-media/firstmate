#!/usr/bin/env bash
# End-to-end demo: PR-ready handoff vs. inactive reconciliation, base vs. change.
# Usage: demo-pr-ready-handoff.sh <worktree-root>
set -u
WT=$1
. "$WT/tests/lib.sh"
. "$WT/bin/fm-x-lib.sh"
. "$WT/bin/fm-wake-lib.sh"
BASE_PATH=/usr/bin:/bin:/usr/sbin:/sbin
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git -C "$WT" archive 15dbc8ced0900cef8bf5cf2533cd76c5fbb27d55 bin | tar -x -C "$TMP" && mv "$TMP/bin" "$TMP/base-bin"
URL=https://github.com/o/r/pull/37

setup() {  # <dir>
  local d=$1
  mkdir -p "$d/home/state" "$d/wt" "$d/project" "$d/fakebin" "$d/root/bin"
  printf '#!/usr/bin/env bash\n' > "$d/root/bin/fm-guard.sh"
  cat > "$d/fakebin/gh" <<'SH'
#!/usr/bin/env bash
case " $* " in *" headRefOid "*) echo 0123456789abcdef0123456789abcdef01234567 ;; *" state "*) echo OPEN ;; esac
SH
  printf '#!/usr/bin/env bash\necho "gh-axi $*" >> "$(dirname "$0")/../gh-axi.log"\n' > "$d/fakebin/gh-axi"
  printf '#!/usr/bin/env bash\necho "called" >> "$(dirname "$0")/../crew.log"\necho "state: done · source: fake"\n' > "$d/fakebin/fm-crew-state.sh"
  chmod +x "$d/fakebin"/* "$d/root/bin/fm-guard.sh"
  fm_fake_treehouse_legacy "$d/fakebin"
  fm_write_meta "$d/home/state/task-a.meta" window=firstmate:fm-task-a endpoint_task_id=task-a \
    "worktree=$d/wt" "project=$d/project" kind=ship mode=no-mistakes
  printf 'working: implementing\nneeds-decision [key=release-window]: Choose the release window\ndone: PR %s checks green\n' "$URL" > "$d/home/state/task-a.status"
  # Watcher has already seen every existing byte.
  fm_wake_signal_sig "$d/home/state/task-a.status" > "$(fm_wake_signal_seen_path "$d/home/state" "$d/home/state/task-a.status")"
}
run() {  # <dir> <bin> <script> args...
  local d=$1 b=$2 s=$3; shift 3
  FM_ROOT_OVERRIDE="$d/root" FM_HOME="$d/home" PATH="$d/fakebin:$BASE_PATH" "$b/$s" "$@"
}
recon() {  # <dir> <bin>
  touch -t 200001010000 "$1/home/state/task-a.meta" "$1/home/state/task-a.status"
  FM_ROOT_OVERRIDE="$1/root" FM_HOME="$1/home" FM_STATE_OVERRIDE="$1/home/state" FM_INACTIVE_RECONCILE_SECS=60 \
    FM_INACTIVE_CREW_STATE_BIN="$1/fakebin/fm-crew-state.sh" PATH="$1/fakebin:$BASE_PATH" "$2/fm-inactive-reconcile.sh" scan --startup
}
seen() { local s=$1/home/state; fm_wake_signal_seen_current "$s" "$s/task-a.status" && echo "yes (no self-wake)" || echo "NO (watcher would wake)"; }

for side in base change; do
  [ $side = base ] && B="$TMP/base-bin" || B="$WT/bin"
  D="$TMP/$side"; setup "$D"
  echo "================ $side ================"
  echo "\$ fm-pr-check.sh task-a $URL"; run "$D" "$B" fm-pr-check.sh task-a "$URL" 2>&1
  echo "\$ fm-pr-check.sh task-a $URL   # repeated"; run "$D" "$B" fm-pr-check.sh task-a "$URL" 2>&1
  echo "--- state/task-a.status:"; cat "$D/home/state/task-a.status"
  echo "--- watcher seen marker covers all bytes: $(seen "$D")"
  echo "--- open decisions (fm-classify-lib):"; ( . "$B/fm-classify-lib.sh"; status_open_decisions "$D/home/state/task-a.status" )
  echo "--- inactive reconcile cycle 1:"; recon "$D" "$B"; echo "(rc=$?)"
  echo "--- inactive reconcile cycle 2:"; recon "$D" "$B"; echo "(rc=$?)"
  echo "--- crew-state probes: $(wc -l < "$D/crew.log" 2>/dev/null || echo 0)"
done

echo "================ change: open legacy unkeyed decision, PR-ready and merge ================"
for mode in ready merge; do
  D="$TMP/unkeyed-$mode"; setup "$D"; printf 'blocked: waiting on infra\n' > "$D/home/state/task-a.status"
  if [ $mode = ready ]; then echo "\$ fm-pr-check.sh task-a $URL"; run "$D" "$WT/bin" fm-pr-check.sh task-a "$URL" 2>&1; echo "(rc=$?)"
  else echo "\$ fm-pr-merge.sh task-a $URL"; run "$D" "$WT/bin" fm-pr-merge.sh task-a "$URL" 2>&1; echo "(rc=$?)"; echo "--- gh-axi calls:"; cat "$D/gh-axi.log"; fi
  echo "--- state/task-a.status:"; cat "$D/home/state/task-a.status"
done
echo "================ change: immediate merge leaves no stale captain-held ================"
D="$TMP/merge-clean"; setup "$D"
echo "\$ fm-pr-merge.sh task-a $URL"; run "$D" "$WT/bin" fm-pr-merge.sh task-a "$URL" 2>&1; echo "(rc=$?)"
echo "--- state/task-a.status:"; cat "$D/home/state/task-a.status"
