# ADR-0011 — Actionable chat, first verb: make-ahead distillation

Status: **Accepted** — 2026-07-02 (Jon signed off same day; open questions resolved; Slice 1
dispatched via `docs/efforts/actionable-chat-make-ahead.md`). Binds jon-platform
`docs/ios/actionable-chat.md` (the cross-app pattern) and `docs/ios/ai-model-access.md` (the
ModelClient boundary law) to Yes Chef. Yes Chef is the **first real consumer** of actionable
chat; per galavant **ADR-0031** (proposed 2026-07-02, the Galavant home of the decision) the
`(extract → commit)` abstraction is *designed and proven here* — Galavant has no honest distill
instance yet, so building the framework there would pre-extract against zero consumers. It
feeds back to galavant and eventually a jon-platform cross-app ADR. Extends this repo's AI-uses
charter (`FUTURE_INTELLIGENCE_AND_PLANNING.md` §7).

**Resolved 2026-07-02:** package = **`LLMClientKit`**; commit target = a new additive
**`Recipe.makeAhead: String?`** column; Yes Chef **migrates** its existing minimal AI stack
onto the shared package (one boundary). These are baked into the decision below.

## Context

The mission is the **first real instance of the cross-app "actionable chat" pattern**: chat
about the recipe that's on screen (seeded context, no screenshots), then tap **one** button
that turns the conversation into a **structured change to that recipe**. The invariant
(actionable-chat.md): *the model proposes and structures; the human's tap is the only write.*
No chat turn mutates a recipe on its own.

This is not a new idea in Yes Chef — it is the app's own stated intent. `PRODUCT_BRIEF.md`
("eventually helps generate realistic prep, shopping, make-ahead, thawing, and cooking
plans") and `FUTURE_INTELLIGENCE_AND_PLANNING.md` §7.2 name the exact feature:

> *Generate a reviewable make-ahead strategy for a saved recipe and persist the accepted
> version with that recipe, likely as its own make-ahead section rather than a generic note.*

The cross-app pattern calls this **advance-prep distillation**; Yes Chef's native vocabulary
(ADR-0006 vocabulary hygiene) is **make-ahead**. This ADR uses *make-ahead* for the domain
(field/note/UI) and *actionable chat / advance-prep distillation* for the portable pattern.

### What already exists in this repo (discovered 2026-07-02)

- A **divergent, minimal AI stack** predating the shared-package plan: `ModelClient` (a
  complete-only *struct*, no tiering/streaming/tools), `ClaudeAPIClient` (a live single-
  provider Anthropic backend), `ClaudeAPIKeyStorage` (app Keychain), and `AISettingsView`
  (BYO-key entry). The app wires `ClaudeAPIClient` at launch, **but no feature consumes
  `modelClient` yet** — so migrating it is cheap.
- `RecipeNote` (`recipeNotes` table) with a `RecipeNoteType.makeAhead` case **already
  modeled and CloudKit-synced**. There is **no** `Recipe.makeAhead` field and no dedicated
  make-ahead section surface.
- `InstructionSection` supports named sections (imports already carry "Make ahead" as a
  section name in some sources).

## Decision

Deliver actionable chat as the mechanism `actionable-chat.md` describes — a screen that
presents chat **and** declares a small catalog of typed **apply-actions**, each a pair:

```
extract:  conversation-so-far  →  structured MakeAheadPlan   (a focused ModelClient.complete)
commit:   MakeAheadPlan         →  a tested domain op         (a pure app write)
```

The **catalog is the deliverable, not one verb** (galavant ADR-0031 §Consequences: a screen
supplies a *catalog* of `(extract → commit)` pairs; the panel renders each as a button). Slice 2
designs it **verb- and context-general** and lands **make-ahead as verb #1**. Named next verbs
that keep the design honest (deferred, not built here):

- **"Chef It Up" (post-hoc distill, recipe):** discuss creative riffs → distill into a
  `Recipe.chefItUp` section. Same shape as make-ahead, a second field — proves the catalog
  generalizes across verbs.
- **Menu side-dishes (inline-structured, menu):** on a *menu*, "suggest sides to complete this
  that aren't full recipes yet" → structured cards, each one-tap added as a lightweight menu
  item. Proves the catalog spans **both motions** (proactive cards, per galavant ADR-0030) and
  **more than one context** (menu, not just recipe) — so `ChatContext` and the catalog must not
  be recipe-only.

So the make-ahead button — **"Summarize make-ahead → Make-ahead section"** — is the first
entry in a general catalog, not a bespoke feature.

### 1. The portable layer moves out first (Slice 1 — the prerequisite lift)

Per `ai-model-access.md` (Extraction) and the WebExtractorKit precedent (jon-platform
ADR-0002, this repo's ADR-0007/0009), **lift galavant's `GalavantAI` module to a neutrally-
named shared SPM package** under `~/code/jon-platform/packages/`. `GalavantAI` is already
domain-free (imports only Dependencies/Foundation/FoundationModels/Security/Synchronization),
so for galavant this is **rename-and-move + delete**, both apps depending by local path.

**For Yes Chef this slice is a small migration, not clean adoption.** The shared package's
`ModelClient` is a richer, incompatible shape (protocol; `ModelTier` on-device floor +
frontier; `stream`; tool-use loop; multi-provider `FrontierProvider`; `APIKeyStore`). Yes
Chef's existing `ModelClient`/`ClaudeAPIClient`/`ClaudeAPIKeyStorage`/`AISettingsView` are
**deleted and re-pointed** at the shared package. Net gain: Yes Chef inherits the on-device
private default, streaming, the tool loop, and multi-provider it does not have today. Risk is
low because nothing consumes `modelClient` yet. Record the lift row in
jon-platform `EXTRACTION-NOTES.md`. This is **its own PR in each repo**; use worktree
isolation if galavant runs in parallel.

> **Package name (resolved): `LLMClientKit`.** Capability + boundary in one — accurate across
> every tier, since the on-device (FoundationModels) and Apple-PCC tiers are LLMs too. The
> `GalavantAI` symbols (`ModelClient`, `TieredModelClient`, `AnthropicModelClient`,
> `APIKeyStore`, …) move unchanged under the new module name.

### 2. The seeded chat surface (Slice 2, part A)

Mirror galavant's `GalavantChat` (`ChatModel` + `ChatContext`), **domain-adapted, not
copied**:

- **`RecipeChatContext`** — built by `RecipeDetailView` from already-fetched read-model
  values (title, servings/yield, times, ingredient sections + lines, instruction sections +
  steps, existing notes) and `serialized()` into the system prompt. The model is *seeded*
  with the recipe on screen, never turned loose on the database. Pure/testable.
- **`RecipeChatModel`** (`@MainActor @Observable`) — ephemeral message list (never persisted,
  never synced), per-conversation tier choice (on-device default; frontier opt-in when a key
  exists, surfaced as "leaves the device"), streaming on-device, tool loop on frontier. Lives
  in `YesChefCore` so dispatch/serialization is stub-testable.

Presented in `RecipeDetailView` (a panel/sheet). Chat stays free-form prose; the "relate it
to my recipe" affordance lives entirely in the apply-action button.

- **Parity built in (galavant ADR-0031 §6 — table stakes, not the decision).** Because we build
  the panel fresh, we include from the start: **inline markdown rendering** (`LocalizedStringKey`,
  so bold + `[label](url)` render rather than raw `**`/`###`) and an **editable pre-prompt** in
  Settings spliced into `systemPrompt()` (mirrors galavant's `ChatInstructions` dependency).
  **Web search is *not* wired for make-ahead** — the distillation reasons over the already-seeded
  recipe and needs no search; a later verb that needs grounding wires `webSearchMaxUses` then.

### 3. The make-ahead apply-action (Slice 2, part B — the point of the whole exercise)

- **Extract — `MakeAheadPlanClient`** (mirrors `PlaceDiscoveryClient`): a **single focused
  `ModelClient.complete`** over the conversation-so-far + serialized recipe, `system`-
  instructed to return **only** a strict JSON `MakeAheadPlan`, parsed defensively (a bad
  element drops, not the whole plan). `MakeAheadPlan` is a domain value in `YesChefCore`
  (e.g. ordered `MakeAheadStep { when: String, task: String, why: String? }` + an optional
  `dayOfNote`). Grounded structured extraction defaults to **frontier/Anthropic**
  (reliable structured output); pure-summarize with no search can fall to on-device.
  The **model layer never sees a `Recipe`** — extraction is generic-in, `MakeAheadPlan`-out.
- **Commit — `applyMakeAheadPlan(_:to:)`**: a **pure, tested `YesChefCore` op** (in-memory
  DB tests) that renders the `MakeAheadPlan` into the new **`Recipe.makeAhead: String?`**
  column. Replace-on-commit (one canonical make-ahead result per recipe); **undo = clear the
  field.** The plan stays a structured value through extraction/decode; the commit flattens it
  to the field, so a later slice can graduate to a richer structured section without touching
  the extraction.
- **Button — "Summarize make-ahead → Make-ahead section."** Runs extract, shows the decoded
  plan for a beat, commits on the tap. The tap is the only write (invariant).
- **Surface** — `RecipeDetailView` renders `recipe.makeAhead` as **its own section**
  (satisfying §7.2's "its own make-ahead section rather than a generic note").

> **Commit target (resolved): a new additive `Recipe.makeAhead: String?` column.** The most
> literal reading of §7.2's "its own section." An **additive nullable column is sync-safe**
> (SQLiteData/CloudKit: additive columns need no schema-version dance, no reserved names, no
> new unique index — [[sqlitedata-blob-cloudkit-asset]] / ADR-0010). Undo = clear the field.
> (The already-modeled `RecipeNote(.makeAhead)` type stays available for *user-authored*
> make-ahead notes; the AI-distilled canonical plan lives in the field.)

### 4. Feed back (Slice 3)

Once the abstraction is proven here, **update galavant ADR-0031** (already proposed — its
Slices 3–4) with what the real `(extract → commit)` shape looked like: conform ADR-0030's
suggestion cards to it, add a Galavant distill verb only if a real need appears, and — when the
shape holds across both apps — promote the pattern to a jon-platform cross-app ADR under
`docs/adr/`, flipping both ADRs to Accepted. Galavant's **Slice 0 (parity §6)** is independent
and can proceed in Galavant in parallel with our Slices 1–2.

## Why this and not the alternatives

| Option | Verdict |
| --- | --- |
| **Let the model write the recipe via a tool-use loop** | Rejected. Violates the invariant + §7.3 "silent rewriting." The tap is the write; the tool loop stays for *conversation*, not for committing the section. |
| **Keep Yes Chef's minimal `ModelClient`; adopt the shared package only for chat** (two clients) | Rejected as the end state — two AI boundaries in one app is exactly what `ai-model-access.md` forbids. (Whether to *temporarily* run both is Open question C, below.) |
| **First verb = scale / grocery** | Rejected for v1. Make-ahead is a **single pure text/structured write** with trivial undo — the cleanest proof of `(extract → commit)`. Scale and grocery fan out across rows. |
| **Commit as a generic note** | Rejected. §7.2 wants "its own make-ahead section" — hence a dedicated `Recipe.makeAhead` field rendered as a section, not an untyped note in the pile. |
| **On-device for the extraction** | Fine for pure-summarize; grounded/structured defaults to frontier for reliable JSON (`ai-model-access.md` provider note). Degrades predictably when no key. |

## Consequences

- **Shared package (Slice 1):** `GalavantAI` → `packages/LLMClientKit`. galavant deletes +
  path-depends; Yes Chef **deletes its minimal AI stack** (`ModelClient`, `ClaudeAPIClient`,
  `ClaudeAPIKeyStorage`) + path-depends and re-points `AISettingsView` at the shared
  `APIKeyStore` (multi-provider-ready); EXTRACTION-NOTES.md row added. **Two PRs** (one per
  repo).
- **`YesChefCore` (Slice 2):** the additive `Recipe.makeAhead` column + migration;
  `RecipeChatContext`, `RecipeChatModel`, `MakeAheadPlan` + `MakeAheadPlanClient`
  (stub-tested), `applyMakeAheadPlan` (in-memory-DB-tested).
- **App (Slice 2):** a chat panel in `RecipeDetailView`; the "Summarize make-ahead" button; a
  make-ahead section rendering `recipe.makeAhead`. Apple-Intelligence-gated paths verify **on
  device** (sim has no Apple Intelligence).
- **galavant (Slice 3):** ADR-0031 updated from the proven shape (conform ADR-0030 cards; distill
  verb only if needed); jon-platform cross-app ADR when it holds. Galavant Slice 0 (parity) runs
  independently in parallel.

## Open questions — resolved (2026-07-02)

- **A — package name:** **`LLMClientKit`** (Jon).
- **B — commit target:** **new additive `Recipe.makeAhead: String?` column** (Jon).
- **C — Slice 1 scope for Yes Chef:** **migrate** the minimal AI stack onto the shared package
  now — one boundary (Jon).

## Amendment 1 — selection-scoped apply-actions

Status: **Accepted** — 2026-07-03 (Jon signed off same day, from his first dogfooding pass over the
shipped make-ahead chat, PR #68; sub-question leans ratified). This revises the apply-action input
surface described in the Decision (§2d) and galavant ADR-0031's `(extract → commit)` shape; it does
**not** touch the invariant (the tap is still the only write) or the commit side.

### The problem the shipped shape has

Slice 2 defined each apply-action's `extract` over **the whole conversation**
(`extract: ([ChatMessage]) → T`). Dogfooding shows this is the wrong granularity. Frontier chat does
not answer in discrete, individually-commit-able units — a single assistant reply might contain
three candidate side dishes, or a make-ahead plan *and* two riffs Jon doesn't want. "Distill the
conversation" then has to guess which part of which turn the human actually meant. The human already
knows; the UI just isn't letting them say it.

### Decision (proposed)

The payload of an apply-action is a **user-selected text span**, not the conversation. The
conversation remains available as *context*, but the thing the verb operates on is what the human
highlighted.

- **Input shape changes** from `([ChatMessage]) → T` to something like
  `(selection: String, context: [ChatMessage]) → T`. The selection is the subject; the conversation
  is background the extractor may lean on. `ChatApplyAction` (the generic catalog type) carries this
  shape; make-ahead and every future verb inherit it.
- **The panel gains text selection over assistant messages.** Highlighting text in a reply is the
  gesture that arms the buttons; with nothing selected the catalog buttons are disabled (or fall
  back to whole-last-reply — an open sub-question below). This keeps the invariant intact — the tap
  is still the only write — while making *what* gets written precise and human-chosen.
- **Why this is an ADR amendment, not a tweak:** it changes the portable contract. Yes Chef is the
  first real instance and the proving ground that feeds galavant ADR-0031 and the eventual
  jon-platform cross-app ADR, so the `(extract → commit)` shape those inherit must be
  selection-scoped from the point it's proven here. Building it as a silent code change would let the
  cross-app pattern ossify around the wrong granularity.

### Sub-questions — resolved 2026-07-03 (Jon)

- **Empty selection behavior:** **fall back to "the whole last assistant reply."** The common case
  stays one tap; a text selection is the *precision override* when the human wants to narrow a
  multi-item reply. Buttons are never dead just because nothing is highlighted.
- **Extractor context scope:** **decided per-verb, via the action's own `extract`.** Not a global
  rule. The selection is always the subject; whether the extractor also leans on the surrounding
  conversation vs. only the selection + seeded recipe is the verb's choice (make-ahead may want the
  back-and-forth; a focused card-distill usually treats the rest of the chat as noise). The generic
  `ChatApplyAction` shape passes both `selection` and `context` so each verb can use or ignore the
  conversation.
- **Ships with the unified cooking workspace** (open-questions.md, Dogfooding 2026-07-03):
  selection-to-action is only ergonomic when chat and recipe are both visible, so this amendment is
  built **as part of the workspace effort**, not a standalone slice.
