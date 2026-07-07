# ADR-0023 — Recipe edit proposals (the "Adjust this recipe" verb, non-destructive by construction)

> **Vocabulary:** the feature is **recipe edit proposals**, surfaced as an **"Adjust this recipe"**
> chat verb. A **proposal** is a *transient, device-local, non-destructive* candidate edit the LLM
> produces from the conversation; it is **reviewed as current-vs-proposed** and **committed by a tap**
> to one of **two destinations** — **overwrite** (change this recipe in place, *this ADR*) or **keep as
> a variation** (a named delta, **[ADR-0021](ADR-0021-recipe-variations.md)**). A proposal is **not** a
> variation (that is one of its destinations), **not** a sidecar section (Chef-It-Up / Serve-With /
> Make-ahead never touch canonical ingredients or method), and **not** a stored row until a tap. In the
> branch metaphor this ADR owns the **working tree** (the ephemeral preview) and the **merge to main**
> (overwrite); ADR-0021 owns the **long-lived branch** (the kept variation).

Status: **Proposed** — 2026-07-07 (architect + Jon, in the branch/undo/preview design conversation;
decisions D1–D6 ratified there, the storage sketch and slice plan are recommendations). **Extends
[ADR-0021](ADR-0021-recipe-variations.md)** — 0021 owns the *variation destination* (the durable delta,
the reader fold, the grocery fold); this ADR owns the *verb*, the *proposal/preview primitive*, and the
*overwrite destination* 0021 explicitly punts ("if a variation diverges beyond a note's worth… manual
promote"). Extends **[ADR-0011](ADR-0011-actionable-chat-make-ahead.md)/[ADR-0012](ADR-0012-menu-actionable-chat.md)**
(the `(extract → review → commit)` apply-action and "model proposes, the tap writes"). Binds
**[ADR-0004](ADR-0004-structured-recipe-editor.md)** (the structured, non-destructive editor is the
overwrite commit path), **[ADR-0015](ADR-0015-chat-persistence.md)** (the local-only, SyncEngine-excluded
store precedent — the proposal and the undo restore-point live there), and **[ADR-0017](ADR-0017-llm-model-and-reasoning-effort.md)**
(per-feature `reasoningEffort`). A new consumer of the [[chat-verb-commit-shapes]] axis. Sync-safe by
construction ([ADR-0002](ADR-0002-cloudkit-sync-no-server.md)).

## Context

Dogfooding the Workbench, Jon hit a wall: the working recipe is a **one-shot synthesis** you then edit by
hand. Chasing that, we found the gap is not workbench-specific — **no chat verb anywhere in the app edits a
recipe's canonical ingredients or method.** Every existing verb is *additive*: Make-ahead, Chef-It-Up, and
Serve-With each write a **sidecar section** (`RecipeDetailModel+Enrichment.swift`), and the workbench's one
exception (`WorkbenchDraftRecipe`) only ever *creates* a recipe — never edits an existing one (the draft
action is gated on `draftRecipeID == nil`; `WorkbenchModels.swift`). So "adjust the recipe by talking to
it" is missing on *plain recipes* and on *the working recipe* alike.

Jon's requirement, stated in the conversation: talk to the chat, have it propose changes, and incorporate
them — with a **proposal/confirm step that shows a side-by-side comparison so the LLM cannot run roughshod**
over a recipe. And it must live on **regular recipes**, not only the workbench ("not every recipe needs a
workbench").

### The insight that makes this safe (and general)

The fear — "the LLM rewrites my recipe and I lose the original" — exists **only if the verb mutates a
stored recipe in place.** Remove that assumption and the fear evaporates. Reframed in the branch metaphor
we settled on:

- **Preview = working tree.** The LLM writes only to a *transient proposal* beside the original. It has
  **zero durable footprint** and evaporates if you walk away. The LLM is *structurally* incapable of
  touching a stored recipe.
- **Overwrite = merge to main.** A deliberate, second tap, guarded by a **one-level undo** (a pre-edit
  restore point). *This ADR.*
- **Variation = a long-lived branch.** A deliberate "keep this" that never merges. *ADR-0021.*

Cooking inverts git in one way worth stating: most culinary "branches" are the *product* — you keep the
spicy and the mild side by side forever (ADR-0021). Convergence (many drafts → one working recipe) is the
**workbench's** job. This ADR is the front-end shared by the *edit* (overwrite) and the *diverge*
(variation) gestures — the same proposal, two commit taps.

## Decisions

### D1 — One verb, two destinations, homed on the recipe (ratified)

"Adjust this recipe" is a single apply-action on **`RecipeDetailModel.applyActionCatalog`**, so **every
recipe gets it** — and the workbench working recipe inherits it for free, because it is a plain `Recipe`
opened in the same `RecipeDetailView` reader and chat host. Committing routes to one of two destinations:
**overwrite** (this ADR) or **keep as a variation** (ADR-0021's delta). Same extraction, same review
surface, two commit paths. The verb is **not gated behind the workbench** (mirrors ADR-0021 D4).

### D2 — The LLM writes only to a preview; nothing is stored until a tap (ratified — the safety line)

The proposal is a **transient, device-local, SyncEngine-excluded** structure (ADR-0015 precedent). No DB
write, no variation row, no recipe mutation until the human commits. Walking away discards it. This single
property is the entire answer to "no roughshod": there is no in-place mutation to be afraid of, because the
model cannot reach a stored recipe.

### D3 — Review is a side-by-side current-vs-proposed, not the text card (ratified)

Today an apply-action's review is a rendered **string** in the staging card (`renderedReview()`). This verb
requires a real **current-vs-proposed** surface, and the engine already exists: reuse
**`WorkbenchCompareCore`** canonical-name ingredient alignment (ADR-0022) + the two-column
**`WorkbenchCompareView`** layout, pointed at *(this recipe, proposed recipe)* instead of *(working recipe,
candidates)*. Ingredients diff **structurally** (added/removed/substituted read as aligned rows and blanks);
method shows as a **prose before/after**. We do **not** build a structural, per-step mergeable method model
— that is the step-by-step resolver ADR-0016 declined, and ADR-0021 D2 already drew this line.

### D4 — Commit shape: a structured delta, not a full-recipe rewrite (ratified)

The extraction emits a **structured delta** in ADR-0021 D2's closed op vocabulary
(`add`/`remove`/`substitute`/`scale` for ingredients; a prose method note / whole-step text replacement for
method) — **not** a `WorkbenchDraftRecipe`-style whole-recipe blob. Rationale: a delta is *reviewable*
(it diffs cleanly), *undoable*, and **is the variation payload** if routed to ADR-0021 — so one extraction
serves both destinations. A full rewrite is a blob that silently churns untouched lines and can't be
diffed. This is the **structured-delta commit shape** — the richest entry in [[chat-verb-commit-shapes]];
classify it as such and hold [[llm-curation-not-synthesis]] (emit distinct ops, never a re-blended recipe).

### D5 — Overwrite carries a one-level undo via a pre-edit restore point (ratified)

Committing **overwrite** first stashes the pre-edit recipe as a **restore point**, then applies the delta
through the existing structured editor update path (ADR-0004). Undo = restore the stash. Reuse the
**`RecipeBundleCoding` snapshot codec and the existing snapshot-viewer UI** (`RecipeModels.swift`
`originalSnapshotButtonTapped`) — but as a **distinct, device-local, sync-excluded restore point**, *not*
the pristine **`originalSnapshot`** column, whose meaning is "the recipe as originally captured/imported"
(set once, if nil; `RecipeCore.swift`). Overwriting must **not** clobber that provenance. One level is
enough for v1 (see OQ2).

### D6 — Default to the cheapest tier; intent gates durability (ratified)

Preview is **ephemeral by default**. A **variation** is created only on an explicit "keep this"; an
**overwrite** is a deliberate tap behind the undo stash. This is the anti-proliferation rule: casual "make
it spicier" experiments cost nothing and leave no trace unless the cook deliberately promotes them. It
keeps us out of the git failure mode where every idle branch is durable clutter.

## Storage sketch (sync-safe by construction — recommendation, not ratified)

This ADR's **S1 is schema-free.** The overwrite path reuses the existing structured-editor update
(ADR-0004); the proposal and the undo restore-point are **local-only, SyncEngine-excluded** (ADR-0015
precedent — the same live-schema audit test that excludes chat and the ADR-0021 active-selection store
guards them). The **variation** destination's durable storage is **ADR-0021's** (`recipeVariations` table),
introduced when S2 lands — not here. No new synced table, no `recipes` column, no CKAsset concern.

## Cost, honestly — and the slice plan

The expensive machinery already exists: the `(extract → review → commit)` apply-action, the
`WorkbenchDraftRecipe` LLM-client shape, and the `WorkbenchCompareCore` diff engine. What is genuinely new
is the **side-by-side review view**, the **ephemeral proposal + undo restore-point**, and the
**delta-extraction verb**. Milestone-sized across all destinations, but **S1 is a real, shippable, schema-free
slice.**

- **S1 — the proposal primitive + preview + overwrite-only.** The `.adjustRecipe` apply-action on
  `RecipeDetailModel`; the LLM delta extractor (reuse the `WorkbenchDraftRecipeClient` shape, `high`
  effort per ADR-0017); the ephemeral device-local proposal store; the **side-by-side review view** (reuse
  `WorkbenchCompareCore`); commit = overwrite-in-place through the ADR-0004 editor with the D5 undo stash.
  **Schema-free.** Ships on regular recipes **and** the workbench working recipe at once. *De-risks the
  whole effort; dogfood before building the variation destination.*
- **S2 — the variation destination.** Add "keep as a variation" as the second commit path on the same
  proposal — which *is* ADR-0021's build (the `recipeVariations` table + reader fold + grocery fold). Here
  0023 and 0021 converge: one proposal, two taps. Resolves ADR-0021 OQ1 (the delta is already structured,
  so no separate extraction) and OQ2 (the D3 side-by-side is the staging surface).
- **S3 — iterative refine loop + workbench-log deposit.** Keep chatting to revise a *live* proposal before
  committing (re-extract with the current proposal as context); on the workbench, a committed adjustment can
  drop a `rationale`/`experiment` entry into the workbench log (ADR-0019). The conversational editing loop
  Jon originally asked for.

## Open questions (surface when the slice is drawn — not decided)

- **OQ1 — method-edit granularity on overwrite.** Ingredients are structured ops (D4). For method, is an
  overwrite limited to **whole-step text replacement** (replace step N's prose), or may it restructure the
  step list (insert/reorder/merge)? *Lean:* allow whole-step replacement and append/remove, but **no**
  structural per-step *merge* model (that reopens ADR-0016). Hold the ADR-0021 D2 line.
- **OQ2 — undo depth.** One-level restore point (D5) vs. a stack of pre-edit stashes. *Lean:* one level for
  v1; a stack is a fast-follow if dogfooding wants it.
- **OQ3 — overwrite of a recipe that already has variations (S2 interaction).** ADR-0021 deltas anchor on
  **base-ingredient identity**; overwriting the base can orphan a variation's anchor ("substitute the
  paprika" when the overwrite removed the paprika). Resolve when S2 lands: either re-validate/rebase deltas
  on overwrite, or warn-and-block. Recorded now so it isn't a surprise.
- **OQ4 — same-recipe vs. new-recipe as the review's "current."** For the workbench working recipe, "current"
  is the working recipe. For a plain library recipe, "current" is that recipe. Both are the same code path
  (a `Recipe` + a proposed delta); no fork expected, but confirm the reader/compare wiring is identical.
