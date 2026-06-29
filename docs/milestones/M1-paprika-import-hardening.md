# Milestone 1 — Paprika import hardening + landing the real library

*Build order for Codex. Architect/editor-in-chief: this doc is the contract; the
strategic arc is in [../implementation-plan.md](../implementation-plan.md) (Phase B),
the conformance baseline in
[../reviews/AUDIT-2026-06-27-main-conformance.md](../reviews/AUDIT-2026-06-27-main-conformance.md),
the format notes in [../IMPORT_EXPORT.md](../IMPORT_EXPORT.md), and the house rules in
`/Users/jon/code/jon-platform/docs/ios/`. Where this doc and those conflict, stop and
flag it — don't silently diverge.*

## The milestone in one sentence

Turn the Paprika **import spike** into a **trustworthy, idempotent, reviewable** flow —
re-running an import never duplicates, the user reviews before anything is committed,
recoverable fidelity (rating/difficulty/sections/images) is no longer dropped — so
Jon's **real library lands cleanly** and the data is worth keeping permanently.

## Why this is M1 (and why it gates sync)

Per [../implementation-plan.md](../implementation-plan.md), sync is a **one-way gate**:
the first time CloudKit is enabled, every duplicate or malformed import propagates to
all devices and the private iCloud zone, and is painful to purge. So the real library
must be **clean and idempotent before sync**, and this milestone is what makes that
true. It is the right M1 because:

- **The foundation is already clean.** The 2026-06-27 audit found no architecture debt
  to pay down first; Phase A collapsed to a single tests-only slice (Slice 0 here).
- **It builds on a working spike, not a blank page.** Parse → bundle → import → summary
  already exists (`PaprikaHTMLImport.swift`, `RecipeRepository.importBundle`,
  `RecipeModels` import flow). This milestone hardens it; it does not reinvent it.
- **It is gated on data we actually have.** `/Users/jon/code/PaprikaExport` is the real
  HTML export. The milestone is specified against real recipes, not guesses.

## Definition of done

A reviewer can, in the running app:

1. Pick the real Paprika HTML export and see a **review** screen *before* any write:
   per-recipe rows marked **new** vs **already imported**, with parse warnings
   (missing images, unmatched index links) surfaced — and **cancel** leaves the library
   untouched.
2. Commit the import, then **run the same import again** and see every recipe reported
   as already-imported with **zero duplicate rows** created.
3. See recovered fidelity that the spike dropped: **rating**, **difficulty**, and
   ingredient **section headings** (e.g. `CHICKEN`, `SAUCE`) materialized as real
   `IngredientSection`s — with `originalImportText` still preserved whole.
4. See imported photos at the **canonical display tier** (processed from the high-res
   gallery source, not the cover thumbnail — full-res originals stay deferred per
   ADR-0005 §5), with recipe detail presenting low- and high-res imports consistently.
5. Undo a just-committed import (**rollback**) and confirm the library returns to its
   prior state.

Invariants that must hold at merge:

- `swift test --package-path YesChefPackage` green; new behavior covered by tests over
  a **committed, sanitized** fixture derived from the real export.
- **Idempotency is tested:** importing the same fixture twice yields the same row count
  as importing it once (per entity: recipes, sections, lines, photos, joins).
- House stack honored: observed reads, identity-preserving writes, pure repository
  functions called by `@Observable` models, persisted enums, `@CasePathable`
  `Destination`. No SQL in the app target.
- No `database.read`-in-`.task`; no delete-all/reinsert; `originalImportText` and
  `originalSnapshot` (the `RecipeBundle`) never lossy.

## In scope

- Re-import identity + idempotency (the keystone).
- Review-before-commit and rollback of a committed import.
- HTML parser fidelity recovery: rating, difficulty, ingredient section promotion.
- Image fidelity per ADR-0005: high-res gallery source → canonical display tier
  (originals deferred, §5) + consistent detail display.
- Landing the real library and committing a sanitized multi-recipe test fixture.
- Slice 0: the audit's one "now" residual — grocery dangling-source tests.

## Out of scope — with destinations

| Deferred | Goes to | Why not now |
|---|---|---|
| `.paprikarecipes` **full** backup import (rating/nutrition/photos from JSON) | **M-later**, gated on Jon providing a real backup | No backup sample on disk; HTML export is richer than first documented and is what we have real data for. Backup stays a **created-date supplement** (already built) until a sample exists |
| Source/author/book cleanup from Paprika categories/tags | **M-later** | Needs a reviewable suggestion UI; ambiguous labels must not be silently converted (IMPORT_EXPORT §2.10) |
| Source refresh / better-image recovery from source URLs | **M-later** | Needs a source-page scraper; separate research milestone |
| Authenticated source capture (ATK, Milk Street) | **M-later** | User-controlled auth + sanitized fixtures; never store credentials |
| Nutritional-info storage | **this milestone, parse-and-preserve only** | `Recipe` has no nutrition field; preserve raw in `originalImportText`, add a typed field only if Slice 2 shows it reliably populated (see Decisions) |
| Dedup-on-read for name-unique entities; `menuItems.recipeID` second FK | **sync / Family Cookbook milestones** | Audit findings 1 & 2 — correctly parked, not this milestone |
| CloudKit sync enablement | **next milestone (Phase C)** | This milestone is the gate that must close first |

## Architecture & module layout

No new module boundaries. Work lands in the existing seams:

```
YesChefPackage/Sources/YesChefCore/
  PaprikaHTMLImport.swift        # parser fidelity (Slice 2); import-identity key (Slice 1)
  RecipeRepository+Import.swift  # importBundle find-or-skip + identity (Slice 1);
                                 #   read-only preview/classify + rollback of a commit's
                                 #   inserted-ID set, no session table (Slice 3)
  RecipePhotoProcessing.swift    # full-res + derivative pipeline (Slice 4)
  GroceryCore.swift              # (Slice 0 touches tests only, not this file)
YesChefApp/
  RecipeModels.swift             # RecipeImportModel: review state, commit/cancel,
                                 #   rollback (Slice 3) — @Observable, Destination-driven
  PaprikaImportWorkspace.swift   # file access; parse off the main actor (exists)
  + a review/commit view         # replaces import-then-summary (Slice 3)
```

Boundary rule holds: parsing, identity, and image processing are **pure core**;
file-system/security-scoped access and presentation stay in the app target behind the
existing dependency seams. Repository functions remain `static func …(in db: Database)`,
called by the model.

## The keystone: re-import identity (design note)

The real HTML export carries **no stable Paprika UID** (verified on real data — no
`uid`/`data-`/`meta`). So import identity is a **composed key**, reusing the matching
the backup supplementer already does:

- **Primary key:** normalized source URL + normalized title.
- **Fallback (no source URL):** normalized title alone, but a title-only match is
  **weaker** — on collision, treat as *new* and warn rather than silently merging
  (preserve-data-over-magic).
- Persist the chosen key as **provenance** so a re-import is a lookup, not a re-derive.
  Store it in a small **`recipeImportRef` side table** keyed to recipe (confirmed with
  Jon 2026-06-28) — keeps `Recipe` clean and isolates import provenance. It is
  provenance, **not a unique index** (CloudKit law 3): a lookup-then-decide, never a DB
  constraint.

On re-import, a matched recipe is **reported as already-imported and skipped by
default** (no field overwrite — the user may have edited it). "Update from source" is a
later, reviewable affordance, not an automatic overwrite.

## The slices (each is one PR into `main`)

`main` is protected — every slice is a branch + PR, small enough to review in one
sitting, green at merge (build + tests). Tick the box in the slice PR that completes it.

Each slice carries a **reasoning hint** for the executor (`reasoning: high | xhigh`).
The architect writes a tight enough contract that **`high` is the default**; `xhigh` is
reserved for slices with genuine design judgment or invariant risk — schema migrations,
concurrency/actor correctness, idempotency/sync invariants, or heuristics with real-data
edge cases. Spend the extra reasoning on the spec and the review, not on grinding a
well-specified slice.

- [x] Slice 0 — Grocery dangling-source tests (audit fold-in)
- [x] Slice 1 — Re-import identity + idempotency
- [x] Slice 2 — Parser fidelity: rating, difficulty, ingredient sections *(was secretly
  `xhigh`-shaped — the all-caps real-data edge case)*
- [x] Slice 3 — Review-before-commit + rollback — `reasoning: high`
- [x] Slice 4 — Image fidelity (full-res + consistent detail) — `reasoning: high`
- [ ] Slice 5 — Land the real library + committed sanitized fixture — `reasoning: high`

### Slice 0 — Grocery dangling-source tests

The audit's only "now" residual (finding 3). `groceryItemSources` models recipe/menu/
placement/calendar origins as **loose UUIDs with no cascade**, so deleting a referenced
entity leaves a dangling origin the repository must tolerate on read. Pin that with
tests. **Tests:** add a recipe that contributes to a grocery row, delete the recipe,
assert the grocery row + its remaining sources degrade gracefully (no crash, no orphan
surfaced as a live source); same for a deleted menu/placement. **Done when:** the
loose-UUID tolerance is covered; no production code change required (or a minimal
read-side guard if a test exposes a gap).

### Slice 1 — Re-import identity + idempotency

Implement the composed import key above. `importBundle` becomes **find-or-skip**: look
up the key; if matched, skip and report already-imported; if new, insert as today.
**Tests (the gate):** import the fixture, assert N recipes; import it again, assert
**still N** — per entity (recipes, sections, lines, photos, joins), no duplicates.
Title-only collision → new + warning. **Done when:** double-import is a no-op on row
counts and the summary distinguishes new vs already-imported.
**Fixture:** reuse the existing `Tests/.../Fixtures/PaprikaHTML/SyntheticExport`; extend
it minimally for the two identity branches this slice needs — one recipe **with** a
source URL (strong key) and a **title-only collision** pair (same title, no/empty source
URL → second imports as *new* + warns). The full sanitized real-shape fixture is Slice 5,
not this slice.

### Slice 2 — Parser fidelity: rating, difficulty, ingredient sections

Extend `PaprikaHTMLImport` to recover what real exports contain but the spike drops:
`itemprop="aggregateRating"` → `Recipe.rating`; difficulty → `Recipe.difficulty`;
and promote ingredient **section headings** — a `recipeIngredient` paragraph with **no
`<strong>` quantity** that is all-caps or colon-terminated (real data: `CHICKEN`,
`SAUCE`) — into real `IngredientSection` names, with following lines assigned to that
section. `originalImportText` keeps the whole raw page regardless. Nutrition: **parse
and preserve raw** only (see Decisions before adding a typed field). **Tests:** over the
sanitized fixture — rating/difficulty populate when present and stay nil when absent;
the multi-section recipe yields the expected sections; a recipe with no headings yields
one default section unchanged. **Done when:** recovered fields appear in detail and are
tested, with nothing over-interpreted.

### Slice 3 — Review-before-commit + rollback — `reasoning: high`

Replace parse→import→summary with parse→**review**→commit/cancel. Today the whole flow
lives inside `RecipeLibraryModel.paprikaExportSelected` (`YesChefApp/RecipeModels.swift`):
it parses, builds bundles, calls `RecipeRepository.importBundles` **immediately**, then
shows a post-hoc `.importSummary`. There is no review gate and no rollback. This slice
inserts the gate and makes a commit reversible.

**Grounding (what S1 already gives us — build on it, don't reinvent):**
- `importBundles` is **find-or-skip** and returns a `RecipeImportBatchResult`: per-recipe
  `outcome` (`imported` / `alreadyImported`), `warnings`, and **`importedIDs`** (exactly
  the recipes a commit inserts). `makeRecipeBundle` **pre-allocates every child ID**
  (sections, lines, photos, source, notes) under the recipe ID. So "what a commit
  inserted" is fully determined by its `importedIDs` plus those recipes' child rows —
  **no session bookkeeping table is required.**
- Classifying new-vs-already-imported is a **read** against existing `recipeImportRef`s
  (the composed identity key), not a trial write.

**The review step (read-only preview).** Add a pure classifier that, given the parsed
bundles and the existing `RecipeImportRef`s, returns per-recipe status (new /
already-imported / title-only-collision) **without writing**. Reuse the single import-key
home from S1 — do not re-derive the key here. `RecipeImportModel`
(`@Observable @MainActor`, `Destination`-driven) holds the parsed result + the preview and
renders per-recipe rows with parse/identity warnings surfaced. **Cancel writes nothing.**
The read must follow the house rule — **no `database.read` inside `.task`**; classify via
the injected db seam the model already uses.

**Commit.** On Commit, call the existing `importBundles` (identity-preserving writes,
unchanged) and present the post-commit summary that exists today. The summary carries the
batch's `importedIDs` so it can offer **Undo**.

**Rollback (Undo).** Rollback is an **undo of an insert**, not a user deletion of a real
recipe — so it **hard-deletes** exactly the committed batch's inserted rows (the
`importedIDs` recipes + their child rows + the `recipeImportRef`s created for them), unlike
the normal recipe-delete flow which **archives** (`RecipeRepository.archive`). It must
return per-entity counts to the pre-commit baseline. Disjoint batches are independent by
construction (disjoint `importedIDs`), so rolling back batch A cannot touch batch B.
Downstream loose references (a grocery/menu origin pointing at a rolled-back recipe)
**degrade gracefully** — that is the Slice 0 contract, already tested; rollback does not
need to chase them.

**Why no import-session column** (correcting the original "tag rows with a session id"
sketch): the inserted-ID set already identifies a batch precisely, an Undo is a
same-session post-commit affordance, and adding a persisted session id is a model change
with migration cost for no done-criteria benefit (AGENTS.md: preserve data, avoid
premature migration; ask before persistent model changes). Durable import-session
provenance, if it ever earns its place (a "manage imports" screen), is its own ADR — not
this slice.

**Tests:** cancel writes nothing (counts unchanged); the preview classifies a fixture
with a new recipe, an already-imported recipe, and a title-only collision correctly with
**zero writes**; commit then rollback returns every entity count to baseline; rolling back
batch A leaves batch B intact; a rolled-back recipe that fed a grocery row leaves the
grocery row degrading gracefully (no crash). **Done when:** no import mutates the library
without an explicit commit, and a commit is reversible to the exact prior row counts.

---

#### Handoff refinement — 2026-06-29 (dispatch-ready; the dependency flipped)

This slice was originally specced to *precede* M2 and hand M2 its review pattern. Execution
inverted that: M2 shipped first and built the review-before-commit model this slice needs.
**So M1 S3 is now a "mirror the proven template, add batch + rollback" job, not a greenfield
one.** Read M2's `RecipeCaptureModel` before writing anything.

**The template to mirror — `RecipeCaptureModel` (`YesChefApp/RecipeModels.swift:182`).**
It is the shape the new `RecipeImportModel` must follow:
- `@Observable @MainActor final class`, `Destination`-driven on the owning `RecipeLibraryModel`.
- Dependencies as `@ObservationIgnored @Dependency` seams only: `\.date.now`,
  `\.defaultDatabase`, `\.uuid`. No I/O in `init`, no `database.read` in `.task`.
- **Preview is a held value, commit is the only write.** Capture holds a `draft`
  (`WebRecipeCaptureDraft?`) and exposes `canCommit`; `commitButtonTapped()` is the *only*
  path that opens `database.write`, calling a repository method and returning the result.
  Cancel/`reset()` writes nothing. Import mirrors this exactly — the held value is a batch
  preview instead of a single draft.

**Exact boundaries (what to touch, what not to):**
- **Replace** the eager path in `RecipeLibraryModel.paprikaExportSelected`
  (`YesChefApp/RecipeModels.swift:75`) — today it parses and calls `database.write { … importBundles … }`
  immediately (~line 88), then shows `.importSummary` post-hoc. Re-route: parse → build
  preview → present `RecipeImportModel` for review → commit on explicit action. The existing
  `.importSummary` destination stays as the *post-commit* summary, now carrying Undo.
- **New pure classifier in YesChefCore** (alongside `RecipeRepository+Import.swift`): given the
  parsed bundles + existing `RecipeImportRef`s, return per-recipe status
  (new / already-imported / title-only collision) with **zero writes**. Reuse the single
  import-key home from S1 — do **not** re-derive the key. This is the read-only preview;
  `importBundles` (`RecipeRepository+Import.swift:89`, returns `RecipeImportBatchResult` with
  `importedIDs` at `:60`) is the commit, unchanged.
- **New rollback method on `RecipeRepository`** — hard-delete a batch's `importedIDs` recipes
  + their pre-allocated child rows + the `RecipeImportRef`s created for them, returning counts
  to baseline. **Contrast it explicitly with `RecipeRepository.archive`
  (`RecipeCore.swift:399`)**, which is the soft user-delete path; rollback is an undo-of-insert
  and must be a true hard delete. Disjoint batches → disjoint `importedIDs`, so independence is
  by construction.

**Commit-API contrast to keep straight:** capture commits a *single* recipe via
`importCapturedRecipe` → `RecipeImportBundleResult`; import commits a *batch* via
`importBundles` → `RecipeImportBatchResult`. Same `@Dependency`/`@Observable`/commit-on-write
structure, different cardinality and the added classifier + rollback. Don't collapse the two
models; mirror the structure.

**No persistent model change.** No import-session column (decided above) — the `importedIDs`
set identifies the batch precisely. AGENTS.md: ask before persistent model changes; none is
needed here.

**Verify locally (CI is disabled on this repo — billing):** `swift test --package-path
YesChefPackage` green; `bash scripts/check-drift.sh` green; `xcodegen generate` clean;
`xcodebuild -scheme YesChef -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M4)'
-skipMacroValidation build` green; `git diff --check` clean. `reasoning: high`.

### Slice 4 — Image fidelity (ADR-0005) — `reasoning: high`

Follow ADR-0005 through. **Reconciled with ADR-0005 §5 (2026-06-29):** "full resolution"
here means **process from the high-res PhotoSwipe gallery source** (over the ~280×280
cover thumbnail — already chosen) **into the canonical display tier** — *not* storing a
pristine original blob. ADR-0005 §5 defers full-resolution originals; the display tier is
the synced canonical image, so **no new originals column and no migration.** Generate
display/thumbnail derivatives via the **pure** `RecipePhotoProcessing` pipeline at the
ADR-0005 §4 budget (≈1600px longest edge / ~300 KB default; use the **larger budget for
text-heavy/reference photos** where readability matters — ADR-0005 §4 + Consequences).
Reconcile recipe-detail presentation so low-res and high-res imports look intentional (no
jumpy layout). Preserve provenance on the **existing** `RecipePhoto` fields
(`originalSourcePath`, `sourceURL`, `pixelWidth`/`pixelHeight`, `checksum`) — they already
exist, so this is fidelity recovery, not a schema change. Missing images still never fail
a recipe. **Tests:** processing pipeline (resize/derivative) over fixture image bytes;
provenance retained; a recipe with a missing referenced image imports with a warning.
**Done when:** imported photos display crisply at the canonical display tier and detail is
visually consistent across resolutions.

### Slice 5 — Land the real library + committed sanitized fixture — `reasoning: high`

Run the full real `/Users/jon/code/PaprikaExport` through end to end. Commit a small,
**sanitized** multi-recipe fixture into the test target covering the real shapes:
simple single-section; multi-section (`CHICKEN`/`SAUCE`); source-mapped
(cooksillustrated.com → Cook's Illustrated); unicode title (the Chinese-character
recipes); gallery vs cover-thumbnail image; and a partial/missing-image case. **Tests:**
the fixture exercises Slices 1–4 together (parse → review → idempotent commit →
fidelity → images). **Done when:** the real library imports cleanly and idempotently,
and the committed fixture guards every behavior this milestone adds.

## Constants register (pre-justified — jon-platform "constants need a rationale")

- **Import identity key = normalized(sourceURL) + normalized(title); fallback
  normalized(title).** The HTML export carries no stable UID (verified on real data),
  and this is exactly the match the `.paprikarecipes` supplementer already uses to
  backfill dates — one matching rule, reused. Title-only is the weak fallback and warns
  on collision.
- **Section-heading heuristic = a `recipeIngredient` line with no `<strong>` quantity
  that is all-caps or colon-terminated.** Derived from the real export
  (`itemprop="recipeIngredient">CHICKEN</p>`), not guessed. Anything ambiguous stays a
  plain ingredient line (preserve over interpret). **Refinement (Slice 2, from real
  data):** when *every* ingredient line in a recipe is uppercase, casing carries no
  signal — a fully-uppercased export (real, e.g. the Garlicky Traybake) would otherwise
  promote ordinary lines like `KOSHER SALT AND GROUND BLACK PEPPER`. So the all-caps
  branch is suppressed for fully-uppercased lists; colon-terminated headings still count.
  The rule lives once in `IngredientSectionHeading.sections(in:)`, shared by Paprika
  import and web capture.
- **Primary image source = first PhotoSwipe gallery image, else `itemprop="image"`.**
  Already chosen in the spike; the gallery source is the higher-resolution original,
  the `itemprop="image"` file is often a ~280×280 cover thumbnail (IMPORT_EXPORT §2.7).
- **Ignored ZIP sidecars = `__MACOSX/`, `.DS_Store`.** Present in real macOS exports;
  must not be parsed (IMPORT_EXPORT §2.2).
- **Source→publication map** (e.g. `www.cooksillustrated.com` → `Cook's Illustrated`):
  the existing deterministic map; extend only with real observed domains, never guess.

## Decisions for Jon to confirm (not Codex's to make alone)

1. **`.paprikarecipes` backup:** export one real backup so a future milestone can lift
   full fidelity (rating/nutrition/photos/created from JSON)? Until then, HTML stays
   primary and the backup stays a created-date supplement. **Recommend:** export it when
   convenient; it does not block this milestone.
2. **Nutrition:** add a typed `Recipe.nutritionalInfo` field now, or preserve raw in
   `originalImportText` until the backup path makes it structured? **Recommend:**
   preserve raw this milestone; add the field with the backup importer, so we model it
   once from the richer source.
3. **Import identity storage:** ~~loose column vs side table~~ **CONFIRMED 2026-06-28 —
   `recipeImportRef` side table** keyed to recipe; provenance, not a unique index.
4. **Already-imported policy:** **CONFIRMED 2026-06-28 — skip, never overwrite.** Matched
   recipes are reported as already-imported and skipped; no field overwrite (edits are
   sacred). "Update from source" is a later, reviewable feature.
5. **Rollback storage (Slice 3):** an Undo of a commit hard-deletes the batch's inserted
   rows, identified by the `importedIDs` set the commit already returns — **no persisted
   import-session column.** A durable session id would be a model change with migration
   cost and no done-criteria benefit. **Recommend:** ship Slice 3 without it; if a
   "manage imports" view ever needs durable session provenance, that earns its own ADR.
   Flagged here rather than decided silently — say the word if you'd rather pay for the
   durable session id now.

## Working agreement

- Each slice: branch → PR → merge (`main` protected; self-merge per the collaboration
  protocol). Commits end with the Co-Authored-By trailer; PR bodies end with the Claude
  Code trailer.
- Tests with swift-testing + CustomDump; control date/uuid/db via `@Dependency`; the
  idempotency test is the milestone's load-bearing assertion.
- Surface any new constant in the PR description per the register above — flag, don't
  bury.
- Blocked or spec looks wrong → write it in the PR, label `question-for-architect`;
  don't silently diverge.
