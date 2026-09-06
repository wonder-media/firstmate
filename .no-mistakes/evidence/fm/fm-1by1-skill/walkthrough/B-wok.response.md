Captain, **Project: WOK**

**Title:** Release Wonderok now, or hold for tomorrow's smoke check?

**Description:** The `wok-release` decision is open in the `mf` home (revision 7, Bridge lifecycle active). It's asking whether to ship the Wonderok release now or wait for tomorrow's smoke check to run first. The root snapshot shows the same item as a projection of this same task — treating it as one decision, not two.

**What your choice changes:** Determines whether the release goes out immediately or is delayed until the smoke check completes, affecting the whole `wok-release` task.

A. Release now
B. Wait for tomorrow's smoke check — **Recommended**: catches regressions before they reach users, at the cost of a short delay

**Hold (archive for later)** | **Discard (close task)** | **Skip (leave open, continue this walk)** | **Stop**

Reply with your choice or your own answer, and add any free-text notes.

*(Note: Hold/Discard would apply to the `wok-release` task as identified by Bridge's lifecycle_task_id — no sibling decisions currently share that origin.)*
