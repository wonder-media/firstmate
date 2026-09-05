# Tool compatibility and freshness verification

This record verifies that startup compatibility gates and opt-in release freshness are separate mechanisms.
[`bin/fm-tool-versions-lib.sh`](../../bin/fm-tool-versions-lib.sh) owns compatibility floors, exact release-channel identities, and intentional CI pins.
[`bin/fm-version-inventory.sh`](../../bin/fm-version-inventory.sh) reads those values and performs the bounded maintenance comparison without installing or changing any tool.

## Current verification

Verified 2026-09-04 from a disposable Firstmate worktree.

The deterministic regression used only isolated fake executables and no real network:

```text
tests/fm-version-inventory.test.sh
# all fm-version-inventory tests passed
```

The regression proves exact repository routing for `kunchenguid/no-mistakes`, `kunchenguid/treehouse`, and `ogulcancelik/herdr`; exact npm package routing for the five axi tools; separate compatibility and freshness verdicts; `unknown/offline`; intentional CI pins; and hard per-request bounds.

The companion convergence regression uses two independent repositories so the standalone secondmate begins without the primary target object:

```text
tests/fm-secondmate-sync.test.sh
# all fm-secondmate-sync tests passed
```

That regression also covers linked worktrees, a standalone clone that acquires the missing commit from the local primary, dirty refusal before acquisition, divergence refusal after acquisition, and identity refusal before acquisition.

Run the live read-only inventory only during explicit maintenance:

```text
bin/fm-version-inventory.sh
```

Its current machine-specific output belongs in the maintenance report or PR evidence rather than this tracked behavioral record, because installed and published versions can change independently of Firstmate code.
`--offline` retains installed and compatibility fields while reporting every stable version and freshness verdict as `unknown/offline`.
The command never queries a live Herdr server; it reports Herdr's protocol floor and leaves compatibility unknown until an independently authorized live protocol check exists.
