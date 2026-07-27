# Effort: Playbook edit grain — one row editor, and Serve With becomes rows (2026-07-26)

**Type:** App-layer component extraction (Dispatch 1) + a synced-table decomposition with migration
(Dispatch 2). **Dispatch 1 has no schema; Dispatch 2 does.**
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Dispatch 1 ready. Dispatch 2 ready but sequenced behind it** — see Sequencing.

**Read before starting:** [ADR-0048](../decisions/ADR-0048-playbook-edit-grain.md) in full, then
[ADR-0040](../decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) (the rule this implements), then
`CURRENT_HANDOFF.md` Verification Pattern. The core reframe, which the dispatch must not undo: **the three
different edit interactions are an accurate readout of three different storage grains.** Do not unify by
making the chrome uniform over blob storage.

---

## The findings that shape this dispatch

### Finding 1 — ADR-0048 OQ1 is **answered by the code**: multi-line already works

The open question was whether Reader Feedback's paragraph-length bodies would fit the Learnings pattern.
They do — `LearningRow` already uses `TextField("Learning", text: $draft, axis: .vertical).lineLimit(2...6)`
([`MenuPrepPlanEditingViews.swift`](../../YesChefApp/MenuPrepPlanEditingViews.swift)). The shared component
needs no new capability for prose. **OQ1 closed; do not re-open it during S1.**

### Finding 2 — but `RecipeNote` has **no `sortOrder`**, so Reader Feedback cannot reorder

`RecipeNote` is `{id, recipeID, text, noteType, dateCreated, dateModified, cookingSessionID, pinned}`
([`Models.swift:855`](../../YesChefPackage/Sources/YesChefCore/Models.swift)) — no ordering column. So:

**Reorder is an opt-in capability of the shared component, not an assumption.** Learnings has it (sparse
ranks), Serve With will have it (Dispatch 2), Reader Feedback does **not**. Passing a `nil` reorder handler
must cleanly omit `.reorderable()` / `.reorderContainer`, not degrade or crash.

**Do not add `sortOrder` to `RecipeNote` to make the shape uniform.** That is schema with no requirement
behind it — nobody asked to reorder reader feedback.

### Finding 3 — Reader Feedback today is a **bulk** edit mode; converting it is a net deletion

`readerFeedbackView` ([`RecipePlaybookView.swift:349`](../../YesChefApp/RecipePlaybookView.swift)) has one
`Edit`/`Done` button that flips **every** note into a `TextEditor` at once, backed by a
`readerFeedbackDrafts` dictionary committed in bulk on Done. Adopting per-row editing deletes
`isEditingReaderFeedback`, `readerFeedbackDrafts`, `readerFeedbackDraftBinding(for:)` and
`commitReaderFeedbackEdits(_:)` outright. **The slice removes more code than it adds** — expect that, and
treat a growing diff as a signal something was misread.

### Finding 4 — `LearningRow`'s provenance badge must be injected, not inherited

`LearningRow` renders a hardcoded `Label("Hand-authored", …)` when `provenance == .inApp`. In a shared
component that becomes an **optional caller-supplied badge**. (Note, recorded in ADR-0048 and *not* fixed
here: `LearningProvenance` is `{externalHandoff, inApp}` — transport, not authorship — so hand-authored
learnings and in-app model output both land on `.inApp`.)

---

# DISPATCH 1 — the shared row editor (app layer only; **no schema**)

## SLICE S1 — extract the row editor; Reader Feedback adopts it

1. **Extract** the `LearningsSection` / `LearningRow` interaction into one generic component: inline
   tap-to-edit (`TextField`, `axis: .vertical`), swipe-to-delete, **optional** add affordance, **optional**
   reorder (Finding 2), **optional** provenance badge (Finding 4).
2. **Learnings keeps behaving exactly as today** — same reorder, same badge, same add flow. This is a
   refactor for Learnings and a behavior change only for Reader Feedback.
3. **Reader Feedback adopts it**, losing the Edit/Done bulk mode (Finding 3). Delete is per row, edit is per
   row, no reorder.

**Acceptance:** Learnings is visually and behaviorally unchanged. Reader Feedback edits one note at a time
with no mode toggle and no `TextEditor` box. The four bulk-edit members listed in Finding 3 no longer exist.

## SLICE S2 — `ServeWithCoding.decode` becomes loud

```swift
return (try? JSONDecoder().decode([ServeWithItem].self, from: data)) ?? []
```

A malformed blob presents as **"no Serve With items"**, indistinguishable from a recipe that never had any.
Make the failure observable rather than swallowed. **This ships ahead of Dispatch 2 deliberately** — it is
the read path the migration itself runs through, so it must be trustworthy *before* the migration, not after.

**Acceptance:** a corrupt blob surfaces as a reported failure, not an empty list; an absent blob (`nil`) is
still a legitimate empty list, not an error.

---

# DISPATCH 2 — Serve With becomes rows (**schema**; sequenced after Dispatch 1)

## Sequencing (binding)

Dispatch 1 lands first. S1 produces the component Serve With will adopt, and S2 makes the migration's read
path trustworthy. Running the migration before S2 means a silently-empty decode migrates a recipe's Serve
With into **nothing**, with no signal — the exact failure S2 exists to expose.

## SLICE S3 — `recipeServeWith`

**Why at all:** `ServeWithItem` is `Identifiable` with a `UUID` and lives inside `Recipe.serveWith: Data?` —
identity without a row. `reconciledServeWithItems`
([`RecipeEnrichment.swift:380`](../../YesChefPackage/Sources/YesChefCore/RecipeEnrichment.swift)) exists
solely to carry those UUIDs across whole-blob rewrites by matching `title == && note ==`, so **editing an
item's title silently mints a new UUID and drops its identity**. This slice deletes that function.

1. **Table** — `@Table("recipeServeWith")`: `id`, `recipeID`, `title`, `note`, `sortOrder`, `provenance`,
   `dateCreated`, `dateModified`.
   - **`sortOrder` is sparse**, reusing `LearningOrdering.rankStride` (1024). A human moves one item at a
     time across synced devices; a reorder must update only the moved rows. The `Learning` comment is
     explicit that this is a deliberate sync-conflict tradeoff, not a free choice.
   - **`provenance` is its own enum**, expressing **model-suggested vs hand-authored**. Do **not** reuse
     `LearningProvenance` — it is `{externalHandoff, inApp}`, which records *transport*, and both of its
     cases are model paths. It would stamp `inApp` on a hand-typed dish and answer the wrong question.
2. **Migration** in `Schema.swift` (`migrator.registerMigration`): decode each recipe's blob → insert rows
   with sparse ranks and `provenance = .model` → stop reading the column.
3. **Register in `CloudSync.swift`**'s tables list, alongside `RecipeNote.self` / `Learning.self`. Add to the
   **prod-schema promotion list** in `CURRENT_HANDOFF.md` in the same PR.
4. **Delete `reconciledServeWithItems`.**
5. **Serve With adopts the S1 component** — inline edit, swipe delete, reorder (it has ranks), provenance
   badge.

### ⚠️ The regeneration path is this slice's primary test, not a detail

Serve With is regenerated wholesale by its verb. **If regeneration deletes and re-inserts the group, the
table reproduces exactly the identity loss this slice exists to remove** — fresh UUIDs, fresh ranks, and
every hand-authored item and every hand ordering destroyed. So regeneration **upserts by identity and
preserves hand-authored rows and their ranks**; new suggestions take fresh sparse ranks at the end. Provenance
is what makes "which rows are the cook's" answerable — the two design choices are one, not two.

**Acceptance:** a recipe with existing Serve With items migrates with its item ids intact; editing an item's
title preserves its id (the old blob path did not); regenerating the section **keeps** a hand-authored item
and its position; reordering updates only the moved rows.

**Verification note:** schema + sync means this one genuinely wants Jon's two-device device pass before it is
called done — do not close it on a green build.

---

## Explicitly out of scope

- **Make Ahead and Chef It Up.** ADR-0048 D4 keeps them prose: no per-item identity, no per-item consumer,
  nothing anchored to their lines. They only *look* like lists because `PlaybookEnrichmentDisplayText` splits
  multi-line strings at render time. **Do not decompose them on this effort's momentum**
  ([[withdraw-not-defer-orphaned-schema]]); revisit only when a real per-item consumer exists.
- **Adding `sortOrder` to `RecipeNote`** (Finding 2) — schema with no requirement behind it.
- **Fixing `LearningProvenance`'s transport/authorship conflation** (Finding 4). Real, recorded in ADR-0048,
  and a different table's problem.
- **The menu's Playbook sections.** ADR-0041 scoped deliberately to the recipe; the menu equivalent is
  already a separate parked follow-on in `CURRENT_HANDOFF.md`.
