# Bridge Hold / Discard test evidence (branch fm/fm-bridge-hold-discard, commit bdab1c3)

## Automated: tests/fm-board.test.sh (focused Board test, isolated fixtures)

- `fm-board-test-run.log`: FM_BOARD_BROWSER_TEST=1 run. All API/lifecycle checks pass
  (Hold/archive/resume, Discard, duplicate + stale 409, owner routing with failure packet,
  preserved answers gated while held, finished-task 409 Conflict, shared origin lifecycle,
  failed retry/Undo keeps error, already-stopped worker never relaunched, reconcile with tasks-axi).
  The headless Chrome step timed out on this host: headless Chrome hangs even on a `data:` URL
  (CVDisplayLinkCreateWithCGDisplay -6670 / Google Updater wait), so it is a host issue, not the product.
- `fm-board-test-external.log`: FM_BOARD_EXTERNAL_BROWSER=1 run (the test's supported external-browser
  invocation). The rendered page was driven through the existing chrome-devtools-axi Chrome session.
  The later "answers re-arm within 45 s" step failed only because the manual browser session took
  several minutes and the daemon's re-arm backoff had reached its 60 s cap (unrelated to lifecycle).
- `fm-board-test-default.log`: default run (no browser) covering every non-browser section.

## Manual browser evidence (real dashboard served by the synthetic fixture daemon)

- `bridge-desktop-1440x1000-waiting.png`: decision cards show Hold and Discard next to Confirm.
- `bridge-desktop-1440x1000-archive.png`: task cards in Happening show Hold/Discard; Archive holds the
  held task with "Future execution is paused. Work, history, and evidence remain available." and
  Discard + Resume.
- `bridge-desktop-hold-queued-undo.png`: after clicking Hold on "Qualified alias leaf" the card shows
  "Hold queued - undo available for 15 s" and an Undo (14 s) button.
- `bridge-desktop-hold-undone.png`: after clicking Undo the card is back with Hold/Discard.
- `hold-undo-db-state.txt`: persisted fixture DB after Undo: lifecycle_requests row state=cancelled,
  task_lifecycle stays active with no Bridge hold.
- `bridge-phone-390x844-waiting.png`, `bridge-phone-390x844-archive.png`: same surfaces at phone size
  (390x844, DPR 3, mobile+touch emulation), no horizontal overflow.
