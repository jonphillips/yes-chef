# Device passes & held ops

Jon's checklist: real-device passes owed by merged work, and held ops steps. `NEXT_UP.md`'s **Owed** line
points here. The executor never reads this file; it only appends its own gate through `closeout`.

- **Adding:** `closeout` puts a new gate at the end of **Owed now**, so that list runs oldest to newest. Don't add
  at the top.
- **Clearing:** when a pass clears, the architect or Jon deletes its line and adds a note to `DONE-LOG.md`. The
  DONE-LOG's earlier "Owed" line stays, because it's history. Telling the architect what cleared is enough.
- **Held:** waiting on an ops step or on other work. Move a line to **Owed now** when it can be run.

**Standing state (not a task):** Yes Chef runs on CloudKit Production on both physical devices (`iPad Pro 13-inch
(M5)` and `iPhone 17 Pro`) since the cut finished on 2026-11-01 (`PROD-CUTOVER.md`). Debug builds install as Yes Chef
Dev, on CloudKit Development.

## Owed now
- **polish-batch-2026-11:** On iPad and iPhone, check linked Serve With, Related Recipes and Drafted From recipes in a Menu cover; calendar and Menu complement reasons through review and insertion; and repeated Sync sheet opening, including during sync. ([brief](efforts/archive/polish-batch-2026-11.md))
- **create-recipe-calendar-review-fixes S1 + S2 + S3 (one PR):** On iPad Pro 13-inch (M5) (16GB) and iPhone 17 Pro, confirm From Chat Open, Copy, Discard, and whitespace isolation; save edited multi-paragraph Calendar complements with the keyboard up and reopen Edit; edit Source in Create Recipe and an existing recipe, return using Back and swipe-back, and confirm the editor stays put with edits intact. ([brief](efforts/archive/create-recipe-calendar-review-fixes.md))

## Held

- **Cockpit Find handoff — the two-app round trip ([ADR-0058](decisions/ADR-0058-cockpit-find-referral-transport.md), PRs [#322](https://github.com/jonphillips/yes-chef/pull/322) + [#325](https://github.com/jonphillips/yes-chef/pull/325)), no schema.** This is Cockpit's S-join, so it is owed **after Cockpit S-c2** (verdict drain) lands; until then, Yes
  Chef's half can only be seen in `AppLog.handoff`. On device:
  - Send a multi-recipe email from Cockpit; Create Recipe opens with its provenance.
  - Save two candidates from one multi-recipe email; the Find shows both admitted, with no id seen and no hop.
  - Kill Yes Chef between the two saves; on relaunch, confirm Cockpit receives the first admission rather than a dismissal (the transient review session itself is not restored).
  - Glance back at Cockpit mid-review; the referral is **not** dismissed, and a later save still admits it.
  - Kill Yes Chef mid-review; the next launch dismisses it.
  - The Shortcuts "Capture a Recipe from Text" action shows only its text field.
- **[ADR-0030](decisions/ADR-0030-local-backup-and-restore.md) S2 — deliberately held.** The export → restore → re-enable-sync round-trip **passed on two simulators 2026-07-29** (isolated test
  container), which also closed OQ1. OQ6 is now diagnosed (Amendment 3): a naive real-device restore can be
  **silently clobbered by any peer's in-flight delete**, so **hold the real-device pass until the enforced restore
  procedure gates it** (quiesce peers → restore on one → reinstall peers). When it runs, follow that procedure —
  and **Undo Last Restore** is untested at all and rode the same broken binding as restore, so exercise it too.
  `PROD-CUTOVER.md` Step 9 has since run a real-device restore; Undo Last Restore still has no recorded pass.
