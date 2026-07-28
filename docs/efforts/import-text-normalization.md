# Effort: import text normalization — the shouting and the junk rows (2026-07-28)

**Type:** One-time data repair over existing synced rows + a capture-time guard so it stops recurring.
**No schema.** Two independent problems from two publisher families, cohesive because they are the same
write and the same hazard.
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **P1 ready to scope for dispatch; P2 declined; P3 blocked.** Jon closed the casing question
**2026-07-28: skip the de-capping** — option (c). So this effort is now **P1 only** (S1 + S2). P3 stays
parked behind [ADR-0014 Amd1-D1](../decisions/ADR-0014-recipe-text-editing-model.md#amendment-1--the-header-is-syntax-the-section-is-storage-and-the-split-happens-at-edit-time-2026-07-28)
*and* behind a future reversal of the P2 call, so it is not a queue item today.

Origin: the [ADR-0014 D3+D2 review](../reviews/REVIEW-2026-07-28-adr-0014-d3-d2-pr-254.md), which asked
whether `normalize-recipe`'s new markup-awareness requirement was actionable debt. It is not — see
"The requirement that started this is vacuous" below — but measuring the library to answer that turned up
a real want with a **different shape than the ADR assumed**.

**Read before starting:** [ADR-0014 Amd1-D3](../decisions/ADR-0014-recipe-text-editing-model.md)
(the migration hazard analysis this effort inherits wholesale — it is the same write against the same
tables, at 100× the row count), `jon-platform/docs/ios/persistence-and-sync.md` § "Data migrations write
*behind* the sync engine's back", and `CURRENT_HANDOFF.md` Verification Pattern.

---

## What `normalize-recipe` actually is

The ADR names it as one operation — "de-caps imported all-caps." **It does not exist in the code.** There
is no de-capping or re-casing anywhere: [`IngredientSectionHeading.swift:67`](../../YesChefPackage/Sources/YesChefCore/IngredientSectionHeading.swift#L67)
only *detects* all-caps to infer a heading and never rewrites, and the "capture polish" tests are URL
canonicalization. So nothing is carrying debt today; this effort **builds** the thing.

Measured against the live backup (`YesChef-Backup-2026-07-28.sqlite`, 2,179 recipes / 26,932 ingredient
lines), the one operation is really **two problems from two publisher families**, and they want opposite
treatments — one wants text rewritten, the other wants rows deleted.

| | Rows | Recipes | Source concentration |
|---|---|---|---|
| **P1** — `Gather Your Ingredients` junk | 101 lines + 70 sections | **171** | ATK 106 · Cook's Illustrated 51 · cookscountry.com 14 |
| **P2** — all-caps ingredient lines | 2,597 lines | **233** | **Milk Street 226** · 7 others |
| **P3** — all-caps section names | 284 sections | — | 70 are P1's junk; **214 are real headers** |

---

## P1 — America's Test Kitchen's "Gather Your Ingredients" is a **latent grocery bug**, not cosmetics

ATK/Cook's pages put a "Gather Your Ingredients" affordance above the ingredient list. The capture reads it
as content, and it lands in one of two shapes depending on page structure — **never both in the same
recipe** (0 recipes have both; 101 + 70 = 171 = the exact source total):

- **101 ingredient *lines*** reading exactly `Gather Your Ingredients` — and critically, **`isHeader = 0`**.
- **70 ingredient *sections*** named `GATHER YOUR INGREDIENTS`.

**All 101 lines are shoppable.** They carry `doNotShop = 0`, `isHeader = 0`, and all 101 canonicalize to the
single key `gather your ingredient` (the canonicalizer singularized it). Put any of those 171 recipes on a
menu and the grocery list gains an item called **"Gather your ingredient."**

It has not bitten yet — **0 `groceryItemSources` point at any of them** — so this is latent, not manifest.
That is luck about which recipes Jon has shopped, not a property of the data.

**Treatment: delete, do not normalize.** De-capping `GATHER YOUR INGREDIENTS` to `Gather your ingredients`
produces a tidier meaningless section. The line is not an ingredient and the section is not a section; both
are page chrome.

- The 101 lines: **delete the row.**
- The 70 sections: the section is the recipe's only/first ingredient section with a junk name — **clear the
  name, keep the section and its lines.** Do **not** delete the section: `ingredientLines.sectionID` is
  `NOT NULL … ON DELETE CASCADE`, so dropping it takes every ingredient with it. This is the same trap
  Amd1-D3 flagged for the header promotion.

**Referential safety, verified against the backup:** 0 `groceryItemSources` and 0 variation deltas reference
any of the 101 lines (in fact **none of the 171 recipes has a variation at all**). Nothing anchors them.

**Capture-time guard:** the extractor should drop the row at parse time so re-capture does not reintroduce it.
Match on the exact string, case-insensitively, **not** a `gather` substring — 28 instruction steps legitimately
contain the word ("gather the dough", etc.) and must not be touched.

---

## P2 — the shouting is one publisher, and de-capping is harder than it looks

2,597 all-caps ingredient lines across 233 recipes — **226 of them Milk Street**, whose site renders
ingredients in caps and whose capture reads the styled DOM (see [[paywall-gating-taxonomy]] — Milk Street
gates data server-side, so the DOM fallback path is the one in play). This is **one source's capture
artifact**, not a library-wide condition, which argues for fixing it in
[`RecipeMilkStreetExtractor.swift`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/RecipeMilkStreetExtractor.swift)
going forward plus a one-time backfill for the 226 already captured.

**The open question is casing, and it is a real one.** Lowercasing is trivial; restoring proper nouns is not:

```
1 POUND YUKON GOLD POTATOES, CUT INTO 1-INCH CUBES
2 TEASPOONS DIJON MUSTARD   ·   ½ CUP WHOLE-MILK GREEK YOGURT   ·   2 TEASPOONS SRIRACHA
```

A deterministic lowercase gives `yukon gold potatoes`, `dijon mustard`, `greek yogurt`. There is no rule that
recovers those; an LLM does it well. But this is a **reproducible write to canonical recipe data**, which is
the side of the [[llm-vs-determinism-surface-boundary]] line that is supposed to stay deterministic — and it
rewrites `canonicalName` for 2,597 lines, which **moves grocery grouping**.

**✅ DECIDED 2026-07-28 — option (c): skip the de-capping.** P1 earns its dispatch on its own; P2's cost
does not justify either a curated list or a 226-recipe review pass. The three options are kept below so a
reversal starts from the analysis rather than redoing it. **Do not build P2 on momentum while doing P1** —
S1/S2 touch only exact-match junk rows and must not acquire a casing pass.

**The three ways out, as evaluated:**

- **(a) Deterministic lowercase + a curated proper-noun exception list.** Reproducible, auditable, no model
  in the write path. Cost: the list is never done, and misses read as sloppy rather than as absent.
- **(b) LLM-cased, human-gated.** Model proposes, the existing review-sheet pattern
  ([ADR-0026](../decisions/ADR-0026-review-collection-sheet.md)) shows the diff per recipe, nothing writes
  unconfirmed. Best output; 226 recipes is a lot of gating unless it batches per recipe rather than per line.
- **(c) Leave P2 entirely; ship P1 only.** P1 is a latent bug with a mechanical fix; P2 is an aesthetic
  complaint about 10% of one publisher's lines. **Defensible, and the cheapest correct answer** if the
  shouting does not actually bother Jon in the reader.

If this is ever reopened, **(b) is the successor** — the review-sheet gate already exists, and the failure
mode of (a) is a list that is never finished.

---

## P3 — all-caps section names, and why they wait for Amd1-D1

284 ingredient sections have all-caps names. 70 are P1's junk (handled above). The remaining **214 are real
headers shouting**: `FOR THE SAUCE` (7), `FOR THE CHICKEN` (6), `SALAD` (5), `FOR THE FROSTING` (4)…

These are P2's problem in a different column, with the same casing question — but they carry an extra
constraint: **Amd1-D1 makes the section name the thing the colon syntax round-trips through.** The ADR's own
implementation trap applies directly — the `name` column stores the **colon-free** form, and the colon exists
only in the editor's flat-text projection. **A normalization pass must never add or strip a trailing colon on
a section name**, or it silently restructures the recipe on the next edit.

**Sequence P3 strictly after Amd1-D1 ships.** Doing it first means normalizing names that Amd1-D1 is about to
change the meaning of.

---

## The requirement that started this is vacuous — measured, not assumed

ADR-0014 requires any normalization pass to be markup-aware: no stripping or re-casing inside `**`/`*` runs
(D2) or `[…]` spans (D3), and per Amd-1 no touching trailing colons. Against the actual data, **the overlap
is empty**:

| Constraint | Collisions |
|---|---|
| All-caps lines containing `[…]` | **0** |
| All-caps lines ending in `:` | **0** |
| Milk Street prose fields containing `*` | **0** |

So a pass run **soon** needs no markup logic at all. That is an argument for doing this **before markup
accumulates**, not an argument for building markup-awareness now. Re-measure before dispatching — if Jon has
been authoring `**bold**` in the interim, the constraint becomes live and the pass grows a real requirement.

---

## ⚠️ The write hazard — this is the pass Amd1-D3's analysis was actually written for

Amd1-D3 worked out the full hazard for the `isHeader` promotion and then **dodged it**: only 10 rows, so the
answer was "fix them by hand, write no migration." **That escape is not available here.** P1 alone is 171
recipes; with P2 it is 2,597 line updates. The analysis applies in full:

- **[`Schema.swift`](../../YesChefPackage/Sources/YesChefCore/Schema.swift) runs `migrator.migrate` *before*
  `makeSyncEngine`, and SQLiteData installs its per-table sync triggers at engine construction.** Migration
  writes therefore get no `SyncMetadata` row. `ingredientLines` and `ingredientSections` both already exist
  and are already cached, so the `start()` sweep (which only touches brand-new tables) will never pick them
  up. **A repair done in the migrator writes rows that never upload — each device silently diverging.**
- **Therefore: run the pass *behind* the running sync engine**, as a one-time guarded pass, never in the
  migrator. See [[migration-writes-bypass-sync-triggers]].
- **The 101 deletes are the part that cannot be repaired by re-running.** A delete that never uploads leaves
  the row alive in CloudKit while the local row is gone, so a second run will not see it to delete again —
  and any later full-zone fetch (new device, backup restore) resurrects "Gather Your Ingredients" into
  recipes that no longer expect it. Deleting *through* the engine is mandatory, not a nicety.
- **No deterministic-UUID scheme is needed.** Unlike the header promotion, this pass mints no rows — it
  updates text in place and deletes. Both converge naturally.
- **Take a backup first.** [ADR-0030](../decisions/ADR-0030-local-backup-and-restore.md) shipped both halves;
  this is exactly what it is for.

---

## Slices (provisional — do not dispatch before the P2 confirm and Amd1-D1)

- **S1 — capture-time guard.** Drop the exact-match `Gather Your Ingredients` line/section at parse time.
  Core-only, exact-string match, cheap, stops the bleeding. Test with an ATK fixture **and** a negative case
  proving an instruction step containing "gather" is untouched.
- **S2 — one-time P1 repair, behind the running engine.** Delete the 101 lines; clear the 70 section names.
  Guarded, idempotent, logged. Verify post-run that a formerly-affected recipe produces no
  "Gather your ingredient" grocery item.
- **S3 — P2 de-capping. ❌ DECLINED 2026-07-28.** Not a queue item. Kept in the doc as analysis only.
- **S4 — P3 section-name casing.** Blocked on S3 being reopened *and* on Amd1-D1 shipping. Not queued.

## Verification

S1 is Core-only — `swift build` + `swift test` on the package, no app build. S2 writes against the live
database and cannot be certified by the package suite alone: it needs a device pass on Jon's `iPad Pro
13-inch (M5)` with a **backup taken first**, plus a two-device check that the deletes actually propagated
(the whole point of running behind the engine). Say so in the PR rather than claiming build-green is
sufficient.
