# ADR-0014 — Recipe text editing model (header toggles vs. rich text)

**Status:** Accepted (direction) — 2026-07-04; **amended 2026-07-28** ([Amendment 1](#amendment-1--the-header-is-syntax-the-section-is-storage-and-the-split-happens-at-edit-time-2026-07-28),
which supersedes D1's mechanism — read it before slicing D1). Implementation not yet dispatched.
**Owner:** Claude (architect) · Jon (product).

## Context

Jon, dogfooding 2026-07-04:

> "The header on/off editing functionality is pretty crazy from a UI perspective. Why are we avoiding
> allowing me to just set text to Bold, Italics, etc.?"

The structured editor (ADR-0004) models a recipe as typed rows — ingredient lines, instruction steps, and
**section headers** that are a *structural row kind*, toggled on/off, rather than inline text styling. So
"make this a header" is a row-type switch, not "select text → bold." That structural model is what powers
auto-numbering of instructions, ingredient scaling, grocery/pantry canonicalization, and the whole
parse/scale/render pipeline. Free-form rich text would sever those affordances from the text.

### What grounding the code revealed

The schema already contains **two competing grouping mechanisms** that don't agree:

- `IngredientSection` / `InstructionSection` (`Models.swift`) — real structural groups, each with a `name`,
  UUID PK, already sync-safe, already rendered as grouped sections and reasoned over by the app.
- `isHeader: Bool` on a line (`Models.swift`) — a *label row* that lives inside a section but owns nothing
  below it. This is the "toggle" Jon is fighting.

Critically, the editor only surfaces the **first** section (`RecipeEditorDraft.init(detail:)` →
`firstIngredientSectionID`). Multi-section recipes are flattened on edit, and the `isHeader` toggle was the
consolation affordance for expressing structure the editor otherwise threw away. **That flattening is the
root of the "crazy UI" complaint** — not the structural model itself.

## Decisions (resolved 2026-07-04)

The pain was the **editor UI**, not the structured model. We keep structure; we fix the affordances. Three
independent changes, sliceable separately:

### D1 — Grouping: promote headers to real sections; make the editor section-aware

Chosen behavior (Jon): a header must **own the rows beneath it** — reorder / collapse / delete as a unit,
not just show a label.

- The editor becomes multi-section: it reads and writes all `IngredientSection` / `InstructionSection`
  rows, using each section's `name` as its header.
- A "header" in the flat-text authoring flow becomes a **section boundary**, not an `isHeader` line.
- **Retire `isHeader`** as an authoring concept. Migration: existing `isHeader` rows are promoted to a new
  section whose `name` = the header row's text, owning subsequent lines until the next header. Keep the
  column readable during transition; stop writing new `isHeader=true` rows.
- Downstream is unaffected: scaling, numbering, and grocery canonicalization operate per-line and are
  already section-agnostic. Sections already round-trip through CloudKit (UUID PKs), so this is additive.

### D2 — Inline styling on free-text fields only (Markdown-in-string)

- Applies to **free-text fields the app does not parse**: `summary`, notes, tip blocks. Ingredient and
  instruction rows stay structural — no inline styling there.
- **Encoding: Markdown stored inline in the existing text columns** (`**bold**`, `*italic*`). Render with
  `AttributedString(markdown:)`. Rationale: purely additive (columns are already `String`), CloudKit-safe,
  human-legible in the raw store, no attributed-run/BLOB model to sync. Rejected the attributed-run model
  as heavier with no round-trip benefit.
- Editor affordance: a minimal bold/italic control (or just let raw Markdown through initially).

### D3 — `[square bracket]` = author note, rendered lighter

- Convention: text in `[…]` inside an ingredient line is a **Jon note**, rendered at a lighter weight /
  de-emphasized.
- **Pure render rule + parser-ignore** — no schema change. The ingredient parser must treat bracketed spans
  as annotation, not item/quantity/unit; it can land the text in the existing `comment` field. The bracket
  stays in `originalText` so the round-trip is lossless.

## Sequencing / cross-cutting

- **`normalize-recipe` (de-caps imported all-caps) must be markup-aware**: it must not strip `**`/`*` runs
  (D2) or `[…]` spans (D3), and must not up/down-case inside them. Normalization runs on import before user
  styling exists, so the live conflict is small, but any re-run pass has to respect the markup.
- All three are **additive** and land after sync is live — no migration risk beyond the D1 `isHeader`
  promotion, which is a one-time forward transform.
- Suggested slice order: **D3** (smallest, render-only) → **D2** (free-text styling) → **D1** (editor
  section rework, the meatiest).

## Consequences

- Retires the `isHeader` toggle and the single-section editor flattening — net reduction in concept count.
- The editor gains multi-section authoring, which the data model has always supported but never exposed.
- Free-text fields carry Markdown; anything that displays `summary`/notes must render through the Markdown
  path or it will show literal `**`.
- `normalize-recipe` picks up a markup-awareness requirement.

---

## Amendment 1 — the header is *syntax*, the section is *storage*, and the split happens at edit time (2026-07-28)

**Status:** Accepted (direction) — 2026-07-28. Supersedes D1's **mechanism**; keeps its outcome.
Implementation not yet dispatched.

### Why an amendment: D1's premise is obsolete

D1 was written against an editor that "only surfaces the first section" and flattened multi-section recipes
on edit. **That is no longer true.** [`RecipeEditorDraft.ingredientSectionDrafts`](../../YesChefPackage/Sources/YesChefCore/RecipeEditorDraft.swift)
builds a draft per `IngredientSection` / `InstructionSection`, each with an editable `name`, and
[`RecipeEditorSectionReconcile`](../../YesChefPackage/Sources/YesChefCore/RecipeEditorSectionReconcile.swift)
writes them back per-section (ADR-0048's grain rule got there first). The multi-section half of D1 shipped
without this ADR being dispatched.

So the "crazy UI" Jon is *still* feeling is the other half — `isHeader` — and grounding it showed the code
already straddles the fork this ADR was opened to decide:

- [`RecipeEditorModels.ingredientTextChanged`](../../YesChefApp/RecipeEditorModels.swift) sets
  `isHeader: text.hasSuffix(":")` — **the text already decides**, on every keystroke.
- `RecipeEditorView.IngredientLineStructureEditor` renders a parallel list of `Toggle("Header")` rows — the
  **out-of-band repair UI** for when the inference is wrong.
- `IngredientLineRow` **strips the trailing colon** when rendering a header. The colon is already markup.
- [`IngredientParser.lines`](../../YesChefPackage/Sources/YesChefCore/IngredientParser.swift) applies the same
  colon rule on the import path.

**The annoyance is structural, not cosmetic.** A line-oriented text box has nowhere to put a per-line
attribute, so the attribute needs its own parallel surface — and now two views of the same lines can drift
(edit a line's text, its toggle stays put). No amount of toggle-polish fixes that; only removing the second
surface does.

### Amd1-D1 — Colon is the authoring syntax; sections remain the storage grain

A line that reads as a header **is** a header. The rule: **ends in `:` and parses no leading quantity**
(the quantity guard keeps `Salt:` -shaped ingredient lines out; today's bare `hasSuffix(":")` is too loose).
Its text minus the colon becomes the section `name`.

Storage does **not** change: `IngredientSection` / `InstructionSection` rows stay the grain, keeping row
ownership (collapse / reorder / delete as a unit — Jon's D1 requirement), UUID PKs, and CloudKit safety.
This is consistent with D2's already-accepted encoding philosophy: legible markup in the text beats an
out-of-band attribute.

### Amd1-D2 — The split happens at **edit time**, never at save time

The rejected alternative was one text box per recipe with sections *derived on save*. Derivation is two
steps, and the second one is the hazard:

1. **Split** the text into groups on the colon rule. Safe — it's the rule already in the parser.
2. **Match** each derived group back to an existing `IngredientSection` **row**, to preserve its UUID.

Step 2 does not exist today because identity is **explicit**: each editor card carries the real section UUID
in `draftSection.id`. Re-deriving it from bare text has a **silent** failure mode — the line reconcile is
scoped by section id (`existingLinesBySection[draftSection.id]`), so if a rename reads as delete+insert, the
lookup returns empty and every line in the group reconciles as brand new, **dropping `canonicalName`,
`shoppingCategory`, `doNotShop` and merged parse confidence** for the whole group, plus a CloudKit section
delete+insert. That is exactly the failure shape ADR-0040's lossless-or-loud rule exists to prevent.

**Decision:** keep the per-section cards, and make the colon rule live *inside* the editor:

- Typing or pasting a header line mid-card **splits that card in two**, minting the new section's UUID and
  moving the affected line drafts across **with their own IDs intact**.
- Pasting a list containing three header lines yields three cards.
- Clearing a card's name **merges it back up** into the preceding card.
- **The save path is untouched.** `RecipeEditorSectionReconcile` still receives explicit section IDs; step 2
  never happens.

Identity is manipulated where identity exists — in the editor, with UUIDs in hand — instead of being
reconstructed from a string at the storage boundary.

### Amd1-D3 — Retire `isHeader` (D1's outcome, new mechanism) — and mint the migration's UUIDs deterministically

`applyIngredientLineDrafts` (whose only job is applying the toggle over the parser's guess) collapses to
nothing, and the `Toggle("Header")` list goes with it. `isHeader` stops being written; existing
`isHeader = true` rows are promoted to sections owning the lines beneath them, per D1.

⚠️ **This is no longer the "additive, lands after sync is live" migration D1 assumed — sync *is* live
(M4, 2026-07-11), so the promotion rewrites synced rows on Jon's two devices.** A migration that mints
`UUID()` per device will mint **different section UUIDs for the same header on each device**. **The section
UUID must be derived deterministically** from (`recipeID`, header line `id`) so both devices converge on the
same row.

**Grounding this in the sync engine (audited 2026-07-28) turned up a second, different hazard, and it is the
one that bites this migration.** [`Schema.swift`](../../YesChefPackage/Sources/YesChefCore/Schema.swift)
runs `migrator.migrate(database)` **before** `makeSyncEngine`, and SQLiteData installs its per-table sync
triggers at engine *construction*. **Migration writes therefore never fire the triggers and get no
`SyncMetadata` row.** At `start()` the engine sweeps only **brand-new tables** (`uploadRecordsToCloudKit`
does `UPDATE <table> SET pk = pk` for tables absent from the cached `RecordType` list, which fires the
now-installed triggers); nothing sweeps migration-inserted rows in a table that *already* existed.

`ingredientSections` already exists and is already cached. So a promotion done in the migrator would write
sections that are **never uploaded** — each device silently building its own local-only structure — until
some later unrelated write happens to touch them. That is divergence rather than duplication, and it is
invisible.

**Consequences for the slice — both are required, not either/or:**
- **Derive the section UUID deterministically** (UUIDv5-style over `recipeID` + header line `id`), so
  whatever each device writes locally, the rows are *identical* and upserts converge.
- **Do the promotion after the sync engine is up**, not inside the migrator — a one-time guarded pass so the
  triggers exist and the rows actually upload. (The migrator may still create/alter schema; it is the
  **data** promotion that must move.)

See the companion finding on `"Move menu prep plans into editable step rows"` in
[`docs/open-questions.md`](../open-questions.md) — same root cause, opposite symptom, and already shipped.
The general rule now lives in `jon-platform/docs/ios/persistence-and-sync.md`
("Data migrations write *behind* the sync engine's back").

**What the promotion actually touches, ranked by risk** (all three are on *existing* synced tables, so all
three need the post-engine pass):

1. **INSERT** `ingredientSections` — deterministic UUIDs make concurrent devices converge.
2. **UPDATE** `ingredientLines.sectionID` (re-parent) + `sortOrder`. Line **ids are preserved**, which is what
   keeps stored variation ops (anchored on `baseIngredientID`) and `groceryItemSources.ingredientLineID`
   valid. `ingredientLines` has two FKs, so SQLiteData assigns it **no** CloudKit parent reference —
   re-parenting does not move a CKRecord.
3. **DELETE** the header `ingredientLines` rows — ⚠️ **the one that cannot be repaired by re-running.** A
   delete that never uploads leaves the row alive in CloudKit while the local row is gone, so the pass won't
   see it to delete again; any later full-zone fetch (new device, backup restore, zone rebuild) resurrects
   header lines into recipes that no longer expect them. Deleting *through* the running engine is therefore
   not a nicety here.

Do **not** delete any existing `IngredientSection` during the promotion: `ingredientLines.sectionID` is
`NOT NULL … ON DELETE CASCADE`, so dropping a section takes its lines with it. The promotion only adds
sections and re-parents.

`originalSnapshot` keeps the pre-promotion shape and is **not** rewritten — it is passive provenance. This is
safe for Compare, which is line-based and already filters `isHeader` on both sides.

**Pre-flight audit before dispatching the slice** (run against a backup export, ADR-0030 S1) — sizes the job
and catches anything anchored to a row that is about to disappear:

```sql
SELECT COUNT(*) AS header_lines FROM "ingredientLines" WHERE "isHeader" = 1;
SELECT COUNT(*) AS grocery_sources_on_headers
FROM "groceryItemSources" s JOIN "ingredientLines" l ON l."id" = s."ingredientLineID"
WHERE l."isHeader" = 1;
```

The second must be **0** — shopping already filters `!isHeader` ([`GroceryCore.swift`](../../YesChefPackage/Sources/YesChefCore/GroceryCore.swift)),
so a non-zero count is a pre-existing bug to understand *before* the rows vanish. Stored variation ops
anchored to a header line should likewise be impossible (ops target ingredients); worth an eyeball in the
same pass.

**Given step 3's one-shot nature, seriously consider splitting the slice:** promote additively (steps 1–2)
and defer the header-line delete to a follow-up release once the sections have converged on both devices,
per the additive-only guidance in `jon-platform/docs/ios/persistence-and-sync.md`. The interim cost is that
every reader must filter the orphaned header lines — which the reader, Compare, and grocery already do.

### Amd1-D4 — ⚠️ Correction: this does **not** hand ADR-0021 Amd1-D5 a free ride

In discussion I said the composed model would make "add a section header inside a variation" representable in
the existing delta vocabulary with no new ops. **That claim does not survive the code.**
[`derivingVariation`](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift) diffs **structures,
matched by section ID** — not the flat serialization. Under Amd1-D2 the editor's live split mints a genuinely
new section, so the derivation hits `.ingredientSectionAdded` → `RecipeVariationUnrepresentableEdit` →
`variationNeedsReview`. (Worse: added lines whose section is new are skipped by the `guard` in the
add-op loop, so only the *section* is reported, not the lines.)

The colon rule makes a header **expressible in the editor**; it does not make it **representable in the
delta**. Two ways out, and this ADR does not close them — they are ADR-0021's to decide:

- **(a) Extend the delta vocabulary with section ops** (`addSection(name:afterLineID:)`, `renameSection`).
  Structurally honest, matches the storage grain this amendment just reaffirmed. **Recommended.**
- **(b) Derive the variation delta from the flat serialization instead of the structures.** Only viable
  because the folded variation view is display-only (no section rows need identity preservation), but it
  gives up the `baseIngredientID` anchoring that lets a delta survive a changed base. **A real trade, not a
  shortcut.**

**The ADR-0014 → ADR-0021 Amd1-D5 dependency therefore survives this amendment.** What changed is that it is
now precisely scoped: it needs a delta-vocabulary decision, not a text-editing-model decision.

### Still open

- **Escape hatch for a literal trailing colon.** The quantity guard covers the common case; a deliberate
  `Reduce by half:` -style ingredient line still becomes a section. Accept it (the fix is to edit the text),
  or add an escape (`\:`)? **Unresolved — decide before slicing.**
- **Instruction sections.** Instruction step text is blank-line-joined and steps routinely contain colons
  mid-prose. The colon rule as written is **ingredient-only** until someone specifies the instruction variant;
  instruction sections keep explicit card names.

### Sequencing

Unchanged from the original ADR (**D3 → D2 → Amd1**), with one addition: `normalize-recipe` must now also
leave trailing colons alone — stripping or re-casing them would silently restructure a recipe.
