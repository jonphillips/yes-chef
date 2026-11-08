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
- **create-recipe-calendar-review-fixes S1 + S2 + S3 (one PR):** On iPad Pro 13-inch (M5) (16GB) and iPhone 17 Pro, confirm From Chat Open, Copy, Discard, and whitespace isolation; save edited multi-paragraph Calendar complements with the keyboard up and reopen Edit; repeat the exact proposal-review edit and order from the original text-loss report, because that report is unconfirmed and isn't resolved until this passes (if the text disappears, note where you typed, how many proposals there were, and which button you tapped); edit Source in Create Recipe and an existing recipe, return using Back and swipe-back, and confirm the editor stays put with edits intact; tap the blank part of the Source row, between the text and the chevron, and confirm it opens Source. ([brief](efforts/archive/create-recipe-calendar-review-fixes.md))
- **ChatAccessKit export adoption:** Reinstall the helper and restart the tunnel. In Settings, Refresh updates the export time and size. Backgrounding within 15 minutes doesn't write a new export. From ChatGPT, `search_recipes` and `get_recipe` return content with the export's age. An evicted export reads back inside the 60-second bound, and the helper log shows `chat-access export materialize=…`. After a forced Refresh on the other device, the tools use the newer export and refuse the older ref as stale.
- **Workbench hand-off recipe returns (S1 + S2):** On iPad and iPhone, verify Compare recipe returns stage and save through Review Working Recipe; with an existing working recipe, verify the confirm and replacement behavior; verify Draft remains available. ([brief](efforts/archive/workbench-handoff-recipe-returns-and-candidate-choice.md))
- **Workbench hand-off candidate choice (S3):** On iPad and iPhone, verify Compare, Experiments, and Draft candidate selection, prompt contents, and candidate/reference fit counts. ([brief](efforts/archive/workbench-handoff-recipe-returns-and-candidate-choice.md))
- **menu-absorbs-calendar-days S1 + S2 (one PR):** After saving the placement, confirm the Bring In offer appears right away. Menu detail's **Bring In Calendar Items…** presents the same offer. Put two dishes and a note on the calendar across three days, and place Thanksgiving 2026 on one of them. Create a three-day menu over those days and Bring In. The calendar looks the same and the rows open the menu. Thanksgiving 2026 is unplaced with its plan intact, and its steps are in the new menu. Grocery items for moved dishes still group and remove correctly. A past placed menu recipe shows a last-cooked date. ([brief](efforts/menu-absorbs-calendar-days.md))

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
