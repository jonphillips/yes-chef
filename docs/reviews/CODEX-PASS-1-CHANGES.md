# Code Review — Codex Pass 1: Required Changes

Review date: 2026-06-16. Reviewer: Claude Code.
Scope: `YesChefPackage/Sources/YesChefCore/*`, `YesChefApp/*`, against
`docs/` (PRODUCT_BRIEF, DATA_MODEL, AGENTS, ADRs) and `~/code/jon-platform`
(`AGENTS.md`, `docs/ios/*`).

This document is the **change list** — divergences from the established approach
and a few things that are egregious enough to fix before we build further. A
companion doc, [CODEX-PASS-1-KEEP-AND-ALIGN.md](CODEX-PASS-1-KEEP-AND-ALIGN.md),
covers what Codex got right and the handful of decisions we should ratify in the
shared docs.

Severity key: **P0** = wrong/breaks now or bakes in expensive rework · **P1** =
diverges from house style, fix before more code lands on top · **P2** = polish.

---

## P0 — Fix now

### P0-1. The whole read path fights SQLiteData's observation model (this is your `CancellationError`)

**Where:** `RecipeDetailView.swift:60` + `:196`, `CookingModeView.swift:93` +
`:109`, `RecipeEditorView.swift:81` + `:91`.

Every detail-style screen does the same thing: declare `@State var detail:
RecipeDetailData?`, then in `.task` run `try await database.read { ... }` and
stuff the result into that `@State`. That is the imperative pattern SQLiteData
exists to delete, and it produces two visible failures:

1. **Spurious "Could Not Load Recipe — CancellationError()".** `database.read`'s
   async form honors task cancellation. `.task`/`.task(id:)` cancels its body
   whenever the view's identity changes or it disappears — selecting another
   recipe, presenting/dismissing a sheet, or a `@FetchAll` update re-rendering
   the split view. The in-flight read throws `CancellationError`, which
   `loadDetail()`'s `catch` faithfully turns into an alert
   (`RecipeDetailView.swift:201-204`). It is not a real load failure; it is the
   framework cancelling work the code shouldn't be doing by hand.
2. **Stale detail after edits.** Because the data is a one-shot read into
   `@State` keyed on `recipe.id`, editing a recipe (same id) does **not** re-fire
   the task, so the detail pane keeps showing pre-edit ingredients/steps while
   the title (passed as a live `Recipe` value) updates. The two halves of the
   screen disagree.

Both symptoms are one root cause: **manual `database.read` into `@State` instead
of a live query.** Per `jon-platform/docs/ios/persistence-and-sync.md`,
`DATA_MODEL.md §35`, and the `pfw-sqlite-data` skill, composite reads use
`@Fetch` with a `FetchKeyRequest`:

```swift
struct RecipeDetailRequest: FetchKeyRequest {
  let recipeID: Recipe.ID
  func fetch(_ db: Database) throws -> RecipeDetailData? {
    try RecipeRepository.fetchDetail(recipeID: recipeID, in: db)
  }
}

// In the view (or, preferably, the model — see P1-1):
@Fetch var detail: RecipeDetailData?
init(recipeID: Recipe.ID) {
  _detail = Fetch(wrappedValue: nil, RecipeDetailRequest(recipeID: recipeID), animation: .default)
}
```

`fetchDetail` already returns exactly `RecipeDetailData?`, so the repository layer
needs no change — only the call site. This observes the DB, refreshes the detail
automatically on edit, and never surfaces `CancellationError`.

**Required:** replace the `.task`+`database.read`+`@State` trio in
`RecipeDetailView`, `CookingModeView`, and `RecipeEditorView`'s load path with
`@Fetch`/`FetchKeyRequest` (or `$detail.load(...)` driven by `.task(id:)` per the
skill's "dynamic queries" section). At minimum — even if we defer the full
rewrite — wrap reads in `withErrorReporting` and **never** present
`CancellationError` to the user.

> Now a house rule: jon-platform `persistence-and-sync.md` → "Reads are observed,
> never hand-pulled" calls this out explicitly as a bug.

---

### P0-2. The editor destroys structured + multi-section data on every save

**Where:** `RecipeCore.swift:202-293` (`save`), `:334-362` (`replaceChildren`),
and the `RecipeEditorDraft` text round-trip (`:107-140`).

The editor models a recipe as flat text blobs (`ingredientText`,
`instructionText`, `noteText`) and on **every** save:

- re-parses the text and `DELETE`s + re-`INSERT`s all ingredient lines,
  instruction steps, and non-retrospective notes with **fresh UUIDs**
  (`replaceChildren`);
- collapses everything into **one** ingredient section and **one** instruction
  section (`ingredientSectionID`/`instructionSectionID`, `:210-211`), discarding
  any multi-section structure the model is built to hold;
- collapses all notes (makeAhead, freezing, substitution, …) into a **single
  `general` note** (`:253-262`), dropping every other `noteType`;
- regenerates parsed fields (`quantity`/`unit`/`item`/`preparation`/
  `shoppingCategory`/`doNotShop`/`confidence`) from the crude parser, discarding
  any prior structured values.

This violates three settled rules at once:

- **Data preservation** (AGENTS.md priorities #1, #9; DATA_MODEL §2.1/§2.2):
  structured fields, section grouping, and note typing are silently lost on a
  routine edit.
- **Stable IDs** (DATA_MODEL §2.5, §31): delete-all-and-reinsert-with-new-UUIDs
  is the opposite of stable IDs. Once CloudKit sync lands (ADR-0001/0002), every
  trivial edit re-creates every child row on every device — maximal sync churn
  and conflict surface, for an app whose central bet is clean sync.
- **"Structure where useful"** (DATA_MODEL §2.2): the parsed model exists; the
  editor can't see or keep it.

**Resolved (2026-06-16): edit structured rows, not text blobs — see
[ADR-0004](../decisions/ADR-0004-structured-recipe-editor.md).** The blob
shape is replaced, not patched. **Required:**

1. Edit ingredient lines, instruction steps, and notes as real rows that keep
   their UUIDs across edits. Save updates/inserts/deletes **by identity** — no
   wholesale delete+reinsert, so child-row UUIDs stay stable (kills the sync
   churn).
2. Preserve `noteType` and section structure through an edit; never collapse
   multiple sections to one or many note types to a single `general` note.
3. Preserve parsed fields; the parser only fills what it can improve, never
   overwrites a field a prior parse/import or the user already set.
4. Keep the pure functional core (`IngredientParser` etc.) — it feeds row
   creation for pasted-in new content, it does not re-parse-and-replace on save.

Free-text paste stays as an *input affordance* for new content; it just produces
structured rows. See ADR-0004 for the full rationale and rejected alternatives.

---

## P1 — Align before building further

### P1-1. There are no `@Observable` feature models; logic lives in Views

**Where:** `RecipeEditorView.swift:105` (`saveButtonTapped` calls
`database.write` in the view), `MarkCookedView.swift:38`, the load funcs in
`RecipeDetailView`/`CookingModeView`, and `RecipeLibraryView` (owns
`Destination`, search, selection).

The house architecture is **`@Observable` feature models + a `Destination`
enum**, with **non-trivial save/load/reconcile logic living in the model, never
in a View** (`jon-platform/docs/ios/swift-style.md §2`; AGENTS.md "Architecture
Guidance"). Codex put all orchestration in the views and called the repository
directly with `database.write`/`read` from view methods.

The swift-style doc's drafts exception explicitly does **not** cover this: it
allows a *one-line `upsert`* in a view, and warns that "the moment it grows
domain logic (tag reconciliation, association management, derived records),
extract a model." `RecipeRepository.save` does tag reconciliation, association
management, **and** derived records (the snapshot) — the exact named trigger for
extracting a model.

**Required:** introduce `@Observable @MainActor` feature models
(`RecipeLibraryModel`, `RecipeEditorModel`, `RecipeDetailModel`, …) that own the
`@Fetch`/`@FetchAll`, the `Destination`, and the action methods
(`saveButtonTapped`, `markCookedButtonTapped`). Views become bindings + delegation.
`RecipeRepository`'s pure `(…, in db)` functions stay — they're good — but are
called *by the model*, not the view.

> Now a house rule: the repository pattern is ratified in jon-platform
> `swift-style.md` → "Persistence core: repository functions." Pure
> `(…, in db: Database)` functions called *by* the model are the blessed home for
> transaction bodies; keep Codex's `RecipeRepository`, just move the call sites
> off the views.

### P1-2. `Destination` is on the View and uses raw `.sheet`, not swift-navigation

**Where:** `RecipeLibraryView.swift:5-26`, `:75-98`.

The enum-`Destination` instinct is right and naming is correct, but the house
pattern is **one `Destination` per feature model**, driven by **swift-navigation**
(`sheet(item:)` from `SwiftUINavigation`, `@CasePathable`), not a hand-rolled
`Identifiable` enum on the view with a stringly-built `id`. Also,
`swift-navigation` isn't even a package dependency yet
(`Package.swift:14-18` has only sqlite-data, custom-dump, dependencies).

**Required:** add `pointfreeco/swift-navigation`, move `Destination` onto the
library model, make it `@CasePathable`, and drive sheets the house way. This
pairs with P1-1.

### P1-3. Stringly-typed columns where the spec defines enums

**Where:** `Models.swift` — `confidence: String?` (`:157`), `noteType: String`
(`:241`), `RecipePhoto.source: String` (`:290`), `difficulty: String?` (`:20`);
plus `RecipeNoteType` (`:269-283`) modeled as a namespace of `static let`
strings.

DATA_MODEL §25 defines these as real enums (`ParseConfidence`,
`RecipeNoteType`, `RecipeDifficulty`, `PhotoSource`), and the #1 house
non-negotiable is **make impossible states unrepresentable — enums over
stringly-typed values** (`jon-platform/AGENTS.md`, swift-style §3). `RecipeNoteType`
as `static let` strings is the stringly-typed anti-pattern wearing an `enum`
keyword.

**Required:** define real `enum`s conforming to `String`, `Codable`, `Sendable`,
and `QueryBindable` so they persist as their raw value and are still safe in
Swift. This is cheap now and a migration later (typed columns in a synced schema —
schema hygiene, persistence-and-sync.md).

> Now a house rule: jon-platform `persistence-and-sync.md` → schema hygiene →
> "Persisted enums, not stringly-typed columns" spells out the exact recipe.

### P1-4. `originalSnapshot` is a bespoke lossy format, not the transfer bundle the spec mandates

**Where:** `RecipeCore.swift:561-619` (`RecipeBundleCoding`), consumed by
`OriginalSnapshotView.swift`.

DATA_MODEL §2.4 + §2.6 are explicit: the snapshot **reuses the recipe-transfer
bundle serialization — the same format** — a *self-contained* snapshot (Recipe +
sections/lines with parsed fields, instruction sections/steps, notes, photos,
tag/category names) sufficient to **rebuild the recipe with fresh UUIDs**. The
payoff (§2.4, §33.4) is "later, `originalSnapshot` simply becomes version 0 …
with no rework," and the same bundle powers Phase-1 "Send a recipe" (ADR-0003).

Codex's `Snapshot` keeps only `title/subtitle/summary/servingsText/yieldText`,
source name+url, and arrays of raw strings. It **drops** times, servings, cuisine,
course, difficulty, rating, `originalImportText`, all parsed ingredient fields,
section structure, note types/dates, photos, and most source fields. As a display
artifact for "View Original" it limps along; as the transfer bundle the spec says
it must be, it's lossy enough to violate data-preservation on transfer — and it
guarantees the rework §2.4 promised we'd avoid.

**Required:** define one canonical, complete `RecipeBundle` codable (full Recipe
row + children + tag/category names) used for the snapshot now and transfer later.
This is a "got cute with a minimal format" divergence — align it to the spec
before more depends on the snapshot shape.

---

## P2 — Polish / track for later

- **No dedup-on-read for `Tag`/`Category`.** `reconcileTags`/`reconcileCategories`
  (`RecipeCore.swift:368-410`) do case-insensitive find-or-create (good) but don't
  implement the lowest-UUID dedup-on-read cleanup DATA_MODEL §2.6 requires for
  name-unique entities under multi-device sync. Fine pre-sync; flag it for the
  sync milestone and seed duplicates in a test then.
- **`NavigationSplitView` unconditionally.** UI doc wants a size-class-driven
  tab-on-iPhone / split-on-iPad split (`prefersTabNavigation`). Acceptable for
  MVP (collapses to a stack on iPhone) but note it's not the documented pattern.
- **Equipment** has a model, table, and join but no editor/detail surface — fine
  for MVP, just confirm it's intentional.
- **`Package.swift` tools 6.4 vs `project.yml` `SWIFT_VERSION 6.0`** — harmless
  but worth making consistent.
- **`ServingParser`** grabs the first integer in the string (`"Serves 6"` → 6);
  fine, but `"Serves 8-10"` → 8 silently. Acceptable; note as a known limitation.

---

## Quick index of the diagnosis

| Symptom you saw | Root cause | Fix |
|---|---|---|
| `CancellationError()` alert | manual async `database.read` in `.task` (P0-1) | `@Fetch`/`FetchKeyRequest` |
| Detail stale after edit | one-shot read into `@State` (P0-1) | live query |
| (latent) parse/section/note loss on edit | blob re-parse + delete/reinsert (P0-2) | identity-preserving save |
| (latent) sync churn | fresh UUIDs every save (P0-2) | stable IDs |
