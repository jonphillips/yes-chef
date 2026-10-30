# Efforts index

Design/discussion + build-order docs for Yes Chef features. **The `decisions/` ADRs
record *what we decided*; these efforts hold the *worked design and slice plan*** that
implements a decision (or explores toward one).

**Authoring discipline** (jon-platform `docs/agent-workflow.md` § "Working docs stay
discoverable"):
- **Index at creation.** A new effort adds its one-line entry here in the same change —
  the index is kept fresh by ceremony, not vigilance.
- **Self-describing header.** Each effort carries a `Status:` stamp, a one-line
  `Summary:`, and `Related:`/`Superseded-by:` links. The entry below is a copy of the
  Summary; the Status lets you triage without opening the file.
- **Search before authoring.** Before writing a new effort or an ADR, `grep -ri
  <topic> docs/` and read adjacent efforts — cross-link them.

**Status legend:** Designed (spec'd, not dispatched) · Dispatched (with Codex) ·
In progress · Done (write-up in [`../DONE-LOG.md`](../DONE-LOG.md)) · Superseded.

**Coverage note:** this index is **backfilled on touch** — entries appear as efforts
are opened/edited, not via a retroactive sweep. Docs below are the ones touched since
the index was created (2026-07-08); the rest of `efforts/` gains an entry the next time
it's touched.

## Active / recent

- [automatic-backups.md](archive/automatic-backups.md) — **Dispatched 2026-10-25 (S1), ahead of chat-access-mcp S2**, schema-free, publishes the iCloud container · Yes Chef backs itself up. When the app comes to the foreground and the newest automatic backup is over 24 hours old, `CloudSyncKit` takes the same `VACUUM INTO` snapshot a manual export takes and writes it to iCloud Drive › Yes Chef › Backups. It keeps 14 daily and 6 monthly snapshots and never prunes the last one taken before the library shrank by half. Settings shows the last backup and has Back Up Now. Two PRs: jon-platform (additive), then Yes Chef.
- [chat-access-mcp.md](chat-access-mcp.md) — **S0 + S1 shipped and device-passed; S2 queued after automatic-backups S1**, schema-free, one entitlement change · Make Yes Chef the second consumer of jon-platform ADR-0007, so ChatGPT can stage a recipe into Yes Chef and look things up in the library instead of Jon pasting in both directions. Yes Chef isn't on the Mac, so an iCloud Drive folder carries the inbox and the read export between the Mac helper and the phone. S0 proves that transport end to end with probe tools before anything is built on it.
- [raw-import-html-drop.md](archive/raw-import-html-drop.md) — **Designed 2026-10-13, queued behind #348**, schema change + two data deletes on synced tables (Jon-approved) · Stop storing the raw page HTML (`Recipe.originalImportText`) in any build, and drop the column and its data before the CloudKit Production deploy. Nine browser captures exceed CloudKit's 1 MB record limit, so they never uploaded. Re-upload them, along with any child rows that never reached the server, then re-link the three calendar rows that sync broke. Capture stops saving photo rows it never downloads, and the 1,527 existing ones are deleted.
- [sync-failure-surfacing.md](archive/sync-failure-surfacing.md) — **Done 2026-10-26: Slices 1–6 shipped and device-passed**, schema-free, touches sync · The sync row said "Up to date" for weeks while nine recipes had never uploaded. `CloudSyncKit` gains a "not synced" signal: rows that never reached the server, and rows from the server that couldn't be applied here. "Up to date" now requires both counts to be zero, and Yes Chef's sync detail lists them by name with a Retry. Two PRs: jon-platform (additive), then Yes Chef.
- [yes-chef-dev-variant.md](yes-chef-dev-variant.md) — **Designed 2026-10-10; dispatch gated on the cut (`PROD-CUTOVER.md` Step 11)**, no schema, touches identifiers/entitlements/restore · Implements [ADR-0059](../decisions/ADR-0059-yes-chef-dev-variant.md). After the cutover, Xcode Run (Debug) builds **Yes Chef Dev**: its own bundle IDs, app group, URL scheme, display name and icon, so it can sit next to TestFlight Yes Chef on the same device. It keeps the real iCloud container, which puts it on CloudKit Development. Release doesn't change. Separately, `CloudSyncKit` backups record which build variant exported them, and the production app refuses a development backup (this answers Galavant ADR-0050 OQ2). Two PRs: jon-platform (additive), then Yes Chef.
- [prod-dead-column-drop.md](archive/prod-dead-column-drop.md) — **Dispatched 2026-10-08**, schema change on a synced table · Before the CloudKit Production schema locks, drop `Recipe.lastCookedAt` and `Recipe.timesCooked` (superseded by calendar-derived values) with one ordinary appended migration. Add a test that every table's on-disk columns match its model, so no other dead column reaches Production unnoticed. There is no migration squash: per ADR-0056 Amendment 1, the squash is deferred, optional cleanup.
- [cloudsynckit-backup-lift.md](archive/cloudsynckit-backup-lift.md) — **Done 2026-10-06**, schema-free, touches sync · Move ADR-0030 backup & restore and the restore hold into jon-platform `CloudSyncKit` (jon-platform ADR-0006) so Galavant can adopt it for its Production cutover. Adds an owner-only restore guard and a declared schema version that survives ADR-0056's squash. Two PRs: jon-platform (additive), then the Yes Chef rewire.
- [nyt-capture-fidelity.md](archive/nyt-capture-fidelity.md) — **Dispatched 2026-10-04**, schema-free · NYT captures lose their ingredient groups (only in the DOM) and store the author as a URL; recover the groups with a per-site DOM extractor behind a lossless guard and resolve a schema.org `Person` to its name. Publisher tags become opt-in at capture review for every site, and the snapshot keeps them all.
- [reader-count-scaling.md](archive/reader-count-scaling.md) — **Dispatched 2026-09-30**, schema-free · In the reader, unitless ingredients ("1 large onion", "3 garlic cloves") show their unscaled amount at any scale, a regression from the reader-density split rows (#323); take the amount from the scaled text. Rides along: a scaled unit reads singular at or below one.
- [ingredient-range-scaling.md](archive/ingredient-range-scaling.md) — **Built (#332); device pass owed**, schema-free · An ingredient written as a range ("8-10 ounces", "8 to 10 ounces") doesn't change when the recipe is scaled, and grocery drops or garbles it; the reader scales both ends, grocery shops the scaled upper bound (parser + post-engine repair of existing lines). Rides along: the compare aligner labels a provider-blocked response as its own fallback reason.
- [recipe-adjustment-content-filter.md](archive/recipe-adjustment-content-filter.md) — **Done (#330, device-passed 2026-09-30)**, schema-free · Recipe revisions fail on OpenAI with `stopReason=content_filter` because the adjustment prompt makes the model copy whole method steps verbatim as anchors. Stop requiring that echo when an ID anchors the row, backfill the snapshot from our own copy, and give a provider-filter stop its own error instead of the misleading "couldn't be read".
- [recipe-reader-density.md](archive/recipe-reader-density.md) — **In progress, placement correction in draft PR** · Put variation selection beside the recipe, shorten the reader header, and move the supplemental Playbook below Instructions in the Directions column as a compact Notes → Chef It Up → Make-ahead reference with a Serve With capsule strip and Ask now in the sparkle menu.
- [cockpit-find-multi-admit.md](archive/cockpit-find-multi-admit.md) — **Designed (queued 2026-09-25)**, schema-free ·
  Follow-up to the Cockpit Find receiver · When extraction finds N recipes, let the cook save any number of
  them from the one Create Recipe session instead of losing the rest after the first Save; a Cockpit referral
  then returns **one** verdict listing every saved recipe.
- [cockpit-find-handoff-receiver.md](archive/cockpit-find-handoff-receiver.md) — **Built (#322, #325); two-app round trip
  owed** · [ADR-0058](../decisions/ADR-0058-cockpit-find-referral-transport.md) · Receive raw Cockpit Find referrals
  through a pair-scoped App Group mailbox opened by a single-purpose `yeschef://find-referral` door, isolate
  0/1/N recipes for Create Recipe review, and return a typed verdict silently through the same mailbox.
- [prepared-components.md](archive/prepared-components.md) — **Designed (proposal)**, not dispatched, **post-cutover** ·
  Feeds a future ADR · Gives cooking its missing middle layer (`ingredients → prepared components → dishes`):
  a `Recipe.kind` enum makes a recipe a reusable component and a **directional** `recipeComponentLink` edge
  table (single-FK-safe) links a dish to the components it uses, at **recipe grain** (a "Components used"
  section — ingredient-line linking is declined to dodge anchor-repair). The flavor vocabulary
  (ACID/CRUNCH/UMAMI) is **one new facet** surfaced to the user as **"Dimension"** — no schema change, and
  the `Facet` table/type keeps its name. Entirely additive schema. The "on hand / use soon" inventory
  **ledger is parked on purpose** — it reopens the §14 settled boundary. Timing: additive ⇒ safe
  post-cutover, no forcing function to build before ship.
- [menu-dishes-reorder-container.md](archive/menu-dishes-reorder-container.md) — **Dispatched** · One PR for
  S1–S3: declare the recipe UTI, move menu Dishes onto the SDK 27 sectioned reorder container, and place
  Browse Recipes drops at the hovered reorder destination. Schema-free.
- [adr-0021-v4c-and-variation-delete.md](archive/adr-0021-v4c-and-variation-delete.md) — **Done** (write-up in
  [`../DONE-LOG.md`](../DONE-LOG.md)) · [ADR-0021](../decisions/ADR-0021-recipe-variations.md) Amd4-D4 ·
  Widens the variation delta vocabulary by **exactly two** anchored ops — `stepInsert` / `stepRemove` — so a
  variation can add and drop instruction steps instead of being forced out to a separate recipe, and adds the
  **Delete** affordance Amd2-D4 sanctioned but nobody ever built. Both halves schema-free. Moves and every
  section op stay unrepresentable and still route to split-off; the vocabulary is closed again.
- [variation-anchor-repair.md](archive/variation-anchor-repair.md) — **Designed, Dispatch 0 ships immediately** ·
  Defects in [ADR-0021](../decisions/ADR-0021-recipe-variations.md)'s anchor handling · A variation's
  anchors are taken from **model output** and never normalized to base IDs, so a base text edit orphans the
  variation permanently; `resolved(applying:)` **throws**, so one dead anchor takes out the editor, the
  reader fold and the grocery list; and two silent-failure paths in the adjust surface show nothing at all.
  Four dispatches, no schema.
- [dogfood-ferry-2026-07-25.md](archive/dogfood-ferry-2026-07-25.md) — **Designed** (not dispatched) · Jon's
  2026-07-25 ferry pass · **Three dispatches, three PRs.** D1: one shared full-screen expand control replaces
  four drifted copies + the Menu gains the Recipe's pinned-Ask onboard treatment (view layer only). D2:
  prep-plan/complement hand-offs regroup into per-day and per-plan overflow menus, per-day prep becomes a
  *scoped ask* over woven storage (no `dayOffset` on the step record — ADR-0034 holds), Clear gains a confirm,
  and "Prep Plan" stops leaking onto the recipe surface. D3: workbench Active/Completed + edit-in-place +
  honest delete copy, and menu learnings become hand-authorable through the orphaned `.inApp` provenance.
  One nullable synced column (`workbenches.dateCompleted`); everything else schema-free. The tab-bar shell is
  split out as [ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md), gated behind D1.
- [adr-0026-review-collection-sheet.md](archive/adr-0026-review-collection-sheet.md) —
  **Ready to dispatch** (Next Up) · Governed by
  [ADR-0026](../decisions/ADR-0026-review-collection-sheet.md) (Accepted) · Hoist the multi-item
  LLM-review collection into the slide-up sheet (the universal LLM-evaluation surface); remove the inline
  `ChatApplyReviewList` band; adjust verb becomes a launch-only row; S2 = reader-feedback curation adopts
  the same host-agnostic sheet. No schema.
- [dogfood-fixes-batch-5-mechanical-polish.md](archive/dogfood-fixes-batch-5-mechanical-polish.md)
  — **Dispatched** (2026-07-08) · Mechanical dogfood polish in one PR: recipe detail
  toolbar/layout, editor (auto-growing text + editable Make-Ahead/Chef-It-Up + async
  save), tokenized search, capture-review edits.
- [recipe-edit-proposals.md](archive/recipe-edit-proposals.md) — **In progress** (S3 = current
  Next Up) · Governed by [ADR-0023](../decisions/ADR-0023-recipe-edit-proposals.md) ·
  The "Adjust this recipe" verb: LLM writes only to a transient preview, reviewed
  side-by-side, committed to overwrite or a variation.
- [reader-feedback-comment-ingestion.md](archive/reader-feedback-comment-ingestion.md) —
  **Designed** · Governed by [ADR-0025](../decisions/ADR-0025-reader-comment-ingestion.md)
  · Interactive NYT comment harvest → LLM curation into *distinct* Reader Feedback notes
  (select+trim, never merge); Slices 4/5 partly superseded by shipped LLM infra.
- [browser-passwords-autofill-spike.md](archive/browser-passwords-autofill-spike.md) —
  **Spike** (not an ADR) · Investigate why system Passwords autofill fails in the
  `WKWebView` capture browser; *defends*
  [ADR-0009](../decisions/ADR-0009-in-app-authenticated-browser-capture.md)'s
  "never store credentials," does not reverse it.
