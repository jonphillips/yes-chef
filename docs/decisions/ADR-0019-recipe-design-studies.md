# ADR-0019 — Recipe Workbench (durable design workspace → working recipe)

> **Vocabulary (ratified 2026-07-05, ADR-0006):** the feature is the **Recipe Workbench**. A user opens
> **a workbench** on a recipe; the evolving output is the **working recipe** (`draftRecipeID`); the durable
> deliberation store is the **workbench log**; its entries are **rationale / experiment / fork /
> observation / note**; the compared inputs are **candidates**. Entity/table names below use `Workbench*`
> (the body's earlier `Workbench*` identifiers are superseded — see Amendment 1 + 2). Do **not** call it
> a "study," "design doc," Menu, or Collection.

Status: **Proposed** — 2026-07-05 (architect sketch for the design session; body decisions below are
*recommendations*, not ratified — **but see Amendment 1**, where Jon ratified D1(b) and reframed the
entity from a transient study into a durable workbench). Sibling to **ADR-0008** (Collection — the "new entity, don't
overload Menu" precedent) and a third consumer of **ADR-0011/0012** actionable chat (the
composite-subject axis). Binds **ADR-0006** (vocabulary hygiene) and the reference/original-provenance
posture of **ADR-0010** / DATA_MODEL §2.4, §22.

## Context

The mission (Jon, 2026-07-05): pick **N recipes that all circle the same dish** (beef birria,
chocolate-chip cookies), talk with the AI about **what each one is trying to do** and its **strengths
and weaknesses**, then **draft a new recipe** — possibly with **experimental variations to try** — to
"circle in on the one true recipe."

Jon's own framing is the right one, and it's a CS instinct worth honoring: *name things what they are,
pull them out separately, build on top later.* This ADR's job is to decide **which primitive owns the
concept** before we re-derive it, exactly as ADR-0008 did for Collection.

### Why this is NOT a Menu, Meal-plan, or Collection

The three existing grouping entities all model a **set that coexists** — recipes that ship *together*
at one event (Menu/Meal-plan: an ordered, day/slot-placed set) or in one editorial index (Collection:
sectioned, curated). A design study has the **opposite topology**:

- Its members are **mutually-exclusive attempts at one target** — they are *alternatives*, not peers
  that coexist. You will never cook all five birria recipes together; you are comparing them to
  *collapse* them.
- The collection is defined by **resolving to a single output**. A Menu never resolves; a Collection
  never resolves; a design study is *defined* by producing one drafted recipe. That directional
  "inputs → output" relationship has no home in the flat, non-directional `menuItems` / `collectionItems`
  shape.
- It carries a **target concept** ("beef birria") as a first-class thing, independent of any member —
  the study exists before any candidate is added and outlives them once the draft is written.

So the members aren't a peer list; they're **inputs (candidates)** to a **derivation** whose end-state
is a **new Recipe with provenance back to the sources**. That derivation-with-provenance is precisely
the DATA_MODEL §22 `RecipeVersion` / `libraryPlacement = reference` future growing up — this feature is
plausibly where that vision first ships.

### The one genuinely new axis: a composite subject that *synthesizes*

ADR-0012 already taught the chat host a composite subject (menu chat reasons across N dishes). But every
ADR-0012 verb still acts *within* the composite — it plans across the menu, it appends to the menu. A
design study's flagship verb **emits a new document that did not exist**: it synthesizes a drafted
recipe out of the candidates. That is the novel motion and where the AI-quality risk concentrates.

Note the boundary against [[llm-curation-not-synthesis]]: that rule forbids *flattening user content
into one merged blob* for **filtering/curation** features. Here synthesis **is the deliverable**, and
its output is a **structured Recipe** (ingredients, steps), not a merged prose blob — so it honors the
rule's real intent (structured out, distinct items preserved) rather than violating it. The trap to
avoid is a mushy "average of all five recipes"; the guardrail (below) is that the draft must be a
coherent editorial *choice* with a rationale, and experiments come out as a **distinct list**, never
smeared into the draft.

### What already exists in this repo (reuse, not rebuild)

- **The actionable-chat host is context-general.** `RecipeChatContext` is an enum
  (`.recipe(...)`, `.menu(...)`); `ChatWorkspaceSplit` takes a context + a
  `(model) -> [AnyChatApplyAction]` catalog and is not welded to any one screen. A design study is a
  **new `.design(...)` case + catalog** — additive, per the same design that let the menu case land.
- **The AI window with detents** (the split/half-sheet chat surface Jon named) ships already; a study
  reuses it wholesale. The net-new UI is the **candidate selector**, not the chat.
- **Review-before-commit staging card** (`extract → review → commit`) already enforces the invariant —
  *the model proposes and structures; the human's tap is the only write* — so the draft-recipe write
  and the experiment-list write both route through an existing surface.
- **Recipe already models provenance and drafts.** `originalSnapshot` (write-once pristine snapshot),
  `originalImportText`, `source` string, and the **future `libraryPlacement` = main | reference**
  (DATA_MODEL §2.4) exist to keep source material searchable/linkable without cluttering browse — the
  exact posture a design study's candidates want.
- **BLOB-on-recipe storage precedent** for structured side-artifacts: `serveWith: Data?` (Codable BLOB)
  and `Menu.prepPlan: Data?`. A structured experiment list is the *serveWith* pattern, not new infra;
  it syncs as a CKAsset unconditionally per [[sqlitedata-blob-cloudkit-asset]].
- **LLMClientKit + ADR-0017 tiered effort** — the study's synthesis verb wants `high` effort like
  `MenuPrepPlan`; no new client work.

## Decision (proposed — for ratification)

Model recipe design as a **new first-class entity, `Workbench`** — a sibling of `Menu` and
`Collection`, not an overload of either — plus a **`.design(...)` case** on `RecipeChatContext` with its
own apply-action catalog. Verbs classified **commit-shape-first** per [[chat-verb-commit-shapes]]:

| Verb | Commit shape | Target | Resolution |
|---|---|---|---|
| **Compare / "what is each trying to do", strengths & weaknesses** | **no-commit** grounded chat | — | Plain chat (like ADR-0012 critique) |
| **Draft the recipe** | whole structured Recipe | a Recipe (see **D1 — open**) | **Synthesis, flagship** |
| **Experiments to try** | structured `[Experiment{hypothesis, change, rationale}]` list | BLOB on the draft (serveWith pattern) | **List** — distinct items, never smeared into the draft |

### D1 — What is the drafted artifact? (the decision that shapes the whole build — **OPEN**)

Three shapes, in ascending reuse. My lean is **(b)**; this is the one call I most want Jon to make.

- **(a) Draft-in-study.** A `WorkbenchDraft` child holding structured recipe content that is *not*
  yet a real Recipe, promotable later. *Pro:* keeps the Recipe table clean until the cook commits.
  *Con:* a parallel draft type that re-implements everything Recipe already gives (editing, images,
  scaling, sync) — the expensive path.
- **(b) A real Recipe from the start (recommended).** The draft *is* a `Recipe` row, linked from the
  study via `Workbench.draftRecipeID` (soft FK), and tagged as a design output. Reuses the entire
  Recipe stack — the reader, the structured editor, scaling, images, sync — for free, and gives
  provenance a natural home (`originalSnapshot` captures the pristine first synthesis; candidates carry
  back-pointers). *Con:* an in-progress draft is visible in the library unless we lean on
  `libraryPlacement` (or an `isDraft`/placement flag) to keep it out of the default browse until
  promoted — which is arguably a *feature* (drafts are findable) and pushes `libraryPlacement` from
  "future" to "now."
- **(c) Variations as first-class Recipes.** Each experiment is its own Recipe row. **Rejected as the
  default:** five experiments per study would flood the library with half-tested rows; experiments are
  *ideas to try*, not recipes yet. They live as the structured list (table row) and only become a
  Recipe if the cook actually cooks one and wants to keep it — a manual promote, not an auto-write.

### D2 — Grounding inverts the ADR-0012 budget shape (**recommended**)

Menu grounding is **breadth-shallow** (many dishes → capped summaries). Design grounding is
**depth-focused**: *few* candidates, but technique comparison wants **real detail** — full ingredient
lists and instruction steps, because "what is this one trying to do" lives in the method, not a summary.
So the tier-aware budget (ADR-0012 A1) still applies, but the allocation inverts: **spend the budget on
depth-per-candidate, not breadth.** With a small N (say ≤ 5, D3), full bodies of a few recipes fit
comfortably even at modest tiers; cap N rather than truncating each candidate's method, since truncated
method defeats the whole comparison.

### D3 — Candidate set is manual, small, ordered (**recommended**)

`WorkbenchCandidate` rows are added by the cook via the selector (multi-select over the library),
manually ordered, each carrying an optional cook's annotation ("this one nails the consommé, dry on the
meat"). Suggest a soft cap (~5) for the grounding reason in D2; not a hard schema constraint. No smart
seed in v1 (unlike Collection's optional rule — a study is a deliberate hand-pick).

### D4 — Living workspace, passive artifacts (**recommended**)

Like the menu prep plan (ADR-0012 A3) and reference/original provenance (ADR-0010), the draft and the
experiment list are **passive snapshots with regenerate/refine affordances**, not live-linked. Editing
a candidate does not silently rewrite the draft; the study is a workspace the cook iterates in
("circle in"), with the chat reading the current draft + experiments and proposing edits against them
(converse → propose → tap-Apply). No auto-recompute on candidate edits.

## Proposed schema (sync-safe by construction, per ADR-0002)

Two tables + optional BLOB, mirroring the `menus`/`menuItems` precedent:

- **`Workbench`** — `id` (UUID PK), `title` (the target concept), `notes: String?`,
  `draftRecipeID: UUID?` (**soft FK `ON DELETE SET NULL`** — a study tolerates its draft being deleted),
  `experiments: Data?` (Codable BLOB `[Experiment{hypothesis, change, rationale}]`, serveWith pattern),
  `sortOrder`, `dateCreated`, `dateModified`.
- **`WorkbenchCandidate`** — `id`, `designID` (FK `ON DELETE CASCADE`),
  `recipeID: UUID?` (**soft FK `ON DELETE SET NULL`**), `recipeTitleSnapshot: String` (denormalized so a
  candidate renders when its recipe is unsynced/deduped/deleted — same robustness as
  `menuItems.title`/`collectionItems.recipeTitleSnapshot`), `annotation: String?` (the cook's
  strengths/weaknesses note), `sortOrder`, `dateCreated`.

All UUID PKs, **no unique indexes** beyond PK, all cross-record refs **soft** and **denormalized-backed**,
duplicate-ref resolution at **read time** — the ADR-0002 / ADR-0008 §5 reference-tolerance playbook. This
is a **post-sync** feature (sync is done, [[extension-sync-construct-not-run]]), so the tolerance is
exercised, not merely reserved. Additive migration; no reserved columns; nothing touches existing tables
except the (already-planned) `libraryPlacement` if D1(b) uses it to hide in-progress drafts.

## Consequences / boundaries

- **Reuse, not rebuild.** The chat host, split surface, staging card, LLMClientKit/effort tiers, and —
  under D1(b) — the entire Recipe stack (reader, editor, scaling, images, sync) are done. Net-new code:
  two tables + models, the **candidate selector UI**, a `.design` context + serialization (D2), and
  three verbs (compare = zero surface, draft, experiments).
- **Invariant preserved.** Model proposes/structures; **the tap writes.** No chat turn creates the draft
  Recipe or edits experiments on its own — both route through the review card.
- **Synthesis guardrail.** The draft must be a coherent editorial *choice* with a stated rationale
  referencing the candidates, not a blended average; experiments stay a **distinct list**. This is how a
  *synthesis* feature stays on the right side of [[llm-curation-not-synthesis]]'s structured-out intent.
- **Provenance is passive** (D4). `draftRecipeID` + candidate back-pointers make the lineage
  *inspectable* and make staleness *detectable*, but nothing is live-linked; regenerate/refine + clear,
  same posture as prep plan and reference/original.
- **Vocabulary (ADR-0006).** *Superseded by the top banner + Amendment 2 — ratified name is **Recipe
  Workbench**.* The entity is a **workbench** opened on a recipe; the output is the **working recipe**; the
  ideas are **experiments** in the **workbench log**. Keep distinct from Menu/Collection/Meal-plan in copy
  and identifiers; a workbench is not a collection.
- **Sequencing (milestone-sized, not a slice).** New entity + new selector UI + new synthesis verb
  family. Legitimate to build now that the sync gate is passed
  ([[post-browser-sync-vs-features-tension]]), but it earns its own effort doc and a **deliberately thin
  first slice** — prove the container and the conversation *before* the synthesis, because synthesis is
  where the quality risk lives.

## Slice plan (proposed)

- **S1 — the entity + selector + grounded chat, NO drafting.** `Workbench` + `WorkbenchCandidate`
  migration and models; a create-study flow with a **multi-select recipe picker**; a study screen
  listing candidates (with per-candidate annotation) and hosting the existing chat split via a new
  `.design(...)` context with depth-focused grounding (D2). **"Compare / strengths & weaknesses" works
  immediately as plain chat** (zero commit surface). This slice de-risks grounding and UX with no
  synthesis and no draft write. Additive migration only.
- **S2 — the draft verb → a Recipe (settles D1).** The flagship synthesis: apply-action + review card
  that writes the draft per the ratified D1 shape, `high` effort (ADR-0017), `draftRecipeID` link +
  provenance capture. Opens the draft in the existing Reader/editor.
- **S3 — experiments list → `Workbench.experiments`.** Structured `[Experiment]` BLOB, its own
  section with add/refine/clear; distinct-list commit (D-table row 3).

Lean verification default ([[lean-verification-default]]): `swift build` for logic-only; otherwise one
app build for `iPad Pro 13-inch (M5)` + `scripts/check-drift.sh`, no simulator install — Jon does the
device pass. Selector + chat surfaces are iPad-primary but must work on iPhone.

## Open questions for the design session

1. **D1 — draft artifact shape (a/b/c).** The load-bearing decision. Recommend **(b)**; needs Jon's call
   on whether in-progress drafts live in the library (and whether that promotes `libraryPlacement` to now).
2. **Candidate → reference placement?** When a recipe is pulled into a study, should it optionally flip to
   `libraryPlacement = reference` (source material, out of default browse)? Clean tie-in to ADR-0010, but
   maybe too aggressive as a default — likely a manual affordance, not automatic.
3. **One draft per study, or several?** D1(b) as written is one `draftRecipeID`. Does "circle in" ever
   want *competing* drafts side-by-side, or is the single evolving draft (+ experiments list) enough?
   Recommend single draft + experiments; revisit only if the workflow demands rival drafts.
4. **Entry point.** Is a design study created from scratch (pick target, then add candidates), or seeded
   from a multi-select in the library ("Design from these 4")? Recommend supporting the seeded path — it's
   the natural gesture — with scratch-create as the empty case.

## Amendment 1 — Durable workbench, not transient study: the workbench log + two histories

Ratified 2026-07-05 (design session with Jon). Jon accepted **D1(b)** (the draft is a real Recipe from
the start) with one condition — *he must be able to keep interrogating and refining* — and that condition
reframes the entity. Four changes:

- **A1 — The design is a durable workbench, not a study that collapses and dies.** "I'm working on this
  recipe" is a **persistent open design** that lives alongside the recipe across weeks/months of real
  cooking. **Candidate comparison is demoted from the essence to one seed mode:** a design may be opened on
  an existing recipe with *zero candidates*, purely to iterate. The spine is now "iteration workspace +
  durable design record"; comparing N candidates is one entry gesture into it (D-table row 1 unchanged;
  candidates become optional, not required).

- **A2 — Two distinct histories; chat retention is the wrong home for the durable one.**
  **(i) Conversational history** = the raw chat transcript, ADR-0015's ~1-month retention — *working
  memory*, verbose, fine to expire. **(ii) Deliberation history** = distilled, curated intent ("could go
  cheese-stuffed or plain; chose plain, revisit"; "tried dry-toasting, meat improved, consommé unchanged")
  — *long-term memory* that **must not expire**. Its only home today is (i), which is raw and expiring;
  that gap is what this amendment closes. Do not lean on chat persistence to preserve deliberation.

- **A3 — New primitive: a durable, typed, append-only workbench log (replaces the `experiments` BLOB).** One
  table whose entries carry a `kind`, so emerging dogfood verbs write into it instead of demanding new
  schema:
  - **`WorkbenchLogEntry`** — `id` (UUID PK), `designID` (FK `ON DELETE CASCADE`),
    `kind` (`rationale | experiment | fork | observation | note` — **extensible**), `body: String`,
    `outcome: String?` (for `experiment` — what happened when actually tried), `relatedRecipeID: UUID?`
    (**soft FK `ON DELETE SET NULL`** — e.g. a `fork` pointing at an alternative), `sortOrder`,
    `dateCreated`. Editable/deletable by the cook; append-only in practice. Sync-safe by the same
    playbook (UUID PK, soft FKs, no unique index).
  - **This supersedes `Workbench.experiments: Data?`.** Experiments **accumulate individually over time
    and gain outcomes** — that is a *log* (rows with stable ids/dates), not a wholesale-regenerated
    snapshot like `serveWith`/`prepPlan`. Drop the BLOB field; experiments are `kind = experiment` rows.
  - This is the home for "verbs that don't fit a normal recipe structure" (Jon's prediction): their target
    was never the recipe — it's the **workbench log**. A new dogfood verb is usually a new `kind` or a new way
    to compose an entry, **not a migration**. We reserve the *shape* of recipe-adjacent durable thinking,
    not a bet on specific verbs.

- **A4 — The bridge is the existing tap, aimed at a new target class.** ADR-0011/0012 write the tap's
  commit to the recipe/menu. Here the tap can also write to the **design record itself**: a *"save to
  workbench log"* action promotes a **distilled** entry from the ephemeral chat into the durable log. This is
  the mechanism that rescues the "could-go-this-way" thinking before the chat expires — curate keepers out
  of working memory into long-term memory, one tap at a time. Invariant unchanged: model
  proposes/structures; **the tap writes.**

**Resolves open Q3 (branching) → light.** "Could go this way, could go that" is a `fork` log entry that
preserves the road-not-taken as durable text — **not** materialized competing draft Recipes. Rival full
drafts (parallel-draft UI, "which is the winner" semantics) are deferred until dogfooding proves a fork
entry insufficient. One evolving `draftRecipeID` + the log is the v1 answer.

**Schema delta from the body:** `Workbench` loses `experiments: Data?`; add table
`WorkbenchLogEntry`. `WorkbenchCandidate` is now **optional** (a design can have none). Everything
else (soft FKs, denormalized snapshots, read-time dedup, additive migration, post-sync) stands.

**Slice-plan delta:** the workbench log + "save to workbench log" tap slots between S2 (draft verb) and S3.
Suggest **S3 = the workbench log surface + save-to-log tap** (the durable-history primitive Jon most wants),
with the AI-generated experiment/fork verbs layered on top as they emerge from dogfooding — S3 ships the
*store and the manual/curate path* first, before betting on generated entries.

## Amendment 2 — Name ratified: "Recipe Workbench"

Ratified 2026-07-05 (Jon). The feature is the **Recipe Workbench** — a name meant to carry through UI copy,
identifiers, and docs. Canonical term map (ADR-0006):

| Concept | Ratified term | Schema identifier |
|---|---|---|
| The feature / durable workspace opened on a recipe | **workbench** | `Workbench` (table `workbenches`) |
| The evolving output recipe | **working recipe** | `Workbench.draftRecipeID` (soft FK) |
| A compared input recipe | **candidate** | `WorkbenchCandidate` (table `workbenchCandidates`) |
| The durable deliberation store | **workbench log** | `WorkbenchLogEntry` (table `workbenchLog`) |
| A log entry's type | rationale / experiment / fork / observation / note | `WorkbenchLogEntry.kind` |
| Entry gesture | **"Open a workbench"** (from a recipe, or "Workbench these" from a multi-select) | — |

Retire "study," "design study," and "design doc" from copy and code. The `RecipeDesign*` identifiers used
in the body are superseded by the `Workbench*` names above. Filename keeps `…-recipe-design-studies.md` for
link stability (ADRs are cited by number); the H1 and all identifiers are the Workbench vocabulary.

**Also settles two body open questions:** **Q2 (candidate → reference placement)** — a *manual, optional*
affordance ("keep as reference"), never automatic; not required for v1. **Q4 (entry point)** — support
**both**: "Open a workbench" from a single recipe (candidate-less iteration) *and* "Workbench these" from a
library multi-select (the seeded-comparison path). Scratch-create is the empty case of the former.

## Related

- ADR-0008 (Collection — the "new entity, don't overload" precedent + reference-tolerance §5), ADR-0011
  (recipe-scope actionable chat), ADR-0012 (menu composite-subject chat + tier-aware grounding A1/A3),
  ADR-0010 (reference/original provenance posture), ADR-0017 (LLM effort tiers), ADR-0006 (vocabulary),
  ADR-0002 (sync/reference tolerance), ADR-0015 (chat persistence — the *working-memory* half of A2, the
  workbench log being the *long-term* half). DATA_MODEL §2.4 (`originalSnapshot`), §22 (`RecipeVersion` future),
  `libraryPlacement`.
- Memory: [[chat-verb-commit-shapes]], [[llm-curation-not-synthesis]], [[sqlitedata-blob-cloudkit-asset]],
  [[post-browser-sync-vs-features-tension]], [[reference-placement-and-original-provenance]],
  [[lean-verification-default]].
