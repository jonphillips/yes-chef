# Effort: Recipe Workbench — durable design workspace over a recipe

**Type:** New first-class entity + a new actionable-chat context (`.workbench`) + a candidate-selector
UI. Reuses the Recipe stack (reader/editor/scaling/images/sync), the chat split host, the staging card,
and LLMClientKit. **Not** an overload of Menu/Collection.
**Owner:** Codex (implement, per slice) · Claude (architect/review) · Jon (product/review)
**Status:** **Queued** (one effort, sequenced slices; **dispatch S1 alone first** — it de-risks grounding
+ UX before any synthesis). Milestone-sized: do **not** bundle all slices into one PR.
**Decisions it implements:** [ADR-0019](../decisions/ADR-0019-recipe-design-studies.md) — whole, incl.
**Amendments 1 (durable workbench + workbench log) and 2 (name ratified)**. Design record: the
2026-07-05 design conversation.

**Read before starting:** ADR-0019 in full (the top vocabulary banner + both amendments are load-bearing;
the body's `RecipeDesign*` names are superseded by `Workbench*`). Then, for reuse patterns:
`RecipeChat.swift` (`RecipeChatContext` enum + `MenuChatContext` serialization — the model for the new
`.workbench` case and its grounding), `ChatWorkspaceSplit` / the staging (review-before-commit) card,
`Models.swift` + `Schema.swift` (the `menus`/`menuItems` migration + `@Table` shape this mirrors, and the
`serveWith`/`Menu.prepPlan` BLOB precedent), and `RecipeDetailView(recipeID:scaleContext:…)` (the reader
the working recipe opens in, for free). ADR-0017 for per-feature `ReasoningEffort` (the draft verb is
`high`, chat is `medium`).

**Build/verify (house constraint, [[lean-verification-default]]):** package logic via `swift build`; app
via `-skipMacroValidation`, built once; `xcodegen generate` after adding files; then `CURRENT_HANDOFF.md`
Verification Pattern — **no simulator install**, Jon does the device pass. Selector + chat are
**iPad-primary** (primary pass on `iPad Pro 13-inch (M5)`, both orientations) and must also work on
`iPhone 17 Pro` (compact selector + chat sheet).

---

## The invariant this preserves

The workbench chat grounds on the candidates + the working recipe + the workbench log, and **the model
proposes; the tap writes** (ADR-0011/0012). No chat turn creates the working recipe, edits it, or appends
a log entry on its own — every write routes through the staging card.

## Sync posture (ADR-0002 / ADR-0008 §5)

Every new table: UUID PK, **no unique index** beyond PK, all cross-record refs **soft** (`ON DELETE SET
NULL`) and backed by a **denormalized title snapshot**, duplicate-ref resolution at **read time**. This is
a **post-sync** feature — the tolerance is exercised, not merely reserved. Additive migrations only;
the one existing-table touch is the **`libraryPlacement` column on `recipes`** in S2 (decided 2026-07-06,
additive-nullable, defaults `main`) to hide in-progress working recipes from browse.

## Slice plan

- **S1 — the entity + candidate selector + grounded chat, NO synthesis, NO working recipe.** *(de-risks
  the whole effort; ship and dogfood before betting on the draft verb.)*
  - Migration + `@Table` models: **`Workbench`** (`id`, `title` = the target concept, `notes: String?`,
    `draftRecipeID: UUID?` soft FK — null in S1, `sortOrder`, `dateCreated`, `dateModified`) and
    **`WorkbenchCandidate`** (`id`, `workbenchID` FK cascade, `recipeID: UUID?` soft FK,
    `recipeTitleSnapshot: String`, `annotation: String?`, `sortOrder`, `dateCreated`). Candidates are
    **optional** (a workbench may have none).
  - Entry points (ADR-0019 Amdt 2, Q4): **"Open a workbench"** from a single recipe *and* **"Workbench
    these"** from a library **multi-select** (the seeded-comparison path). Scratch-create = empty case.
  - Workbench screen: lists candidates (each with an editable **annotation** — the cook's
    strengths/weaknesses note) and hosts the existing chat split via a new **`case workbench(...)`** on
    `RecipeChatContext` + a `WorkbenchChatContext`.
  - **Depth-focused grounding (ADR-0019 D2 — the inverted budget):** feed *full* ingredient lists +
    instruction steps for a *small* candidate set (soft-cap ~5); tier-aware budget, but spend it on
    **depth-per-candidate**, not breadth — cap N rather than truncating any candidate's method.
  - **"Compare / what is each trying to do / strengths & weaknesses" works immediately as plain chat** —
    zero commit surface (ADR-0019 D-table row 1). No schema beyond the two tables. **This is the dispatch
    target; stop here for review.**

- **S2 — the draft verb → a real working recipe (settles/executes D1(b)).**
  - Synthesis apply-action + review card that writes a **new `Recipe`** and links it via
    `Workbench.draftRecipeID`; capture `originalSnapshot` (pristine first synthesis) for provenance; open
    it in the existing `RecipeDetailView` reader/editor. `high` effort (ADR-0017).
  - **Synthesis guardrail (ADR-0019):** the draft must be a coherent editorial *choice* with a stated
    rationale referencing candidates — **not** a blended average of all candidates. Honors
    [[llm-curation-not-synthesis]] by emitting a structured Recipe, distinct choices preserved.
  - **Decided (Jon, 2026-07-06): promote `libraryPlacement` "future → now"** (DATA_MODEL §2.4,
    `main | reference`) and set the new working recipe to a non-`main` placement so **in-progress working
    recipes stay out of the default browse list** until the cook promotes one. This is the effort's second
    schema touch (additive column on `recipes`); sync-safe (additive-nullable, defaults `main`). "Promote to
    library" is a one-tap flip to `main`.

- **S3 — the workbench log (the durable-history primitive; ADR-0019 Amdt 1).** *Ship the store + curate
  path before the generated verbs.*
  - Migration + model: **`WorkbenchLogEntry`** (`id`, `workbenchID` FK cascade,
    `kind: rationale | experiment | fork | observation | note` — **extensible enum**, `body: String`,
    `outcome: String?` for tried experiments, `relatedRecipeID: UUID?` soft FK, `sortOrder`,
    `dateCreated`). Editable/deletable; append-only in practice.
  - Log surface on the workbench screen (dated, typed entries) + a **"save to workbench log"** tap that
    promotes a **distilled** entry from the ephemeral chat (ADR-0015 ~1-month) into the durable log
    (ADR-0019 A2/A4 — the two-histories bridge).
  - S3 ships the **store + manual/curate path first**; AI-*generated* experiment/fork entries layer on as
    dogfooding shapes them (new `kind` or new compose path = no migration).

## Out of scope / parked follow-ons

- **Rival full working recipes side-by-side** ("could go this way, could go that" as *materialized*
  competing drafts, with which-is-winner semantics). Deferred — a **`fork` log entry** captures the
  road-not-taken as durable text for v1 (ADR-0019 Amdt 1, resolves body Q3). Revisit only if dogfooding
  proves a fork entry insufficient.
- **Auto-flip a candidate to `libraryPlacement = reference`.** Manual, optional affordance only, never
  automatic (ADR-0019 Amdt 2, Q2).
- **Smart-seed candidate rules** (Collection-style category/tag auto-membership). A workbench is a
  deliberate hand-pick; no rule seeding (ADR-0019 D3).
- **AI-generated log entries** as a first-class verb family — reserved by the `kind` enum, layered post-S3
  from dogfooding, not built up front.

## Resolved at review (Jon, 2026-07-06)

- **S3 ordering** → **store + curate path first** (the recommendation): S3 ships the `WorkbenchLogEntry`
  table + log surface + the *save-to-workbench-log* tap; AI-*generated* experiment/fork entries layer on
  from dogfooding (new `kind` / compose path = no migration).
- **`libraryPlacement` in S2** → **promote "future → now"** and hide in-progress working recipes from
  default browse until promoted (see the S2 "Decided" bullet). Additive column on `recipes`, sync-safe.
