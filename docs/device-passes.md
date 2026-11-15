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
- **create-recipe-calendar-review-fixes S1 + S2 + S3 (one PR):** On iPad Pro 13-inch (M5) (16GB) and iPhone 17 Pro, confirm From Chat Open, Copy, Discard, and whitespace isolation; save edited multi-paragraph Calendar complements with the keyboard up and reopen Edit; repeat the exact proposal-review edit and order from the original text-loss report, because that report is unconfirmed and isn't resolved until this passes (if the text disappears, note where you typed, how many proposals there were, and which button you tapped); edit Source in Create Recipe and an existing recipe, return using Back and swipe-back, and confirm the editor stays put with edits intact; tap the blank part of the Source row, between the text and the chevron, and confirm it opens Source. ([brief](efforts/archive/create-recipe-calendar-review-fixes.md))
- **ChatAccessKit export adoption:** Reinstall the helper and restart the tunnel. In Settings, Refresh updates the export time and size. Backgrounding within 15 minutes doesn't write a new export. From ChatGPT, `search_recipes` and `get_recipe` return content with the export's age. An evicted export reads back inside the 60-second bound, and the helper log shows `chat-access export materialize=…`. After a forced Refresh on the other device, the tools use the newer export and refuse the older ref as stale.
- **kitchen-knowledge-promotion:** On the iPad, run Export What I've Taught; on the Mac, run `scripts/promote-knowledge -n` and check the summary includes the mint fix, then run it for real and open its data diff as a PR; install a build with that promotion and confirm the fix is gone from Name Fixes while fresh mint leaves and mint still merge into one item. ([brief](efforts/archive/kitchen-knowledge-promotion.md))
- **dogfood-polish-2026-11-13:** On iPad and iPhone, check dated sorting and new menu selection; menu title scrolling; Fresh rapid-add visibility and focus; Same As labels; rounded grocery quantities; and recipe sharing to Messages and Notes. ([brief](efforts/archive/dogfood-polish-2026-11-13.md))
- **family-cookbooks S5 visiting polish:** On iPad and iPhone, accept an invitation while the app is force-quit and running and confirm it opens the cookbook; check In My Recipes in the list, Power Browser, and Lens shelves; open a recipe from a Lens shelf and from its See all, and confirm it opens the cookbook's recipe; tap Open on the copy toast; verify a copied full-size photo; use Copy Them Too and follow related and serve-with links; and confirm Focus hides the list while keeping the screen awake. ([brief](efforts/archive/family-cookbooks.md))
- **SQLiteData 1.13.0 rebase (patch 1 only; no app schema change):** Before installing, back up the iPad and note the Sync screen's "couldn't be saved here" count. On the first build with it, installed as an update on both devices: the library opens with counts unchanged, the parked count settles to 0, and an edit on each device (including a new recipe note and an instruction step, which are single-parent rows) arrives on the other. With the app force-quit, save a recipe from the share extension and confirm it uploads on next launch. Afterwards, don't install a Debug build from before this PR on either device: SQLiteData's metadatabase gains two migrations, and older Debug builds assert on launch (Release tolerates it). ([YESCHEF-PATCH.md](../Vendor/sqlite-data/YESCHEF-PATCH.md))

## Held

- **family-cookbooks §S3 publish — the cookbook container in Release ([ADR-0071](decisions/ADR-0071-family-cookbooks.md), PR [#519](https://github.com/jonphillips/yes-chef/pull/519)).**
  - Before the **next** TestFlight build of any kind, because Release now carries the entitlement and checks the zone at
    launch: confirm the `com.jonphillips.yeschef` App ID lists `iCloud.com.jonphillips.yeschef.cookbook` (automatic
    signing should add it when you archive).
  - Before the first TestFlight build that shows Family Cookbook (S4 lifts the DEBUG gate): in CloudKit Console, deploy
    `CookbookRecipe` (`payload`, `contentHash`, `payloadVersion`, `displayImage`), `CookbookProfile` (`displayName`,
    `recipeCount`, `payloadVersion`, `publishedAt`) and S4's `CookbookLenses` (`payload`, `contentHash`,
    `payloadVersion`) from Development to Production. S4's device pass has run (2026-11-14), so Development has every field.
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
