# Effort: Playbook edit grain — one row editor, and Serve With becomes rows (2026-07-26)

**Type:** A standing data-loss fix (Dispatch 0) + app-layer component extraction (Dispatch 1) + a synced-table
decomposition with migration (Dispatch 2). **Dispatches 0 and 1 have no schema; Dispatch 2 does.**
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Dispatch 0 ready and should ship on its own, first. Dispatch 1 ready. Dispatch 2 ready but
sequenced behind both** — see Sequencing.

> **Amended 2026-07-29 (architect review).** Three changes, all verified against the code: the loud decode was
> pulled out of Dispatch 1 into its own **Dispatch 0** because it is a live data-loss bug and not merely
> migration prep (Finding 5); S3's migration gained an explicit **determinism requirement**, without which it
> duplicates every Serve With row across devices (Finding 6); and S3 gained a rider not to drop the
> `serveWith` column in the same PR.

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

### Finding 5 — the silent decode is a **read-modify-write** data-loss bug today, not just migration prep

The original framing — a malformed blob "presents as no Serve With items" — is only the *display* consequence.
`ServeWithCoding.decode` also sits on the read side of two paths that immediately **write back**:

| Path | What a failed decode does |
|---|---|
| `replaceServeWithPlan` ([`RecipeEnrichment.swift:361`](../../YesChefPackage/Sources/YesChefCore/RecipeEnrichment.swift)) | decode → `[]` → reconcile against `[]` → `updateServeWith([])`; `encode` returns `nil` for empty, so it **writes `serveWith = nil`** |
| `removeServeWithItem` ([`:372`](../../YesChefPackage/Sources/YesChefCore/RecipeEnrichment.swift)) | decode → `[]` → filter → same write; deleting one item **wipes the whole section** |

So one bad decode becomes *permanent* loss on the user's next action — regenerate or delete-one — with no
migration involved. That is live today. It is why S2 is now **Dispatch 0** and ships on its own rather than
queued behind a refactor.

The acceptance criterion is achievable exactly as written, because `encode` already returns `nil` for an empty
list: **absent** (`nil`) and **corrupt** (non-`nil`, undecodable) are genuinely distinguishable states.

### Finding 6 — S3's migration, as originally written, duplicates every row across devices

S3 said: migrate inside `migrator.registerMigration`, decoding each blob and inserting rows. That is precisely
the shape [[migration-writes-bypass-sync-triggers]] warns about. `Schema.swift` runs the migrator **before**
`makeSyncEngine`, and SQLiteData installs its per-table triggers at engine *construction* — so migration
writes get no `SyncMetadata`. `recipeServeWith` is a **brand-new** table, which is the first of that memory's
two failure modes: at `start()` the engine sweeps new tables wholesale and **each device uploads its own
copy**, so every migrated recipe ends up with duplicated Serve With rows.

**The fix is nearly free, and the data is already in the right shape for it.** `ServeWithItem` is
`Identifiable` with a stable `UUID` ([`Models.swift:171`](../../YesChefPackage/Sources/YesChefCore/Models.swift))
*inside a blob that already syncs*. So every device is migrating identical synced input — derive every column
deterministically from it and the devices converge on identical rows even though nothing uploads, which that
memory states is safe to leave in the migrator. See S3 step 2.

---

# DISPATCH 0 — the loud decode (ship first, on its own; **no schema**)

## SLICE S0 — `ServeWithCoding.decode` becomes loud

*(Was Dispatch 1's S2. Promoted by Finding 5.)*

```swift
return (try? JSONDecoder().decode([ServeWithItem].self, from: data)) ?? []
```

Make the failure observable rather than swallowed. This is a handful of lines, it needs none of S1's component
work, and it should **not** queue behind a refactor — every day it waits is another day a corrupt blob can be
destroyed by the next regenerate or delete-one (Finding 5).

It remains a hard prerequisite for Dispatch 2 for the original reason as well: it is the read path the
migration itself runs through, so it must be trustworthy *before* the migration, not after.

**Acceptance:** a corrupt blob surfaces as a reported failure, not an empty list; an absent blob (`nil`) is
still a legitimate empty list, not an error; and neither `replaceServeWithPlan` nor `removeServeWithItem` can
overwrite a blob it failed to read.

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

*(S2, the loud decode, was promoted out of this dispatch — it is now **Dispatch 0 / S0**. Finding 5.)*

---

# DISPATCH 2 — Serve With becomes rows (**schema**; sequenced after Dispatches 0 and 1)

## Sequencing (binding)

**Dispatch 0 → Dispatch 1 → Dispatch 2.** S0 makes the migration's read path trustworthy; running the
migration before it means a silently-empty decode migrates a recipe's Serve With into **nothing**, with no
signal — the exact failure S0 exists to expose. S1 then produces the component Serve With adopts in step 5.

S0 does **not** depend on S1, which is why it ships on its own and first.

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
2. **Migration** in `Schema.swift` (`migrator.registerMigration`): decode each recipe's blob → insert rows →
   stop reading the column. **⚠️ Every inserted column must be a deterministic function of the already-synced
   blob — no `UUID()`, no `now`** (Finding 6). Concretely:
   - **`id` = the blob item's own `ServeWithItem.id`.** It is already a stable `UUID` and already synced. This
     is the determinism fix *and* it satisfies this slice's own acceptance criterion ("migrates with its item
     ids intact") in the same stroke.
   - **`sortOrder` = blob array index × `LearningOrdering.rankStride`**, not a fresh sequence.
   - **`dateCreated` / `dateModified` = the recipe's own `dateModified`**, never `Date()`.
   - **`provenance = .model`** for every migrated row (nothing in the blob records authorship).

   Done this way the migration is a deterministic function of already-synced rows, so every device computes
   identical rows and they converge without uploading — safe to leave in the migrator, no post-engine data
   pass needed. Get any column wrong and it is a two-device cleanup.
3. **Register in `CloudSync.swift`**'s tables list, alongside `RecipeNote.self` / `Learning.self`. Add to the
   **prod-schema promotion list** in `CURRENT_HANDOFF.md` in the same PR.
4. **Delete `reconciledServeWithItems`.** **Do *not* drop the `Recipe.serveWith` column in this PR** — stop
   reading it and leave it in place a release. A stranded DELETE gets one attempt and is unrecoverable (local
   row gone, CloudKit row alive, resurrected by any full-zone fetch), so the additive half converges first
   ([[migration-writes-bypass-sync-triggers]]).
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
