Captain, **Project: WOK**

**Title:** Release timing for Wonderok

**Description:** The `wok-release` task has an open decision (Bridge revision 7, active): should Wonderok release now, or wait for tomorrow's smoke check? This is recorded once in Wonderok's home (the root listing is the same item, just a projection).

**What your choice changes:** Determines whether the release ships immediately or holds until the smoke check runs tomorrow — affects the whole `wok-release` task, not just this decision.

A. Release now — ships immediately, skips waiting on tomorrow's automated smoke check.

B. Wait for tomorrow's smoke check — delays the release but gets an automated verification pass before shipping.

**Hold (archive for later)** | **Discard (close task)** | **Skip (leave open, continue this walk)** | **Stop**

Reply with your choice or your own answer, and add any free-text notes.

---
Note on scope: Hold or Discard here would apply to the `wok-release` task as a whole (Bridge `lifecycle_task_id`), not just this one decision.

Two more verified items are waiting after this one (a PR review request on Matt Fraser's site, and a CES admin-login prerequisite) — I'll bring up whichever's next once you respond to this one, unless you Skip or Stop. Three older WOK items (`old-proposal`, `finished`, `retired-idea`, `submitted`) are excluded as archived/resolved/do-not-resurface/delivery-pending respectively, and the `running` FM worker item is excluded as ordinary progress with no review requested — let me know if you want any of those revisited.
