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
4. See imported photos at **display resolution** (full-resolution original retained),
   with recipe detail presenting low- and high-res imports consistently.
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
- Image fidelity per ADR-0005: full-resolution storage + consistent detail display.
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
  RecipeCore.swift               # RecipeRepository.importBundle: idempotent upsert,
                                 #   import-session tagging for rollback (Slices 1, 3)
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
  Store it as a loose column on `Recipe` (e.g. `importIdentity: String?`) or a small
  `recipeImportRef` side table — Codex picks the simpler one and flags it; either way
  it is provenance, not a unique index (CloudKit law 3).

On re-import, a matched recipe is **reported as already-imported and skipped by
default** (no field overwrite — the user may have edited it). "Update from source" is a
later, reviewable affordance, not an automatic overwrite.

## The slices (each is one PR into `main`)

`main` is protected — every slice is a branch + PR, small enough to review in one
sitting, green at merge (build + tests). Tick the box in the slice PR that completes it.

- [ ] Slice 0 — Grocery dangling-source tests (audit fold-in)
- [ ] Slice 1 — Re-import identity + idempotency
- [ ] Slice 2 — Parser fidelity: rating, difficulty, ingredient sections
- [ ] Slice 3 — Review-before-commit + rollback
- [ ] Slice 4 — Image fidelity (full-res + consistent detail)
- [ ] Slice 5 — Land the real library + committed sanitized fixture

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

### Slice 3 — Review-before-commit + rollback

Replace parse→import→summary with parse→**review**→commit/cancel. A
`RecipeImportModel` (`@Observable @MainActor`, `Destination`-driven) holds the parsed
result and per-recipe status (new / already-imported / warning); the view previews and
offers **Commit** or **Cancel** (cancel writes nothing). Commit tags rows with an
**import-session id** so the whole batch can be **rolled back** as a unit (an Undo
affordance on the post-commit summary). Identity-preserving writes throughout; rollback
deletes only that session's inserted rows. **Tests:** cancel writes nothing; commit then
rollback returns row counts to baseline; rollback of session A leaves session B intact.
**Done when:** no import mutates the library without an explicit commit, and a commit is
reversible.

### Slice 4 — Image fidelity (ADR-0005)

Follow ADR-0005 through: retain the **full-resolution** original bytes (prefer the
PhotoSwipe gallery source over the small cover thumbnail — already chosen), generate
display/thumbnail derivatives via the **pure** `RecipePhotoProcessing` pipeline, and
reconcile recipe-detail presentation so low-res and high-res imports look intentional
(no jumpy layout). Preserve provenance: source path, dimensions, checksum. Missing
images still never fail a recipe. **Tests:** processing pipeline (resize/derivative)
over fixture image bytes; provenance retained; a recipe with a missing referenced image
imports with a warning. **Done when:** imported photos display crisply and detail is
visually consistent across resolutions.

### Slice 5 — Land the real library + committed sanitized fixture

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
  plain ingredient line (preserve over interpret).
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
3. **Import identity storage:** loose `Recipe.importIdentity` column vs a
   `recipeImportRef` side table — confirm you're fine letting Codex pick the simpler
   one in Slice 1 and flag it in the PR. **Recommend:** yes, Codex's call, provenance
   not a unique index.
4. **Already-imported policy:** confirm matched recipes are **skipped, never
   overwritten** (edits are sacred); "update from source" is a later reviewable feature.
   **Recommend:** confirm skip-by-default.

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
