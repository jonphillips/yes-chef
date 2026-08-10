# ADR-0053 — **Create Recipe** is a destination, not an Add dialog: material in, one reviewed recipe out

Status: **Proposed** — 2026-08-07, from Jon's product brief (drafted in an outboard ChatGPT thread while waiting
on a window, then reviewed against the code). **Answers [ADR-0051](ADR-0051-text-to-recipe-extraction-strategy.md)
OQ1** ("one entry point for paste + workbench-return + menu-note, or per-source?") — which is exactly why it is
its own ADR rather than an ADR-0051 amendment: OQ1 was left open *until paste-text was scoped*, and the answer
turns out to be a **product boundary**, not a parsing strategy. **Depends on ADR-0051** (one sink, plural
front-ends, one extraction engine) **and on its
[Amendment 1](ADR-0051-text-to-recipe-extraction-strategy.md#amendment-1--d1-was-wrong-about-capture-there-are-two-save-paths-and-the-review-surface-is-source-specific-2026-08-07)**
(the two save paths). Governed by [ADR-0047](ADR-0047-llm-capture-fallback.md) (the deterministic-first ladder
this reuses rather than re-derives), [ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) (the sink edits
structured fields), and the [[llm-vs-determinism-surface-boundary]] line. Reuses
[ADR-0046](ADR-0046-sidebar-adaptable-app-shell.md)'s shell.

**This ADR decides the destination, the trust boundary, the source seam, and where uncertainty is computed. It
deliberately does not design the UI.**

> **[Amendment 1](#amendment-1--the-entry-point-is-a-sidebar-destination-not-the-library--2026-08-07)
> (2026-08-07):** supersedes D1's entry point — Create Recipe is a **sidebar section**, not a full-screen
> destination launched from the library `+`, and the `+` is removed. D4's transient-session invariant is
> unchanged (the session is resident in memory and resumes across switches, but is still never persisted or
> synced).
>
> **[Amendment 2](#amendment-2--a-headless-transport-shortcuts--app-intent-into-create-recipe-2026-08-10)
> (2026-08-10):** builds one of the "other global entries… compatible and unbuilt" D1 named — a **Shortcuts /
> App Intent** door that lands clipboard text (a ChatGPT return, most often) in a Create Recipe session for
> review. Moves no boundary this ADR drew: same destination, same D4 trust invariant, same sink and `save(draft:)`
> path, same `CreateRecipeExtraction.extract` engine. Adds a producer-agnostic transport and a small foreground
> coordinator — **not** the routed handoff importer, and **not** a URL scheme.

## Context

**The want is small and the failure mode is not.** Jon wants to paste unstructured recipe text and get a recipe.
The naive shape — `+` → paste → parse → `Recipe` — fails in a way parser quality does not fix:
**a plausible but subtly wrong extraction looks recipe-like enough to be admitted silently into canonical data.**
The library is the trusted artifact in this app; nothing else is worth much if it can't be trusted. So the interesting decision
is not "which parser" (ADR-0051 settled that) but **where the boundary sits between material and canonical
data, and who crosses it.**

**Today the `+` means "make a Recipe row."** It presents a sheet onto `RecipeEditorView(recipeID: nil)` — a blank
structured form ([RecipeLibraryView.swift:113](../../YesChefApp/RecipeLibraryView.swift)). Web capture is a
*separate* sheet with a separate review surface and a separate commit path. There is no place in the app whose
job is "turn whatever I have into one recipe," and paste-text has no natural home in either existing sheet.

**The scope is broader than paste, and broader than import.** The same job covers typed-from-memory family
recipes, half-remembered notes ("about 2 lb thighs, lots of scallions, sauce was soy/vinegar/sugar"), a
photographed cookbook page, a pasted published recipe, and direct structured entry — often *mixed in one
session*. "Import vs. Manual" is not a distinction the cook experiences; it is a distinction the implementation
would be imposing.

**Workbench is not that place, and must not become it.** Workbench answers a different question — *given
candidates, references, experiments, observations and a goal, what should my recipe become?* Its vocabulary
(Candidate, Experiment, Observation, Learning, Working Recipe, Finalize) is useful precisely because it is
opinionated. Someone photographing a handwritten pound-cake card should not meet any of it. Workbench must also
not drift into being the app's generic bucket for "things that aren't Recipes yet."

**One shipped fact shapes the trust decision, and it cuts against the intuitive design.** The workbench's
working recipe is **already a canonical persisted `Recipe`** — `createDraftRecipe` calls
`RecipeRepository.save(draft:)` at `libraryPlacement: .reference` and stores `workbench.draftRecipeID`
([WorkbenchCore.swift:617](../../YesChefPackage/Sources/YesChefCore/WorkbenchCore.swift)); `promoteDraftRecipe`
moves it to `.main`. So the app already has a working "not ready yet" mechanism — **placement, not a draft
table.** That is a real precedent and this ADR deliberately declines it (D4).

## Decisions

### D1 — Create Recipe is a navigation destination. `+` routes there; `+` stops meaning "create a `Recipe` row."

The library's `+` remains the discoverable entry point, but it **launches creation without owning it**. Create
Recipe becomes a full-screen destination with its own lifecycle, not a sheet: the work may involve pasting bulk
text, moving between prose and structure, correcting an extraction, and several minutes of attention — all the
things a sheet's transience argues against, and the iPad's real estate argues for.

**The presentation is the cheap part and we should not pretend otherwise.** Converting a `.sheet` to a
destination later would be a small change; this ADR takes it now because it is right, not because it is
urgent. The expensive, one-way parts of this design are D4 (which save path) and D5 (the source seam) — those
are where the review attention belongs.

Other global entries into Create Recipe (share sheet, a Files hand-off) are compatible and unbuilt.

### D2 — No upfront "Import vs. Manual" choice. One environment, two views of one draft.

Create Recipe opens on a single environment holding **source/compose material** and the **structured draft**,
and the cook moves between them. It does not ask which kind of session this is, because in real use it is often
both at once: an image plus a typed correction, a paste plus remembered substitutions.

**This is nearly free for us, and that is the tell that it's the right shape.** The manual editor's entire state
is already `RecipeEditorDraft` — a plain `Equatable, Sendable` value with per-section ingredient and instruction
drafts and stable line identity, bound directly by `RecipeEditorView`. "Manual creation" and "the structured half
of Create Recipe" are literally the same type; there is no second model to build and no mode to switch.

**Do not introduce a new `RecipeContent` type.** `RecipeEditorDraft` is the authoritative recipe-content value;
`RecipeExtraction` is the shared extraction core beneath it (ADR-0051 D5). A third near-identical struct is the
duplication this decision exists to avoid.

### D3 — Workbench is not broadened into generic creation. Rejected, not deferred.

Recorded as a rejection so it is not re-proposed on the next source. Create Recipe transforms **material → a
recipe**; Workbench transforms **recipes + evidence → my recipe**. They share content, editing, validation and
save infrastructure (D6 of ADR-0051's world, and D7 below) — **not workflow, not vocabulary, not a screen.**
Workbench keeps its broader editorial licence to combine, reject, and invent; Create Recipe's default is
conservative (D7). This preserves the reason Workbench works at all ([[automation-decays-near-the-stove]]).

The one connection worth building eventually is the escalation edge — a canonical `Recipe` becoming a
workbench candidate ("I want to develop my version"). It is cheap, because candidates already reference
`Recipe.ID`s. It is **not in this ADR's slice** (D8).

### D4 — Nothing canonical until an explicit Save. The session is **transient, never persisted, never synced.**

The invariant: **untrusted source material does not silently become trusted canonical `Recipe` data.** The cook
admits the recipe to the library; the model prepares an excellent proposal.

Concretely, for the lifetime of a Create Recipe session:

- The draft lives in memory. **No draft table, local or synced.** Leaving the destination discards the session
  (with the ordinary confirmation the capture sheet already uses for unsaved review changes).
- **The `.reference`-placement precedent is deliberately not reused.** A workbench draft recipe is the cook's own
  reviewed synthesis and has earned a row; an unreviewed extraction has not. Writing one to the library as a
  reference recipe *is* the silent-admission failure this ADR exists to prevent, dressed as a feature.
- If durable sessions are ever wanted, they are **local and unsynced** on the `aiHandoffs` model
  ([[aihandoffs-local-scope-discriminator]]) — resumability on the device you are standing at is the plausible
  want; cross-device drafts are not. **This is a named non-goal, not a staging post** (D8).

**Source material outlives its interpretation within the session.** A failed OCR, a failed extraction, or a
malformed model response never destroys what the cook supplied — the material stays, retry and manual structuring
stay available, and a rejected model response is rejected whole rather than partially applied
([[loud-decode-not-in-migrator]]'s tolerate-and-report discipline, applied at the right layer).

### D5 — A minimal `RecipeSource` seam ships with the text-only V1, because it is the expensive retrofit

The session holds an **ordered list of source items**, each carrying its kind, its original content, and its
extracted text where those differ. V1 ships **`pastedText` and `typedText` only** — but it ships the *list* and
the *kind*, so that adding `image`, `url`, `document`, `sharedContent` later is an addition rather than a
rewrite of how a session stores what it was given.

**Everything else about sources is deferred** (D8). The point of this decision is narrow: do not implement paste
in a way that makes images structurally different in six weeks. Do not build the abstraction out beyond what
the two text cases need.

**Any future non-text source enters the ADR-0047 ladder, it does not bypass it.** That ladder is subtler than
"deterministic first, model second": scalars merge by priority vote (`RecipeAttributeVotes`, where
`modelPriority` loses to every deterministic source arithmetically) while ingredient and instruction **lists have
no vote ladder** and are appended — which is why `suppressingHalvesAlreadyExtracted(in:)` exists
([RecipeExtractionClient.swift:228](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/RecipeExtractionClient.swift)).
A source that produces both recognized structure and model interpretation and skips the ladder will silently
post the recipe twice.

### D6 — Uncertainty is **computed deterministically after extraction**, not self-reported by the model

The review's job is **attention allocation**: the common path is *paste → recipe appears → looks right → Save*,
and the app earns that by pointing at the two things actually worth a look rather than demanding proofreading.

**But the model does not decide what the cook is asked to check.** Self-reported uncertainty is poorly
calibrated, and handing the model that judgement is a soft form of the authority D4 denies it. So:

- **`RecipeExtraction` stays a faithful-transcription type.** No `unresolvedIssues`, no `assumptions`, no
  confidence fields on the wire.
- **A deterministic pass over the extracted structure plus the source text produces the issue list** — ingredient
  listed but never referenced, referenced but not listed, duplicated ingredient, missing quantity, unparseable
  duration, an empty half, unattributed source text. This is verifiable and fixture-testable, and it has a
  precedent: `WebRecipeCaptureWarning` (`noIngredients`, `noInstructions`, `untitledRecipe`,
  `truncatedStructuredData`) is already computed *after* the parse. Ingredient-name matching reuses the grocery
  canonicalization machinery (ADR-0022/0052) rather than a new matcher.
- **A short, named semantic residue may ride in the model's return, because determinism cannot reach it:**
  *this source contains more than one recipe*, and *this passage is a variation, not an instruction*. Nothing
  else is admitted to that list without a decision here.
- **No confidence-score UI.** "Title — 98%" implies a precision the system does not have and creates noise the
  cook cannot act on. Issues are stated as actionable sentences ("no yield was stated; Yes Chef inferred 4
  servings") or they are not surfaced.

**Detection is not intention.** "Multiple recipes found" offers a choice — create this one, create several — and
never silently becomes "let me synthesize these for you." That want is Workbench's, and the cook says so
explicitly (D3).

### D7 — Fidelity vs. authorship is a **service boundary**, not a prompt flag

ADR-0051 D3 makes extraction-vs-synthesis the axis that selects the engine, and the extraction engine already
carries the fidelity contract in its system prompt (*"Never invent a quantity, ingredient, timing, temperature,
or instruction… leave it missing"*). Create Recipe adds a genuinely new third case: the cook **explicitly
authorizes** authorship — *"I don't know the oven temperature. Suggest one."*

That must not become a mode on the extraction engine. A source whose text *is* a recipe must never route through
a client licensed to invent — that is exactly the line ADR-0051 D3 draws, and a boolean parameter is how such
lines erode. **Extraction stays fidelity-only; authorship is a separate, explicitly-invoked operation over an
existing draft**, and it is deferred (D8). When it is built, it is a verb in the existing actionable-chat
architecture (`AnyChatApplyAction`), not a bespoke surface — that architecture has two traps we have already
paid for ([[harvest-verb-requires-subject-false]], [[editable-summary-unchanged-commit-path]]) — and its
relationship to ADR-0023's `adjustRecipe` placeholder is an open question, not an assumption
([[outboard-deliberation-keep-structured-writes]]).

The rule to hold: **the model must not silently cross from representing what the cook supplied into authoring
what the cook did not.** Missing oven temperature is flagged, never filled — until asked.

### D8 — Named non-goals. None of these ship on this ADR's momentum.

Recorded so that a dispatch reading this document knows the boundary without inferring it:

- **Image / photo / OCR input, and Vision/VisionKit generally** — deferred by Jon's explicit call, 2026-08-07.
  D5 keeps the seam honest for it; nothing else about it is designed here.
- **Multi-page and multi-image sources**, layout interpretation, recognition geometry.
- **Durable or resumable Create Recipe sessions** — and *any* synced draft storage, permanently (D4).
- **The iPad source-|-draft split view.** When built, it reuses the shipped detented split workspace
  (`ChatWorkspaceDivider`: reader-only / balanced / dive) rather than a second layout architecture — so iPhone
  and iPad stay one design, which answers the brief's separate-architecture worry before it arises.
- **Conversational refinement inside Create Recipe**, and the explicit authorship verb (D7).
- **Source-to-field provenance UI** (tap a suspect field, see where it came from).
- **Share-sheet and document/PDF ingestion.** Note the share extension already exists for URLs and carries a
  known construct-don't-run sync constraint ([[extension-sync-construct-not-run]]) — it is not free.
- **URL ingestion inside Create Recipe.** Web capture already owns URLs end-to-end with a richer review surface
  (reader feedback, editorial prose, harvested labels) and a different save path for good reason
  (ADR-0051 Amd 1). Folding it in is a real decision, not a tidy-up.
- **The menu-note LLM-fallback tier.** ADR-0051 D6/OQ3 defers it *and names paste-text as its trigger* — which
  makes this ADR precisely the momentum that would swallow it. It stays deferred and separate; if built, it is
  offer-don't-impose.
- **Any convergence of `save(draft:)` and `importBundle`.** See ADR-0051 Amd 1: the split tracks import
  identity, and paste-text has none.

## Slice

**S1 — the destination + the paste-text front-end.** This *is* the already-scoped ADR-0051 paste-text dispatch,
re-homed: the front-end, engine, sink and save are unchanged by this ADR; what changes is the entry point and the
enclosing screen. Contents: the Create Recipe destination replacing the `addRecipe` sheet (D1); the compose ↔
structured draft environment over one `RecipeEditorDraft` (D2); the D5 source list with two text kinds; the
two-tier front-end (deterministic JSON-LD if the paste happens to be markup, else `RecipeExtractionClient`
faithfully) → `RecipeExtraction` → `RecipeEditorDraft` → `RecipeRepository.save(draft:)`; **the extraction runs
at the capture tier policy unchanged** (OQ2) and **assisted labeling runs on the save** (OQ3); **and the ADR-0051
D5 lift** — paste-text is the second real consumer of the extraction engine, so rename + relocate it out of the
`WebRecipeCapture` namespace and rename `structuredPageText` → `text`, deliberately, here.

**S1 opens on the structured half already usable** (OQ1) — no landing screen, no mode picker, no "Import or
Manual?".

**S2 — the deterministic issue pass (D6).** Separable and worth separating: S1 is valuable without it, and it
wants its own fixture corpus. Extends the existing capture fixtures
(`WebRecipeCaptureTests`, `RecipeExtractionTests`, `WebRecipeMilkStreetCaptureTests`) rather than starting one.

Verification per [[lean-verification-default]], plus `YesChefTests` if any app-layer model changes
([[app-test-target-not-in-verification]]). **Schema-free — both slices.** Nothing for the prod-schema promotion
list, which follows directly from D4.

## Amendment 1 — the entry point is a sidebar destination, not the library `+` (2026-08-07)

**D1 said `+` routes to Create Recipe and Create Recipe is a full-screen destination.** In the S1 device pass Jon
made a different product call: **Create Recipe is a first-class sidebar section** (`AppSection.createRecipe`),
rendered as a full-width workspace beside the collapsible sidebar — the same shell as Browser and Calendar, with
the built-in split-view toggle to hide the sidebar for full width. **The library `+` is removed entirely**; the
sidebar entry (and, on compact width, the "More" tab) is the way in. D1's own text flagged the presentation as
"the cheap part… a small change" and correctly located the load-bearing decisions elsewhere (D4/D5) — so this
amends only where the door is, not what happens past it.

**Why the sidebar wins over the modal.** A modal launched from a list frames creation as a transient interruption
of *browsing the library*; but the job is a several-minutes, own-lifecycle task (D1's own words). A resident
workspace with a collapsible sidebar fits that shape, gives the iPad its real estate without a cover, and lines up
with the sidebar-adaptable direction ([ADR-0046](ADR-0046-sidebar-adaptable-app-shell.md)) rather than fighting it.

**D4's trust invariant is fully intact — this changes *when the session clears*, not *whether it persists*.** The
session model is now **resident in memory** so an in-progress draft **resumes** across sidebar switches instead of
being discarded on dismissal; it is still **never written to a table, never synced**, and nothing is canonical
until an explicit Save. The discard trigger moves from "leave the modal" to an explicit **Clear** affordance, and
a successful **Save resets the session and jumps to the newly created recipe** in the library. D2 (one
environment, structured half immediately usable), D5 (the source seam), and D6/D7 are untouched.

**The one deliberate cost:** the `+` shortcut's discoverability is gone. Accepted — the sidebar is a stable,
always-visible home, and a redundant `+` that merely re-selects the section would reintroduce the "hangs off the
list" framing this amendment removes.

## Amendment 2 — a headless transport (Shortcuts / App Intent) into Create Recipe (2026-08-10)

**D1 named the class and left it unbuilt:** *"Other global entries into Create Recipe (share sheet, a Files
hand-off) are compatible and unbuilt."* This builds one — a **Shortcuts → App Intent** path that takes text
already on the clipboard (Jon does most ChatGPT work on iPhone/iPad, and copies the response) and lands it in a
Create Recipe session for review. It is an amendment, not a new ADR, because it **moves no boundary this document
drew**: the destination is still Create Recipe, the trust invariant is still D4, the sink is still
`RecipeEditorDraft` committing through `save(draft:)`, and the engine is still `CreateRecipeExtraction.extract`.
What it adds is a *door* and a small foreground coordinator. The load-bearing risk is not the code — it is tiny —
but that a dispatch reading a mature return-path in the codebase wires the new door to the **wrong** one. Amd2-D2
exists to prevent exactly that.

### Amd2-D1 — The transport is producer-agnostic and app-owned. The operation is *capture a recipe from text*, not *import from ChatGPT*

The semantic operation is **`CaptureRecipeFromText(text:)`**, never `ImportRecipeFromChatGPT`. ChatGPT is one
producer of text among a paste, Apple Notes, a Files hand-off, a future share-sheet. The App Intent accepts exact
input text and routes it through the existing Create Recipe extraction + review; the **Shortcut layer is transport
only** — `Get Clipboard → the intent`, and nothing else. The Shortcut does not inspect JSON, touch code fences,
decide whether text is a recipe, infer a menu or day, or write anything. Clipboard access stays *out* of the
Recipe domain: the intent takes a `String`, and the Shortcut is the only thing that knows it came from the
pasteboard.

### Amd2-D2 — It lands in **Create Recipe** (`save(draft:)`, transient session), **never** the routed handoff importer

The load-bearing routing decision, stated so it cannot drift. Yes Chef has **two** return paths, split by
identity class ([ADR-0051 Amd1-D1](ADR-0051-text-to-recipe-extraction-strategy.md#amendment-1--d1-was-wrong-about-capture-there-are-two-save-paths-and-the-review-surface-is-source-specific-2026-08-07)):

- the **routed handoff importer** — `ImportHandoffResult` → `HandoffAppOperations.stageReview` →
  `HandoffReviewCoordinator` ([HandoffIntents.swift:68](../../YesChefApp/AppIntents/HandoffIntents.swift)) —
  returns **already-decided content to an existing subject** (a recipe, a menu day, a workbench), matched by a
  `handoffID` token and reconciled against that subject; and
- **Create Recipe** — admits **a new recipe with no prior identity**, on `save(draft:)`.

A ChatGPT-authored recipe from the clipboard has **no `handoffID` and no subject**. It is Create Recipe,
categorically. Routing it through the handoff coordinator would be a category error — it would demand a token the
text does not carry and force a brand-new recipe through a surface built to reconcile against an existing one.
The maturity of the handoff machinery is precisely the trap: the dispatch must add a *sibling* intent, not reuse
`ImportHandoffResult`.

### Amd2-D3 — Reuse the shipped operation; **no new parser, no URL scheme**

The app-owned "text → recipe" already exists: `CreateRecipeExtraction.extract(text:)` — the two-tier
deterministic-JSON-LD-then-faithful-LLM engine (ADR-0051 D4, honoring the D7 guardrail). The intent feeds text
into the resident `CreateRecipeModel` through **the same seam a paste uses** (`pastedTextReceived`) and runs that
engine; it does not re-derive extraction. It foregrounds the app the way the handoff path already does — an
**`openAppWhenRun` intent plus a coordinator** ([OpenHandoffReviewIntent](../../YesChefApp/AppIntents/HandoffIntents.swift), `openAppWhenRun == true`) — **not** a `yeschef://`
URL scheme. The app has no URL scheme today (`onOpenURL` is unused), and minting one to do what a coordinator
already does is the "new navigation stack" the shell decision ([ADR-0046](ADR-0046-sidebar-adaptable-app-shell.md))
refuses. ADR-0051 D7 / Amd1-D3 apply unchanged: this **adds a front-end, not a parser and not a save path** — a
PR that forks a second "text → recipe" model call or a bespoke JSON-LD parser inside the intent is the review
block that guardrail describes.

### Amd2-D4 — Staging is transient and in-memory; it seeds the resident session and **never clobbers unsaved work**

D4's trust invariant extends to the transport: there is **no durable or synced pending-import table.** The Create
Recipe session is already resident in memory and resumes across sidebar switches (Amd 1); the intent seeds *that*
session and selects `AppSection.createRecipe`, through a small **`CreateRecipeCoordinator`** that mirrors
`HandoffReviewCoordinator` (a `present`/route entry plus the `openAppWhenRun` opener). One sharp edge the seam
must handle: `pastedTextReceived` **overwrites `composeText`**, so a Shortcut firing while the cook has unsaved
material in an open session would wipe it. The coordinator's seed path must therefore **append the incoming text
as a new pasted source without discarding the current draft** — and, if a draft is already extracted, offer the
new material rather than silently replace it. Destroying supplied material is the one thing D4 forbids
("source material outlives its interpretation"). If durable sessions are ever wanted, that is the local-`aiHandoffs`
shape D4 already names ([[aihandoffs-local-scope-discriminator]]) — **not** a new synced table built on this door's
momentum.

### Amd2-D5 — Exact source text is preserved; menu/day provenance stays deferred **and stays on the handoff path**

The transport preserves the **exact** clipboard text into the source list (`CreateRecipeSourceItem.content`
already does this), so a future provenance marker riding in the text — a `YC-HANDOFF`/menu-day token — remains
extractable later. The intent must not strip, re-encode, or normalize it. But this generic door stays
**menu-unaware**: it never picks a menu or a day, and grows no provenance schema (the D8 deferral of menu/day
association is unchanged). When that association is built, a menu-scoped recipe returns through the **handoff**
path, which already carries `sourceID`/`dayOffset` — not through this producer-agnostic door. The only
forward-compatibility obligation this slice owes is: **do not mangle the text.**

### Amd2-D6 — Error behavior rides the existing surfaces; the tolerant contract means "version mismatch" is *not* this path's concern

- **Empty clipboard** → the intent fails cleanly (nothing to stage), surfaced by Shortcuts. No session is
  opened.
- **Non-recipe or malformed text** → the extractor's existing empty/failed-extraction handling and the review
  surface show it; nothing canonical is written without the cook's Save (D4). The material is preserved (D4),
  never silently discarded.
- **No contract handshake.** The prompt's "contract/version mismatch" case belongs to the *handoff* return (the
  `YC-CONTRACT` marker + `AIHandoffReturnContract.strippingMarker`). Create Recipe is tolerant of prose and code
  fences **by design** — the deterministic JSON-LD tier falls through to the LLM engine on anything it cannot
  parse — so there is no version handshake to fail here, and **none should be added.**

### Slice — S3: the headless transport

One App Intent (`CaptureRecipeFromText(text:)`), a `CreateRecipeCoordinator` (seed-non-destructively +
select-section + `openAppWhenRun` opener) mirroring the handoff coordinator, an entry in the existing
`AppShortcutsProvider`, and the "Faster return path with Shortcuts" operator-doc section. Reuses
`CreateRecipeExtraction.extract`, `CreateRecipeModel.pastedTextReceived`/`extractButtonTapped`, and
`AppSection.createRecipe`. **Schema-free** — the session is D4-transient, so nothing is owed to the prod-schema
promotion list. iOS 27 deployment target means modern App Intents throughout: extend the existing provider, no
SiriKit-era patterns, no deprecated intent lifecycle. Verification per [[lean-verification-default]] plus
`YesChefTests` (this is an app-layer coordinator/model change, [[app-test-target-in-verification]]); the intent
and the coordinator's non-clobber seeding are the unit-testable core — the Shortcut itself is not tested.

## Open questions

- **OQ1 — is there still a fast path to a blank structured form?** Someone typing a family recipe from memory
  wants the form, not a compose box. **Resolved 2026-08-07 (Jon): no separate entry.** Create Recipe is the one
  door, and it opens with **both affordances present and the structured half immediately usable** — a cook who
  wants to type a recipe starts typing into it, and never sees a mode question. This is D2 taken literally:
  there is no landing screen to choose from, because there is no choice to make. The affordance to *revisit* is
  layout, not routing, and it can move once the real screen exists.
- **OQ2 — the extraction tier default for paste** (frontier vs on-device). **Resolved 2026-08-07 (Jon):
  frontier — by reusing capture's existing tier policy verbatim, not by adding a constant.**
  `RecipeExtractionClient` already resolves through `resolveTier(useFrontier: tierPreference.current(), …,
  requirement: .onDeviceCompatible)` on ADR-0047 OQ1's reasoning: *a capture is low-volume and user-initiated,
  so it prefers the strongest configured model.* A paste is the same shape, so **paste inherits that path
  unchanged** — which means the cook's tier preference still governs ([[personal-app-latency-tolerance]]: tier
  belongs in settings, not in code constants), a key-less frontier preference still degrades to on-device and
  records an honest `.degradedToOnDevice` rather than claiming a provider the cook no longer has a key for, and
  extraction still degrades rather than fails. **Adding a paste-specific tier constant would be a regression**,
  not an implementation of this decision.
- **OQ3 — does assisted labeling (ADR-0049) run on a Create Recipe save?** **Resolved 2026-08-07 (Jon): yes —
  reuse `labelProposer`.** It is the same "a recipe is entering the library" moment capture already treats this
  way, and the proposal is *offered pre-save and accepted by the cook*, so it sits on the right side of D4's
  trust boundary and of [[llm-curation-not-synthesis]]. Note the asymmetry this leaves deliberately: the plain
  manual editor still does not propose labels. That is fine — the editor is usually *editing*, not admitting a
  new recipe — and it is not a defect to go fix on this ADR's momentum.
- **OQ4 — where does "Start Workbench from this Recipe" live** (D3's escalation edge)? Deferred with the edge
  itself.
- **OQ6 — when the Shortcut fires with a session already in progress, seed-and-append or open a fresh session?**
  (Amd 2.) Amd2-D4 fixes the **invariant** — unsaved material is never destroyed — but not the **product** choice
  between appending the incoming text to the open session and starting a clean one (the open draft parked, not
  lost). *Lean: seed-and-append when the open session is empty (`CreateRecipeModel.isEmpty`), and when it is not,
  surface the incoming text as a new pasted source the cook can accept or discard* — no silent replace either way.
  Also open: does the intent **auto-run extraction** on a fresh seed (so the app foregrounds on the reviewed
  structured draft, not a raw compose box)? *Lean: yes on a fresh session, never over existing unsaved work.*
  Resolve on Jon's device pass.
- **OQ5 — does Create Recipe eventually absorb the workbench-return and menu-note entries?** ADR-0051 OQ1's
  residue. *Lean: no.* Both have a subject they belong to (a workbench, a menu) and arriving via the library's
  `+` would be the wrong door. Revisit only if a third free-text entry appears with no subject of its own.

## Related

- [ADR-0051](ADR-0051-text-to-recipe-extraction-strategy.md) (the strategy this is a consumer of; **this ADR
  answers its OQ1**) and its Amendment 1 (the two save paths, the source-specific review surface),
  [ADR-0047](ADR-0047-llm-capture-fallback.md) (the deterministic-first ladder and its list/scalar asymmetry),
  [ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) Amd 2 (extraction ≠ synthesis),
  [ADR-0036](ADR-0036-promote-note-to-recipe.md) (the menu-note front-end that stays separate, D8),
  [ADR-0023](ADR-0023-recipe-edit-proposals.md) (where the authorship verb would land, D7),
  [ADR-0049](ADR-0049-unified-labels-and-assisted-tagging.md) (OQ3),
  [ADR-0046](ADR-0046-sidebar-adaptable-app-shell.md) (the shell the destination lives in).
- Memory: [[workbench-draft-extraction-seam]], [[llm-vs-determinism-surface-boundary]],
  [[editable-at-the-grain-stored]], [[automation-decays-near-the-stove]] (D3),
  [[aihandoffs-local-scope-discriminator]] (D4's shape if durability ever arrives),
  [[llm-curation-not-synthesis]] (D6), [[harvest-verb-requires-subject-false]] and
  [[editable-summary-unchanged-commit-path]] (D7's traps), [[synced-table-cost-calibration]] (why D4 is a
  *product* refusal, not a cost one — a table would be cheap; admitting unreviewed data is not).
