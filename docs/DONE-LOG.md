# Done Log

Archive of completed efforts, the implemented-behavior checkpoint, and strategic
background. **Read-rarely, append-on-approval.** No dispatch instruction should ever
point the coding agent (or the architect during a dispatch) at this file — it is a
human-reference archive, not a working-context source. `docs/CURRENT_HANDOFF.md` stays
lean precisely because this history lives here instead.

Newest first.

---
## ADR-0042 Amd 3 — Recipe JSON-LD v2 capture contract

**Merged 2026-08-09; PR [#302](https://github.com/jonphillips/yes-chef/pull/302). No schema. Jon's device pass
owed.** Late-bound Recipe capture (ADR-0042 Amendment 3): an external Project conversation can emit a durable Recipe
*product* midstream and keep going, without a `YC-HANDOFF` row. New `RecipeJSONLDContract` centralizes the versioned
(v2) Project source, the self-contained handoff output instructions, and a thin `captureRequest()`;
`WorkbenchChatContext` now sources its output shape from it instead of an inline literal. v2 adds the namespaced
`yesChef:ingredientSections` so named ingredient groups round-trip while `recipeIngredient` stays the complete flat
schema.org interop fallback (no fake heading rows). cuisine/course thread through `RecipeExtraction`, the parse
builder, and the editor draft to the canonical save. Top-level `HowToStep` entries now coalesce into one unnamed
instruction section instead of one-section-per-step — which also fixed a latent web-capture bug; the King Arthur and
Allrecipes real-shape fixtures were corrected. App: "Copy Recipe Contract Source" (AI Settings) and "Copy Recipe
Capture Request" (Menu) actions. Verified: `swift test` full package suite green (640 tests). **Follow-ups (not
queued):** `captureRequest(recipeName:)`'s named path is unwired — the app always emits the generic "ask me which
recipe" variant; the extractor trusts `yesChef:ingredientSections` wholesale and matches the literal namespaced key,
safe under the controlled Project contract but a fidelity assumption.

---
## ADR-0050 S2 — Power Browser surface

**Built 2026-08-09; PR [#301](https://github.com/jonphillips/yes-chef/pull/301). No schema. Jon's iPad device pass
owed.** The Power Browser is now its own app-shell tab, deliberately distinct from the Safari web-capture Browser
(ADR OQ1 resolved); it is hidden from the compact tab bar until S5 provides the phone presentation. Its balanced
split keeps ranked, contextual facets alongside results: the top available facet opens initially so counts are
immediately useful, selection chips use full hierarchy names to disambiguate values, and search, sort, Clear, and
recipe-detail routing are all present. The balanced split is intentional: facets and results are peer working
areas, rather than the master/detail pattern that needs a Focus visibility toggle.

**The model owns the performance boundary.** `RecipeBrowserDataRequest` observes the engine's raw inputs;
`PowerBrowserModel` rebuilds its `RecipeBrowserEngine` only when that `Equatable` data changes and memoizes the
result for the current query. The view reads that result once and passes it to both panes, avoiding a duplicate
engine construction and availability pass for each keystroke or chip toggle. Rich recipe rows remain separately
observed and are mapped from engine result IDs. Focused model tests cover selection, Clear defaults, and one-time
initial facet expansion; the existing S1 Core suite covers query semantics. Verified before review: `xcodegen
generate`, targeted SwiftLint (0 violations), elevated generic iOS build, and `YesChefTests` (44 tests / 15 suites)
all passed.

---
## ADR-0050 S1 — Power Browser query engine

**Merged 2026-08-09; PR [#299](https://github.com/jonphillips/yes-chef/pull/299). No schema, no device surface (that
is S2).** The headless query engine: `RecipeBrowserQuery`, descendant matching, OR-within/AND-across semantics,
matching-id retrieval, self-excluding counts, availability + deterministic ranking. Pure Core. Amd4-OQ1 is answered
in code — `RecipeBrowserQuery` indexes variation names as text-search aliases and does **not** expand related-recipe
edges (`variationNamesAreTextSearchAliasesWithoutExpandingRelatedRecipes`). **Architect review caught a D4 defect:**
self-excluding facet counts collapsed for any facet without a selection — each value unioned against the *full*
result set, so for an unselected facet every value's count became `|result|` and the discrimination filter hid the
whole facet (an empty query offered zero facets; selecting one facet hid every other). The four original tests
passed only because each selected *every* facet — the one arrangement where the full result is the right union base.
Fixed to union against only recipes carrying a currently-selected value of that facet; added empty-query and
single-selection availability regression tests. Verified: `swift test` full package suite green (636 tests).

---
## ADR-0046 S2 — the chat presentation merge

**Built + architect-reviewed 2026-08-08; PR [#298](https://github.com/jonphillips/yes-chef/pull/298) (the doc bump
rides in it). No schema. Jon's device pass owed.** The deferred second half of ADR-0046: with all eight sections
now living in per-tab layouts, reconcile the wide-width chat presentations to one. **Jon's product call: inspector
everywhere on wide iPad** (not the detent split, not don't-merge), and **no Calendar/Workbench cold-start
starters** (they keep `.none`). The bespoke `ChatWorkspaceSplit` + `ChatWorkspaceDivider` + `ChatWorkspaceDetent`
(reader-only/balanced/chat-dive draggable divider, its `@AppStorage` detents, the width math) is **deleted**;
**Calendar, Workbench Detail, and Workbench Compare** now route through the same `.inspector` presentation Recipe
already used, via a shared `recipeChatInspector` view modifier and `ChatInspectorMetrics` (which absorbs the old
`RecipeAskSlideOverMetrics` 320/380/480 range). Compact iPhone still gets the modal sheet. **Tier propagation is
preserved** — `.embeddedHeader` reports `panelOwnsActiveTierPropagation`, so `RecipeChatPanel` now drives
`compareTier` from its own `onAppear`/`onChange(of: activeTier)` where the split used to; **live context refresh
is preserved** (an open inspector's chat re-reads workbench context on each `dateModified` bump without a standing
full-extract fetch).

**Architect review caught a double-presentation defect the sim-less build could not.** S2 made the Workbench
Detail **Ask** button unconditional (it was `if !isSplitEnabled` before), so on regular-width iPad tapping Ask now
sets `destination.chat` *while the split is enabled* — but the pre-existing compact `.sheet(item:
$model.destination.chat)` was left ungated, so the inspector **and** the modal sheet both presented over the same
`RecipeChatModel`. Calendar and Compare already gated their fallback sheet with `isChatInspectorEnabled ?
.constant(nil) : …`; Workbench Detail was the one that didn't. Fixed by the same guard
(`isSplitEnabled ? .constant(nil) : $model.destination.chat`). **Folded in the same PR:** the now-unreachable
chat-surface contract — `Presentation.column`, `ChatSurfaceResolution.DetentIdentity`, and the host-owned
`Dismissal` case no factory can produce — was removed so the type stops advertising a presentation no host can
construct ([[withdraw-not-defer-orphaned-schema]]). Verified: elevated generic iOS build green, `ChatSurface`/
`ChatSurfaceResolution` tests green, `check-drift.sh` green except one **pre-existing, unrelated** red
(`DatabaseBackupTests.restorePreparationForwardMigratesAGenuineNMinusOneBackup`, a migration test already failing
on the branch head independent of this diff — flagged to Jon).

---
## ADR-0046 S1 — the sidebar-adaptable app-shell container

**Built + architect-reviewed + merged 2026-08-08; PR [#297](https://github.com/jonphillips/yes-chef/pull/297). No
schema. Jon's device pass owed (under dogfood).** One `TabView(selection:).tabViewStyle(.sidebarAdaptable)` with a
`Tab` per `AppSection` replaces the old size-class fork — the compact `AppCompactTabView` **and** the four
regular-width `NavigationSplitView` branches — collapsing the four-way taxonomy (`AppSection` / `AppCompactTab` /
`AppMainColumnSection` / the hand branches) to the single `AppSection` source of truth, and giving the free system
sidebar⇄tab-bar toggle. Each tab owns its own internal layout and its **own** `@State columnVisibility` (no
cross-tab focus bleed); the four secondary sections carry `.defaultVisibility(.hidden, for: .tabBar)` to replicate
"primary 4 + More" without a lossy enum; `TabViewCustomization` persists reorder/hide/pin. The workbench/menu
`navigationPath` More-stacks are gone — deep-links now drive split selection — and `AppContainer`'s full-screen
covers still present above the `TabView`.

**Architect review before the device pass caught a defect class Codex's sim-less build could not:** the three
single-column tabs had no navigation container. **Calendar** was wrapped in `NavigationSplitView { EmptyView() }`,
which rendered a blank leading pane on iPad and a **fully blank screen on iPhone** (a collapsed split shows its
empty root, never the detail) — rewritten to a single-column `NavigationStack` (the workspace adapts to width on
its own; Calendar loses its now-meaningless Focus button, Jon's live-with-it call). **Create Recipe** and
**Browser** were bare tab children, so Create Recipe lost its title **and its Clear/Save buttons** — both now
wrapped in `NavigationStack`. Dead `MealCalendarPlannerView` + `AppSection.label` removed. Verified: elevated
generic build + `YesChefTests` 40/40 green. **S2 (the chat presentation merge) is briefed and queued** behind this
device pass; see [`efforts/sidebar-adaptable-shell.md`](../efforts/sidebar-adaptable-shell.md).

---
## ADR-0021 Amendment 4 V4b — the synced related-recipe edge table

**Built + architect-reviewed + merged 2026-08-08; PR [#293](https://github.com/jonphillips/yes-chef/pull/293). Joins the prod-schema promotion list; Jon's two-device sync pass owed (back up first).**
The second half of the Playbook "Choices" section: a **synced `recipeRelatedRecipes` table** of symmetric peer
edges linking two recipes. Both recipe IDs are intentionally **loose columns** — an edge has no owning recipe, and
a second SQL FK would violate the CloudKit single-FK sharing rule ([[sqlitedata-single-fk-sync-limit]]). Every
writer stores the same undirected edge via a **canonical lowest-UUID pair**; offline duplicates **converge
deterministically on the lowest edge UUID** at the next link; unlink removes every copy; reads dedupe and **order
by name — OQ2 resolved, no ordering column** ([[recipe-variations-overlay]]). **Split-off links the new standalone
recipe to its former base** in the same transaction (the "get more involved → promote it" release valve).
Registered in `CloudSync`.

**Architect review caught and Codex refixed a reintroduced writer convoy.** The link picker first held an
always-on whole-library `@Fetch(RecipeListRequest())` on `RecipeDetailModel` — a heavyweight fetch (thumbnail
BLOBs and all) that re-ran synchronously on the writer on every recipe edit, exactly the ADR-0029 Finding 8
pattern PRs #148/#149 killed ([[sqlitedata-fetch-writer-convoy]]). Refixed to an **on-demand scoped read**
(`relatedRecipePickerRows`, never touches `recipePhotos`) fired when the picker opens, onto the model's
swift-navigation `Destination` enum instead of a `@State` boolean. Two dead indexes were dropped. Core tests cover
symmetry, idempotency, offline-duplicate convergence, unlink, split-off linkage, and the lightweight picker rows.

**Amd4-OQ1 answered (architect, 2026-08-08): list/browser indexing stays unchanged.** Whether `RecipeBrowserQuery`
indexes variation names or related-recipe edges is a **Power Browser (ADR-0050) product decision** — that ADR is
still proposed and defines no semantics, so this slice does not silently invent a synced query contract
([[withdraw-not-defer-orphaned-schema]]). **Amendment 4 is now COMPLETE** — V4a, V4b, and V4c + Delete all shipped.

---
## ADR-0052 S1+S2 — the synced grocery learned store-area table

**Built + architect-reviewed + merged + device-passed 2026-08-08; PR [#292](https://github.com/jonphillips/yes-chef/pull/292). Joins the prod-schema promotion list.**
Store-area classification used to be recomputed every generation, so a cook's correction never stuck and re-runs
drifted. Now a **synced `GroceryAreaAssignment` table** (append-only create, no data pass —
[[migration-writes-bypass-sync-triggers]] doesn't bite an empty create) makes a name **classified once ever**, then
served by a free deterministic lookup, and corrections **persist across generations and devices**
([[grocery-area-no-learned-cache]]).

**Precedence is a fixed ladder — user > seed > model.** A `.user` correction always wins; `seedAreas` stays a code
constant read at classify time (the middle tier, **not** migrated into the table); the classifier's own answer is
the floor. On first classification of an unseen name the classifier **auto-promotes its answer as `.model`**; a
correction writes a `.user` row that outranks it and purges the matching `.model` row; correcting *to* the seed
area deletes the learned rows and reverts to seed. Duplicate rows (offline races) reconcile deterministically at
read time by source then `dateModified`. The read path stays deterministic — **ADR-0022 holds** (the "slug"
naming is a stale misnomer kept only as the link anchor). Registered in `CloudSync`.

**The last `.low`-effort LLM site closed.** The grocery categorizer went `.low → .high` with the response budget
raised 1,024 → 2,048 so reasoning doesn't starve output ([[reasoning-budget-starves-output]],
[[personal-app-latency-tolerance]]). The device pass cleared both watch items — unusual ingredients come back
classified under the new budget, and a corrected unusual ingredient persisted after regeneration and synced across
two devices with no second model call.

**S3 remains (not designated):** repoint ADR-0037's seed-coverage view to **audit** the `.model` rows (amends,
never deletes). Also un-fixed **by design**: stale `.model` rows from offline dup races are only ever GC'd by a
`.user` correction — harmless at ~10 users.

---
## ADR-0053 S2 — the deterministic extraction issue pass (D6)

**Built + architect-reviewed + merged + device-passed 2026-08-08; PR [#291](https://github.com/jonphillips/yes-chef/pull/291).**
The D6 issue pass: a pure, fixture-tested `RecipeExtractionIssueDetector` over the extracted structure + source
text — missing title/halves/quantity, unparseable duration, duplicate ingredient, listed-vs-referenced mismatch,
unattributed source — surfaced as **review cues** in Create Recipe, with **no confidence scores and no model
self-report** (attention allocation, not proofreading). Duration parsing was consolidated onto
`RecipeDurationParser`, and the session now captures **typed-vs-pasted** source distinctly and preserves it across
a failed extraction (closing the S1 provenance gap).

**Architect fixes rode in `9cfa4fb`:** the `DatabaseBackupTests` migration-tail, and two masked-red
`CreateRecipeModelTests`. The `YesChefTests` target can't run in Codex's sim-less sandbox, so its "couldn't run
the app tests" is structural, not a regression — but it hid two genuinely red tests (missing `bootstrapDatabase()`
→ `RecipeEditorModel`'s eager `@Fetch` tripped SQLiteData's blank-DB reporter), fixed by the architect running the
target locally ([[codex-build-excuse-reproduce]]).

**Two review notes were checked on the 2026-08-08 device pass; neither warranted an **ADR-0053 S2.1** (not
designated).** They stay documented in case real use reopens them: (1) **cue noise** — `missingIngredientQuantity`
+ `ingredientNotReferenced` can fire for staples (salt, pepper, oil, "to taste", garnishes), in tension with D6's
"attention allocation, not proofreading"; the fix if it reopens is to suppress staples from those two categories.
(2) **`unattributedSource` points at a source with no UI** (the source list is D8-deferred) — gate that cue until
the source list surfaces.

---
## ADR-0053 S1 — Create Recipe destination + paste-text front-end

**Built + architect-reviewed + merged + device-passed 2026-08-08; PR [#290](https://github.com/jonphillips/yes-chef/pull/290).**
Re-homes Jon's "paste unstructured recipe text and create a recipe" want as the **Create Recipe** destination,
answering [ADR-0051](decisions/ADR-0051-text-to-recipe-extraction-strategy.md)'s OQ1 and built to its
one-sink / plural-front-ends / one-engine strategy. **Schema-free** — the session is transient and never synced
(D4), so **nothing on the prod-schema promotion list.**

**Core.** The **ADR-0051 D5 lift** landed at the second real extraction consumer: `RecipeExtractionClient` moved
out of the `WebRecipeCapture/` namespace to a source-neutral home, vestigial `structuredPageText` → `text`, the
one live caller (`WebRecipeCaptureClient`) updated. `RecipeExtraction.editorDraft(uuid:)` maps the shared
extraction core onto `RecipeEditorDraft`, the single terminal sink; `CreateRecipeExtraction` is the two-tier
front-end (deterministic schema.org/JSON-LD first, faithful LLM engine otherwise); `CreateRecipeSourceItem` is
the D5 source-list seam (`pastedText`/`typedText` kinds), shipped small so images are a later addition, not a
rewrite.

**App.** `CreateRecipeModel` / `CreateRecipeView` — one screen, compose material + structured draft, the
structured half immediately usable (D2/OQ1). Transient session, nothing canonical until Save; a failed
extraction preserves the material and surfaces a loud error. Tier reuses capture's policy verbatim (OQ2). Labels
propose after a successful extraction, accepted by the cook, written facet-aware in the same write as
`save(draft:)` (OQ3). Save commits through `save(draft:)` — the app-authored identity class (ADR-0051 Amd 1),
no `importBundle`, no third save path. The editor's `Form` was extracted into a reusable `RecipeEditorFields`
so `RecipeEditorView` and `CreateRecipeView` edit **one** draft implementation.

**Amendment 1 (2026-08-07, commit `9c0e738`) supersedes D1's entry point.** Create Recipe is a first-class
**sidebar destination** (`AppSection.createRecipe`), rendered full-width beside the sidebar like Browser/Calendar
— **not** a full-screen destination off the library `+`, and the recipe-list `+` is removed. The session model is
**resident** (an in-progress draft resumes across section switches, still in-memory only — D4 intact), a **Clear**
affordance resets it, and after Save the app **jumps to the new recipe**.

**Follow-up refinements (later commits on the branch).** Step segmentation: the model was emitting
colon-terminated list continuations as separate numbered steps; the sink mapping now flattens internal line
breaks and the **shared** extraction prompt gained step-granularity guidance (which also improves web capture —
hence the owed capture re-check).

**S2 (deterministic issue pass, D6) shipped separately in PR [#291].**

---
## ADR-0042 Amendment 2 — `workbenchDraft` hand-off (S3a + S3b): draft a working recipe outboard

**Built + architect-reviewed + device-passed 2026-08-07; PR [#289](https://github.com/jonphillips/yes-chef/pull/289).**
Un-defers ADR-0042 S3 on a *cost* want (draft against a flat-rate ChatGPT/Claude subscription instead of the
metered onboard synthesis). **Schema-free** — `AIHandoff` is device-local, so **nothing on the prod-schema
promotion list, no `YC-CONTRACT` bump.** The first path built to [ADR-0051](decisions/ADR-0051-text-to-recipe-extraction-strategy.md).

**What it does.** The Working Recipe section gains a **Copy Draft Prompt + Paste** door (gated on the onboard
verb's own conditions: no working recipe yet, ≥1 candidate). The outboard argues a draft out and `finalize`
returns a schema.org `Recipe` **JSON-LD** block + a separate prose rationale block. The return is **extraction,
not synthesis** — the existing deterministic `RecipeJSONLDExtractor` parses it **for free** (new raw-block
entry `extract(fromJSONLD:)`, no synthetic `<script>`), into `WorkbenchDraftRecipe` → the **existing** draft
review sheet → `createDraftRecipe` (Create Working Recipe → Promote). Learnings deposit to the workbench log as
an `.observation` row. A declined/empty draft degrades **loud** (`.emptyPlan`).

**The hand-run finding that shaped S3b.** The paste path autoformats JSON delimiters into typographic/curly
quotes — the transport-level mangling Amd2-OQ3 anticipated — and the old `cleanedJSON` salvage would *not* have
rescued it (it **deleted** curly quotes, leaving invalid unquoted JSON). Fixed deterministically: the salvage
now **replaces** curly doubles with `"` and curly singles with `'` (so `Cook's` survives), no metered rescue.

**Architect-review fixes before approval (all with regression tests).** (1) The outboard door was ungated —
it invited a round trip that could only fail with `draftRecipeAlreadyExists`; now gated. (2) A draft that
omitted the rationale block (argued it in-thread) was discarded whole; the declined test is now the ADR's — *no
ingredients and no instructions* — and a missing rationale stages as an empty field, with the recipe and
learnings as independent review items; a rationale written *before* the JSON is also recovered. (3) Ingredient
group headings were silently deleted; now re-inlined as colon-terminated lines the editor reads back
(ADR-0040 lossless). (4) A stray Markdown code fence leaked into the rationale; now stripped. (5) Shared the
learnings review item with the compare verb.

**Resolved (recorded in the ADR).** Amd2-OQ1 — keep the two-part return (the real learnings were dish
constraints / rejected candidates, not restatement). Amd2-OQ3 — the paste path *does* mangle JSON-LD; the free
deterministic curly→straight salvage handles it, loud fallback, no metered rescue. Amd2-OQ4 — a raw-block
extractor entry point, not HTML-wrapping.

**Verified.** Core `swift build` + 13 `workbenchDraft` tests (curly-quote round-trip, declined-loud,
malformed-past-salvage, ingredient-heading re-inline, missing-rationale-stages, rationale-before-JSON,
fence-strip, JSON-LD/rationale split) + 143 in the AIHandoff/Workbench/capture filter; elevated
`generic/platform=iOS` build; `YesChefTests` app-target suite (35 tests / 12 suites, incl. a new review-staging
test); `scripts/check-drift.sh` clean of the S3 files. **Device gate: PASSED 2026-08-07** (Jon). Note: the
draft's instruction `HowToSection` groupings flatten (single instruction section by construction); the
`learnings + unparsedLines` combine is a flagged verb-local patch of the known `learningBullets` floor bug.

---
## ADR-0021 Amendment 4 V4c — the two structural step ops + a variation Delete affordance

**Architect review 2026-08-06.** Decision: [ADR-0021](decisions/ADR-0021-recipe-variations.md) Amendment 4
(D4), plus a gap-fill Delete that Amd2-D4 already sanctioned but that was never built. **Schema-free** — both
halves ride the existing `deltas` BLOB and an existing synced row, **no prod-schema promotion entry**. Spec:
[`efforts/adr-0021-v4c-and-variation-delete.md`](efforts/adr-0021-v4c-and-variation-delete.md). Gate was
anchor-repair Dispatch 1 (read-lenient / write-strict), cleared 2026-08-05.

**What it does.** A variation can now **add and remove instruction steps**, which is what forced Jon's
motivating case (one technique, several treatments, a different finishing step each) out of the variation model
entirely. The vocabulary widens by exactly two anchored ops — `stepInsert(after:sectionID:text:)` and
`stepRemove` — reusing `RecipeMethodStepReplacement`'s base-step anchoring so they normalize write-strict and
backfill read-lenient through the *existing* repair queue rather than a second one.
`instructionStepAdded`/`instructionStepRemoved` leave `RecipeVariationUnrepresentableEdit`; `instructionStepMoved`
and every section op stay unrepresentable and still route to split-off. In the reader an inserted step renders as
an addition and a **removed step stays visible, struck through and unnumbered**, so the base procedure is legible
underneath the overlay (D3) instead of silently vanishing. Separately, the Choices menu finally has **Delete**,
behind a confirmation.

**Three architect-review fixes before approval.**
1. **An inserted step silently changed section.** The op carried no section, so resolve gave the new step its
   *anchor's* section — and a step added at the head of a section anchors to the last step of the section
   *above*. Derive→resolve identity was broken for every multi-section recipe (and for the "Base Recipe"
   restore variation that promote mints), and it passed green because the tests only covered a single-section
   base. The op now carries its own `sectionID`, mirroring the ingredient `add` op, and degrades to the
   anchor's section when that section is gone — placement is a hint, the step anchor is the thing that must
   resolve.
2. **The Delete confirm was the [[alert-ispresented-destructive-setter]] shape** — the `isPresented` setter
   discarded the staged variation the action was about to read. Restated with `presenting:` so the value is
   handed *into* the closure. That shape shipped ADR-0030's restore dead through three reviews; a silent no-op
   on an irreversible destructive action is exactly where it must be impossible, not merely unlikely.
3. **Removed steps had no reader affordance** — resolution drops them, so they just disappeared, which is the
   opposite of what a removed *ingredient* does. The reader now splices them back at their base position.

**Verified.** `swift test` (595 tests) and `scripts/check-drift.sh` pass except for
`DatabaseBackupTests.restorePreparationForwardMigratesAGenuineNMinusOneBackup`. Elevated generic-iOS app build
green after `xcodegen generate`. The `YesChefTests` app target adds two **new app-level tests** — both passing —
that drive the model + display seam rather than Core alone, which is the seam that hid both the section drift
and the ADR-0030 restore defect.

**⚠️ `main` is currently red in two places, neither caused by this slice** (both reproduce on a stashed,
clean tree): the `DatabaseBackupTests` migration-ordering failure above, and **5 app-target failures** in
`RecipeCaptureLabelSuggestionTests` / `RecipeDetailLabelSuggestionTests` / `RecipeListPresetTests` /
comment-curation, all tripping the unimplemented-`uuid` dependency trap. Worth its own fix before they
normalise into background noise. Jon's device pass still owed, with the cross-device case worth exercising by hand:
Delete syncs the row but the active-selection highlight is per-cook, so a peer whose local selection points at
a deleted variation must degrade to base (covered by a Core test, but it is the non-obvious edge).

---
## ADR-0021 Amendment 4 V4a — variations relocate to a Playbook "Choices" section

**Approved (architect review) and merged 2026-08-05; PR [#285](https://github.com/jonphillips/yes-chef/pull/285).**
Decision: [ADR-0021](decisions/ADR-0021-recipe-variations.md) Amendment 4 (V4a). **App-only, schema-free**
(scoped via the local `aiHandoffs.variationID` discriminator — [[aihandoffs-local-scope-discriminator]] — no
prod-schema entry). Device-passed 2026-08-05.

**What it does.** Relocates the variation picker out of the recipe Body and into a proper Playbook **Choices**
section (Amd4-D5), rendering variations as a list with name + description + the full action set, above Notes.
Selecting a variation folds it into Directions and surfaces a **Return to Base Recipe** control there (the only
deselect affordance — there is no Base row in Choices, by design). The variation-scoped hand-off round-trips:
**Hand Off** from a variation's Choices menu, bring a revision back, and **Save Variation** re-derives *that
variation* (not the base); a **Paste** whose token no longer resolves still lands scoped to the right variation
(the unmatched-fallback fix). Base-recipe adjust is unchanged.

**Verified.** Core `swift build` + variation suites; the elevated generic-iOS app build green after
`xcodegen generate` (the first push added two `YesChefApp/` extension files without regenerating, so the app
target could not have compiled — architect caught it and re-ran locally, fixed in `5388e31`; a build-claim
tripwire now recorded in the Verification Pattern, [[codex-build-excuse-reproduce]]); `scripts/check-drift.sh`
green. **Device gate: PASSED 2026-08-05.**

**Remaining in ADR-0021 Amd 4 (Next Up):** V4b (related-recipe edge table — the Choices section's second half,
the schema slice, two-device pass owed) and V4c (the `stepInsert`/`stepRemove` step ops, gate cleared by
anchor-repair Dispatch 1).

---
## variation-anchor-repair Dispatch 1 — `resolved(applying:)` degrades instead of throwing

**Approved (architect review) 2026-08-05; branch `codex/variation-anchor-repair-dispatch-1`** (Codex ran out of
tokens; architect completed the handoff-site fixes + verification). Spec:
[`efforts/variation-anchor-repair.md`](../efforts/variation-anchor-repair.md). **Core + app-layer read surfaces,
no schema.** **Unblocks ADR-0021 Amd4 V4c** (the `stepInsert`/`stepRemove` step ops).

**What it does.** Dispatch 0 stopped *new* dead anchors and repaired the resolvable legacy ones, but a single
unresolvable anchor still made `resolved(applying:)` **throw**, taking out that recipe's editor, reader fold, and
grocery contribution. Dispatch 1 splits resolution into *read-lenient / write-strict*. `resolved(applying:)` now
returns a `RecipeVariationResolution` (the partial detail with every still-exact op applied, plus a
`unresolvedAnchors` repair queue) instead of throwing on the first orphan; `variationIngredientHighlights` and
`fetchDetailApplyingActiveVariation` carry the same queue. **Every write path opts back into strict behavior via
`.requiringAllAnchorsResolved()`** — variation create, base re-derive + siblings, proposed-base validation, and
the app overwrite — so no write can silently drop an op. Read surfaces are **loud**: the reader and the variation
editor render a `RecipeVariationRepairNotice` (the editor also blocks Save), and grocery generation stamps the
source subtitle `"Variation: <name> (needs repair)"`.

**Handoff sites (architect fix).** The two variation-scoped hand-off reads —
`HandoffReviewCoordinator.draftRecipeAdjustment` (in-app LLM adjustment base) and
`HandoffAppOperations.exportedRecipeAdjustmentHandoff` (the outbound Shortcuts/AppIntent export) — had no repair
UI of their own, so feeding an LLM a silently-partial recipe would violate lossless-or-loud. They now **block on
`requiresRepair`** with tailored errors (`HandoffReviewError.variationNeedsRepair`,
`HandoffIntentSurfaceError.variationNeedsRepair`) telling the user to repair the variation first — consistent with
the editor's Save gate. Cosmetic: a stray blank line in `RecipeDetailView` removed.

**Verified.** Core `swift build` + all variation/grocery/resolution suites pass (incl. the new
`RecipeVariationResolutionTests`, which asserts the partial-apply + grocery `(needs repair)` stamp); the elevated
generic-iOS app build is green (exit 0); `scripts/check-drift.sh` is green. **Dispatch 2 (the repair UI that lets
the user re-anchor or drop an orphaned op) remains** — until it ships, the repair queue is surfaced but not yet
directly actionable in-app (repair happens by editing the base back or promoting/splitting the variation).

**Rode along (pre-existing drift, unrelated to anchor-repair).** `RecipeCaptureLabelSuggestionTests` called
`ParsedRecipePage(categoryNames:tagNames:)` in the wrong argument order — a stale test left by the ADR-0049 facet
arc (PRs #275–#282), which the SQLiteData `Ld` wall had been masking by short-circuiting `check-drift`'s
build-for-testing before it reached the test compile. One-line reorder to match Core; flagged so the masking
pattern is on the record ([[exported-import-not-link-time]]).

**Device gate: PASSED 2026-08-05.**

---
## variation-anchor-repair Dispatch 0 (+3) — anchors normalized to base IDs, backfill, loud-at-save

**Approved (architect review) 2026-08-05; PR [#284](https://github.com/jonphillips/yes-chef/pull/284), branch
`codex/variation-anchor-repair-dispatch-0`.** Spec:
[`efforts/variation-anchor-repair.md`](../efforts/variation-anchor-repair.md). **Core-heavy + a small app-layer
touch, no schema, no prod-schema entry** (`recipeVariations` was already on the promotion list); a backfill data
pass, **device-passed 2026-08-05**.

**What it does.** Closes the standing ADR-0021 data-loss defect (found on device 2026-08-01). A variation's
ingredient/method anchors were copied verbatim from model output and never normalized to base row IDs, so
correcting a typo in a base step orphaned the variation and `resolved(applying:)` **threw** — taking out that
recipe's editor, reader fold, and grocery contribution. Now `keepAdjustmentProposalAsVariation` normalizes anchors
to live base-row IDs *before* writing the blob, throwing **loud-at-save** on an unresolvable anchor rather than
persisting a dead one. A post-engine, idempotent `RecipeRepository.backfillVariationAnchors` walks existing
`recipeVariations.deltas`, repairs what resolves and **reports — never guesses** the rest
(`variation-anchor-backfill` warning on `AppLog.dataIntegrity`, category `dataIntegrity`); it runs *after*
`makeSyncEngine`, alongside the other post-engine passes, so the repair upload carries SyncMetadata
([[migration-writes-bypass-sync-triggers]]) and converges deterministically (base IDs are identical across
devices). The positional `stepNumber` fallback in `index(in:)` is **deleted** (a silent-corruption hazard after a
reorder); ID-first → exact-trimmed-text is the only matching — no fuzzy/positional widening. Dispatch 3 rode
along: distinct editor error titles (Could Not Load / Save / Split-Off Variation) and a `clearError()` on the
adjustment-review sheet hand-off.

**Verified.** All 5 new `RecipeVariationAnchorRepairTests` and the 6 (id-migrated) `RecipeAdjustmentTests` pass
locally — architect ran both suites 2026-08-05; the idempotency + convergence + reorder-safety asserts are the
spine. Codex's PR run added `scripts/check-drift.sh` and the elevated generic-iOS app build.

**Device gate: PASSED 2026-08-05.**

**Remaining in the effort (still Ready, no schema):** Dispatch 2 — the repair UI (Dispatch 1 shipped + archived
above).

---
## ADR-0014 Amendment 1 — header follow-through complete

**Jon's hand-repair done 2026-08-05.** The three recipes still carrying `isHeader = 1` rows — *Beef Birria Taco
Filling*, *Broccoli Spoon Salad*, *Sous Vide Indoor Pulled Pork* (411 West's Rosemary Chicken was pre-fixed
2026-07-28) — were repaired in the app by adding a colon to each header line, which promotes the row to a section
and deletes it on save. Amd1-D1a (the colon-free door) stays **deferred** — the colon is the ratified primary
path. Dropping the `isHeader` **column** is a schema change, not a data migration, and remains un-queued.

---
## ADR-0049 Amendment 4 — deterministic exact-match label floor

**Merged 2026-08-04; PR [#281](https://github.com/jonphillips/yes-chef/pull/281), branch
`codex/adr-0049-amd4-deterministic-label-floor`. Architect-approved 2026-08-04.** Spec:
[ADR-0049 Amendment 4](decisions/ADR-0049-unified-labels-and-assisted-tagging.md). **Core + app, no schema, no
prod-schema entry, no two-device pass.**

**What it does.** Structured output (S4 / PR #280) fixed the format failure but the on-device model's *recall* on
surface-evident labels was weak — a fried-chicken recipe yielded only the inferred `Cuisine → American`, missing
the verbatim `Protein → Chicken` and `Technique → Fry`. A pure, model-free `LabelProposer.floor(recipe:vocabulary:)`
in Core now owns the surface-evident dimensions (whole-word Protein / Technique / Dish Type, precision-first,
typed, never a substring sweep; excludes Cuisine/Course/Dietary and loose labels) and is unioned with the model
proposal, deduped on `SuggestedLabel.id`, deterministic-wins. Provenance rides a sidecar
`LabelProposal.sources: [SuggestedLabel.ID: SuggestionSource]`, so the accepted-chip `Codable` shape is untouched
and nothing new syncs. Tests are the spine (the KFC precision anchor: floor yields Chicken + Fry, not Eggs, not a
loose or inferred-cuisine label; `stir-fried → Stir-Fry`; union dedups; sources map correct). Out of scope and
deliberately un-queued: prompt de-suppression / loose-label context trim, and escalate-on-miss.

**With this the ADR-0049 facet/labeling arc is closed as a gate.** Filling in per-recipe coverage is Jon's
ongoing hand work (Edit Tags + DEBUG Facet Coverage) and gates nothing downstream — Power Browser (ADR-0050) and
everything after it move forward without waiting on it (Jon, 2026-08-05). The two-column Edit Tags facet layout
was refined in PR [#282](https://github.com/jonphillips/yes-chef/pull/282) (merged 2026-08-05).

---
## ADR-0004 S4 — LabelProposer structured-output opt-in

**Merged 2026-08-04; PR [#280](https://github.com/jonphillips/yes-chef/pull/280) + jon-platform
[#36](https://github.com/jonphillips/jon-platform/pull/36).**
`LabelProposer` now attaches the portable `label_suggestions` JSON Schema to its `ModelCall`, while retaining the
English JSON instruction as the fallback floor. The proposal's `ModelCallRecord` records both structured intent and
the parser-verified result: structured hit, readable fallback, truncated, or unreadable. DEBUG Model Calls renders that state
for reliability measurement. Verified before handoff: `swift build --package-path YesChefPackage`, `swift test
--package-path YesChefPackage`, and the elevated generic-iOS app build are green; `scripts/check-drift.sh` and
`git diff --check` remain required final PR evidence.

---
## ADR-0049 Amendment 3 — labeling surfaces revised to Edit Tags + D8 discovery

**Approved (architect review) 2026-08-04; PR [#278](https://github.com/jonphillips/yes-chef/pull/278), branch
`codex/adr-0049-labeling-backfill`.** Spec: [ADR-0049 Amendment 3](decisions/ADR-0049-unified-labels-and-assisted-tagging.md#amendment-3--the-labeling-surface-is-a-per-recipe-tag-editor-not-a-batch-march-discovery-is-a-d8-cleanup-entry-2026-08-04).
**App + Core, no schema, prod-schema entry, or two-device pass.**

**What it does.** Retires the batch march and its main-library coverage filter. Recipe detail now owns the one
labeling surface, **Edit Tags**: it groups current assignments by visible facet, adds/removes assignments inline
through the existing reconcile path, and keeps accepted high-effort on-device suggestions in the editor. DEBUG
Facet Coverage turns every facet's unclassified total into a cleanup list; that list also exposes the three D8
coverage views and opens the same tag editor. The Core predicate is shared by the per-facet counts and discovery;
hidden vocabulary remains excluded.

**Verification.** `swift build --package-path YesChefPackage`, focused proposer/coverage Core tests, the elevated
generic iOS build, `scripts/check-drift.sh`, and `git diff --check` are green. Existing unrelated compiler warnings
remain.

---
## ADR-0049 S5 + S6 + ADR-0050 D8 — labeling-backfill tooling

**Merged 2026-08-04; PR [#278](https://github.com/jonphillips/yes-chef/pull/278),
branch `codex/adr-0049-labeling-backfill`. Architect-approved 2026-08-04; device look done 2026-08-05 (Jon).** Spec:
[`efforts/recipe-facets.md`](efforts/recipe-facets.md) § "The dispatch — S6 + S5 + D8". **Core + app, no
schema, no prod-schema entry, no two-device pass.** The existing `LabelProposer` remains on-device and
`RecipeRepository.reconcileSuggestedLabels` remains the sole category/join writer.

**What it does.** Adds one Core-derived coverage source shared by all consumers: Missing Protein, Missing a
Primary Facet, and No Editorial Labels inspect visible `RecipeCategory → Category.facetID` joins at query time;
hidden facets/values contribute neither vocabulary nor counts. The library exposes those views for a one-at-a-time
prefetched review queue, while recipe detail gets a re-runnable Suggest Labels sheet. Both retain accepted chips
as transient selection and commit only accepted typed `SuggestedLabel`s. DEBUG Settings adds facet coverage,
per-facet unclassified counts, and used-value distribution for the D6 gate/OQ3 measurement.

**Review round — the app target did not compile on first submission.** `swift build --package-path
YesChefPackage` is green because `reconcileSuggestedLabels` is exercised *inside* Core (`WebRecipeCaptureClient`),
but the two new callers live in `YesChefApp` — a separate module — so the package build is not App-target
evidence. The elevated `generic/platform=iOS` build (the required evidence for `YesChefApp/` changes) surfaced
three errors: `reconcileSuggestedLabels` was `internal`; `RecipeDetailModel` never declared its `labelProposer`
dependency; and `RecipeLabelBackfillSheet` declared `@Environment(\.dismiss)` as a local **inside** `body`,
which reads the default no-op `DismissAction` and left the queue's "Done" button dead. Fixed in commit
`86d8d44` — reconcile made `public`, the dependency added, `dismiss` moved to a stored view property. Architect
re-ran the elevated build locally → **BUILD SUCCEEDED, 0 errors**; `check-drift.sh` green (retaining the
pre-existing `RecipeCoreTests.swift` non-optional-`Data`-to-`nil` warning). **Restated lesson: a green package
build and `swiftc -parse` are not App-target evidence — the generic app build is** (the Verification Pattern's
own corollary; [[verify-local-fix-reached-merge]]).

**Device look done 2026-08-05 (Jon)** (transient state, so no two-device pass): (a) the detail Suggest Labels sheet and
the library batch queue present, accept typed suggestions, write them through `reconcileSuggestedLabels`, and
the queue's **Done** button dismisses (the fixed binding); and (b) **backfill latency** —
`RecipeFacetCoverageRequest` is an always-on whole-library `@Fetch` in `RecipeLibraryModel`, so every accepted
label re-runs the full coverage recompute; confirm Save & Next stays snappy across a real run, since this is the
[[sqlitedata-fetch-writer-convoy]] shape.

---
## App-layer pure logic moved to Core

**Merged 2026-08-04; PR [#279](https://github.com/jonphillips/yes-chef/pull/279),
branch `codex/app-tests-to-core-final` — no device pass owed (pure relocation, no behavior change).** Spec:
[`efforts/app-target-tests-to-core.md`](efforts/app-target-tests-to-core.md). **Core + app, no schema, no
prod-schema entry, no device pass.** `RecipeScaleFormatting` and the `@MainActor @Observable`
`WorkbenchCompareAlignmentModel` now compile in `YesChefCore`, with every app-facing type, initializer,
property, and method exported `public`. `ServeWithRepairPresentation` was extracted from its SwiftUI sheet into
Core while the sheet remains in `YesChefApp`.

The associated pure tests moved to `YesChefCoreTests`, so they run in ordinary `swift test`; the remaining
app-model repair-routing test remains in `YesChefAppTests`. The two redundant app-layer yield-scaling assertions
were deleted because `RecipeYieldScalingTests` already owns that behavior in Core. `xcodegen generate` was run
so the Xcode project drops the removed app-target sources and test files. Verification: package build and Core
tests green (**576 tests**), elevated generic-iOS app build green, `check-drift.sh` green, and `git diff --check`
green.

---
## ADR-0049 Amendment 2 · OQ4 — editorial facet seed (Protein / Dietary / Dish Type / Technique)

**Merged 2026-08-04; PR [#277](https://github.com/jonphillips/yes-chef/pull/277),
branch `codex/adr-0049-amd2-o4-editorial-facets`. Architect-approved 2026-08-04; two-device convergence pass done 2026-08-05 (Jon).** Spec:
[ADR-0049 Amd 2 § Resolved OQ4](decisions/ADR-0049-unified-labels-and-assisted-tagging.md);
[`efforts/recipe-facets.md`](efforts/recipe-facets.md) § Labeling backfill. **Core only, no schema, no new
prod-schema entry** — `facets` + `Category.facetID`/`hidden` are already registered and already on the
promotion list. Verified per the PR: `swift build` + `CategoryRepositoryTests` (23 tests / 3 suites) green,
`check-drift.sh` (SwiftLint + 566 Core tests) green; the unskipped run hits the documented pre-existing
`SQLiteData` dynamic-product linker wall in `YesChefAppTests`, untouched by this Core-only slice
([[exported-import-not-link-time]]).

**What it does.** Extends the existing `starterFacets`/`starterFacetValues` seed (Cuisine/Course) with the
four ratified editorial facets and all 49 values, each with a fixed, non-colliding `starterCategoryID`
ordinal — facets `21–24`, loose-assignment `103–106`, values `25–73`. The seed runs in the **post-engine data
pass** (`seedStarterFacets`, after `makeSyncEngine`), so its inserts carry `SyncMetadata` and upload, and the
deterministic ids mean two devices seed identical PKs and CloudKit dedups — the correct pattern per
[[migration-writes-bypass-sync-triggers]]. Insert-if-absent, so existing libraries gain the four facets
additively on next launch; non-deletable via `isStarterFacet`. Tests cover stable ids, idempotency (rerun
seeds nothing, row counts unchanged), non-deletability, and the name-fallback boundary — a user's own
"Protein" root with a non-starter child is **not** promoted. On review, Codex added an id-allocation-range
comment above the seed (`… values 3–20, 25–73; next value 74`) so a future value edit can't silently reuse a
facet ordinal and mint a permanent cross-fleet PK collision.

---
## ADR-0049 Amendment 2 · F1 + F2 — recipe-facing facet surfaces (hidden leak + editor grouping)

**Merged 2026-08-04; PR [#276](https://github.com/jonphillips/yes-chef/pull/276),
branch `codex/adr-0049-amd2-f1-f2`. Architect-approved 2026-08-04; device look done 2026-08-05 (Jon).**
Both found on Jon's D1–D5 device pass. Spec:
[`efforts/recipe-facets.md`](efforts/recipe-facets.md) § Post-D5 device-pass findings. **Core + app, no schema,
no prod-schema entry, no two-device pass.** Verified per the PR: `swift build` + a new Core hidden-suppression
test green, generic-iOS app build green, `check-drift.sh` green.

**F2 — the correctness fix.** `hidden` was honored in the catalog requests (`CategoryListRequest` /
`FacetListRequest`) but leaked through the per-recipe read paths, which built their category map from an
**unfiltered** `Category.fetchAll` — so hiding a category still showed it on recipe rows/detail and left it
filterable. The fix centralizes the effective-visibility rule in `CategoryRepository.visibleCategories(_:facets:)`
(one definition, factored out of `CategoryListRequest`) and routes `RecipeListRequest` (list display +
filter-availability names) and `RecipeDetailRequest` (detail display) through it: a hidden category — or a value
under a hidden facet — `compactMap`s away while its `RecipeCategory` join is **preserved**, so unhiding restores
it. Core test covers both grains + the restore. Residual (logged, not fixed): other denormalized surfaces (menu
cards, workbench, calendar, grocery) weren't audited, but `visibleCategories` now makes any straggler a
one-liner.

**F1 — presentation.** The recipe editor's category selector rendered a flat `parentCategoryID` tree, so facet
values sat at depth 0 with no group header and the facet title was invisible. It now renders one `Section` per
visible facet with values nested, loose labels under an "Other Categories" section, via a pure
`RecipeCategorySelectionSection.sections(categories:facets:)` helper; the selected-summary facet-qualifies values
(`Cuisine > Thai`). **F3/OQ5** (retire the typed freeform Cuisine/Course editor fields) stays deferred to
ADR-0050 — and its retirement must **preserve the per-facet single-select picker affordance** (Jon, 2026-08-04),
rebinding it to facet values rather than deleting it; pure UI, no `selectionMode` column.

---
## ADR-0049 Amendment 2 · Dispatch 5 — facet membership becomes editable

**Merged 2026-08-04; PR [#275](https://github.com/jonphillips/yes-chef/pull/275), branch
`codex/adr-0049-amd2-d5-editable-facets`. Architect-approved 2026-08-04.** Spec:
[`efforts/recipe-facets.md`](efforts/recipe-facets.md) § Dispatch 5. **App + Core, no schema, no prod-schema
entry, no two-device pass** (writes through D1's already-sync-tested reconcile/merge paths). Verified: `swift
build` + `CategoryRepositoryTests` (19 tests) green, generic-iOS app build green, `check-drift.sh` green.

**What it does.** Closes the create/update asymmetry: `createCategory` took an explicit `facetID` but
`updateCategory` derived it from the parent, so a parentless loose label could never be filed into a facet by
editing — which blocked the Dispatch 4 hand pass. `updateCategory` now takes `facetID: Facet.ID?`, cascades a
membership change to descendants (D9 rule 2), rejects moving a non-leaf to loose (D9 rule 3), and — the
load-bearing choice — **merges on a destination name-collision when membership actually changes** (re-points
recipe joins + children into the existing value and deletes the source row via the private `mergeCategory`),
while a pure in-place rename onto an existing sibling still throws `duplicateSibling`. This is what makes
shadow-consolidation work on the real library: every one of Jon's 15 loose labels (`Chinese` 66, `Thai` 37, …)
name-collided with an empty, non-deletable starter value, so the operation that clears each shadow *is* a merge,
not a plain move. `mergeCategory` stays `fileprivate`; no general merge verb is exposed. The editor gains a Group
picker (visible facets + "No Group") that clears the parent on change.

**Dispatch 4 (Jon's hand pass) done 2026-08-04.** With D5 shipped, Jon merged the 15 loose-label shadows into
their facet values by hand in the app — nothing dropped, joins preserved, and the #270 two-device convergence
held. Remaining facet work after this: F1/F2 (above), F3/OQ5 (deferred to ADR-0050), and the S5/S6 labeling
backfill (ADR-0050 D6 coverage gate).

---
## ADR-0049 Amendment 2 · Dispatch 3 — proposer re-point

**Merged 2026-08-04; PR [#274](https://github.com/jonphillips/yes-chef/pull/274), branch
`codex/adr-0049-d3-proposer-repoint`. Architect-approved 2026-08-03; device capture-flow look done 2026-08-04.**
Spec: [`efforts/recipe-facets.md`](efforts/recipe-facets.md) § Dispatch 3. **App-layer + Core, no
schema** (writes through D1's already-sync-tested reconcile paths); no new prod-schema entry. Verification per
the PR: `check-drift.sh` green, elevated `generic/platform=iOS` app build green, `git diff --check` green.

**What it does.** Re-points the label proposer from the untyped category *tree* to a **typed, visible facet
vocabulary** and makes accepted suggestions carry stored **identity** through commit instead of path strings.
`SuggestedLabel` becomes an enum (`.existingCategory(Category)` / `.newChild(NewChild)` / `.loose(String)` /
`.namespace(Namespace)`); the model proposes against `LabelVocabulary` (visible facets + visible values only —
hidden rows are deliberately out of scope), and `RecipeRepository.reconcileSuggestedLabels` resolves each to a
row id and remains the **sole writer** of categories, facets, and joins. `.namespace` literally proposes a new
`Facet` + its first value. Carrying identity subsumes the old Café/Cafe path-canonicalization (an
`existingCategory` now holds the real row id). An accepted suggestion that case-insensitively re-matches a
**hidden** row in its identified facet reuses **and unhides** it — a deliberate re-assignment, not a background
import resurrecting vocabulary; ordinary imported text does not reactivate hidden rows. Model **proposes**,
determinism **writes** (D2's boundary, unchanged). PR #269's Findings 1 & 3 were re-pointed, **not** deleted
(D11). The settled hidden-vocabulary rule was written into **ADR-0049 D11**.

**The review found one regression, fixed in `392618c0`.** The refactor collapsed the harvested-label dedup
filter and kept only the `tagNames` clause, dropping `categoryNames` — so a suggestion whose display name
matched a publisher-harvested *category* (both lists become joins at import,
[RecipeRepository+Import.swift](../YesChefPackage/Sources/YesChefCore/RecipeRepository+Import.swift)) would
surface a redundant chip for a label the recipe already receives. Not data-corrupting (reconcile dedups by id),
but it contradicted the retained comment and was *more* likely under the new bare-leaf display name. Codex
restored the `categoryNames` clause, extracted it into a testable `filteringHarvestedLabels(from:in:)` helper,
and added the regression test `doesNotSurfaceSuggestionsAlreadyHarvestedAsCategoriesOrTags`. Two narrow
non-blocking notes left on the record: a hidden diacritic-variant sibling/facet could still slip the
proposer's diacritic-insensitive guard past reconcile's diacritic-sensitive lookup (single-user, D4 hand-pass
catches it), and `RecipeListRequest`'s new base order is UUID-arbitrary for any non-re-sorting consumer
(determinism was the goal).

**Rode along — three Claude-authored recipe-list ordering fixes** (Jon folded them into this PR): a total-order
final tiebreak on the stable `id` in `RecipeLibraryListState.titleSort` and `RecipeModels`'
`archivedRecipeRows`, and a deterministic `.order { $0.id }` base fetch in `RecipeListRequest`. All sort modes
funnel through `titleSort`, so promoting it to a total order closes the non-total-order gap that let Swift's
non-stable `sort` swap identical-key rows between republishes — the phantom moves an animated `List` diffed
into an invalid batch update (the `NSInternalInconsistencyException` on deleting archived recipes).

---
## ADR-0049 Amendment 2 · Dispatch 2 — category management UI

**Merged 2026-08-04; PR [#272](https://github.com/jonphillips/yes-chef/pull/272), branch
`codex/adr-0049-amendment-2-category-management`. Architect-approved 2026-08-03; device UI look done 2026-08-04.**
Reads D1's schema (#270/#271, merged 2026-08-03). Spec:
[`efforts/recipe-facets.md`](efforts/recipe-facets.md) § Dispatch 2. Verified in-session: `check-drift.sh`
green (SwiftLint + 546 Core tests), generic-iOS app build green. **App-layer dispatch — not a synced-migration
pass** (writes through D1's already-sync-tested create/reconcile paths); no new prod-schema entry.

**What it does.** The management surface (`CategoryViews.swift` / `CategoryModels.swift`) presents **category
groups** (facets) and **loose categories** as structurally different things, each with its own deliberate
creation act; the old drag-to-move root/child browser is retired. New thin Core facet-CRUD on
`CategoryRepository` that D1 did not need — `createFacet`, `renameFacet`, `setFacetHidden`/`setCategoryHidden`
(hidden at **both** grains, Amd 1's escape hatch), duplicate-facet-name protection, and `Facet`/management
`FetchKeyRequest`s (product reads filter hidden, management reads show everything with an eye-slash marker). The
library filter (`RecipeCategoryFilterView.swift`) browses groups separately from loose labels. Starter facets
and values stay non-deletable (`isStarterFacet`/`isStarterCategory` guards); the UI hides Delete rather than
offering a dead control.

**The review found one blocking bug + two gaps, all fixed in `d4baa6f`.**
- **Blocking — value-name uniqueness ignored the facet.** `validateUniqueSiblingName` keyed only on
  `parentCategoryID` + name, and every top-level facet value and loose label shares `parentCategoryID == nil`,
  so creating a loose `Italian` was rejected by the `Cuisine` starter value `Italian`, and `Dinner` could not
  exist in two facets. This contradicted the store, `deduplicateFacetSiblings` (facet-scoped), and the import
  path, which all treat each facet as its own namespace — the validator enforced an invariant the rest of the
  system violates. Fixed by scoping the check to `facetID` too; regression-tested.
- **Cascade — hiding a group now hides its values on product reads.** `CategoryListRequest` excludes categories
  whose `facetID` points to a hidden facet, so hiding a group removes its values from the recipe editor and the
  filter, not just the group list. This is an implementation refinement of D8's `hidden` semantics (the ADR
  specified the column at both grains but not the cascade); **it hands D3 an open question — see the effort doc /
  handoff Next Up.**
- **Gap — user facets had no delete.** Added `deleteFacet` (non-starter, empty-of-values guard, symmetric with
  `deleteCategory`) plus a confirmation dialog and menu/editor Delete. Beyond D8's hidden-only escape hatch but
  the obvious CRUD completion; starters remain non-deletable.

**Schema: no change** — D1 already added `facets` / `Category.facetID` / `Category.hidden` and put them on the
prod-schema promotion list. This slice adds only behavior and UI.

## ADR-0049 Amendment 2 · Dispatch 1 — namespaces become synced `facets`

**Approved (architect review) 2026-08-03; PRs [#270](https://github.com/jonphillips/yes-chef/pull/270) +
[#271](https://github.com/jonphillips/yes-chef/pull/271) MERGED 2026-08-03 (`24f50d4`, `54a7021`),
branch `codex/adr-0049-amendment-2-facets` — device audit-review + two-device convergence pass done 2026-08-04**
(migration was a no-op on the real library — no `Cuisine`/`Course` parent to promote — so real categories stayed
loose labels; the resulting 15 loose-label shadows of empty starter values were consolidated in the D5/D4 hand
pass, both devices converged with no duplicate rows). Spec: [`efforts/recipe-facets.md`](efforts/recipe-facets.md) § Dispatch 1;
[ADR-0049 Amendment 2](decisions/ADR-0049-unified-labels-and-assisted-tagging.md). Verified in-session:
`swift build` clean, `CategoryRepositoryTests` **8/8** green. **Absorbs Amendment 1's teardown** — the
seed-state and tombstone tables are dropped *inside* this migration, not in a separate synced pass.

**What it does.** A `facets` table becomes an explicit synced entity; `Category` gains `facetID` (non-nil = a
structured facet value, nil = a loose label) and `hidden`. `Cuisine` and `Course` stop being category rows and
become facet rows with fixed ids. The post-`makeSyncEngine`, deterministic, idempotent data pass promotes both
namespace roots — setting each child's `facetID`, nulling its `parentCategoryID`, deleting the old root
category — while **preserving every child UUID so all `recipeCategories` joins ride through untouched**. Recipes
joined directly to a bare namespace root are **remapped to a "Legacy &lt;name&gt;" loose label, never dropped**,
and reported. The four D9 invariants (facet membership, same-facet parenting, leaf-only loose labels, facets
unassignable) are enforced in `CategoryRepository` alongside `reconcileCategories`, which stays the sole writer.
Import maps `recipeCuisine`→Cuisine and confidently-interpretable `recipeCategory`→a facet, otherwise loose — a
delimiter is not a hierarchy signal (D12). Dormant tags fold into loose categories.

**The review found one blocking gap, fixed in `fe20abe`.** The `FacetMigrationAudit` — the slice's required
Pass D deliverable ("Jon reads it before the second device converges") — was computed and then discarded at the
call site, so the merge gate could not actually be satisfied. It is now logged via `AppLog.dataIntegrity` when
`requiresReview`, and the struct was widened to capture parent changes, merges, and deletions (the full Pass D
spec). The same commit gated the dedup passes on rows actually changing, so a steady-state launch no longer does
full-library dedup grouping. Cross-table UUID reuse (`facet.id == old category.id`, `category.id == tag.id`) was
verified sync-safe: SQLiteData namespaces CloudKit record identity as `<uuid>:<recordType>`, so the shared zone
never collides.

**Schema: `facets` IS synced** — registered in `CloudSync`, and `facets` + `Category.facetID` + `Category.hidden`
added to the prod-schema promotion list in this same PR; the two retired seed tables stay off it.

## ADR-0049 S3/S4 label-proposer review fixes + app-test target repair; Amendment 1 recorded

**✅ Merged 2026-07-31.** PR [#269](https://github.com/jonphillips/yes-chef/pull/269), branch
`codex/adr-0049-pr268-review-followups`, merge `a59263f`. Follow-up to PR
[#268](https://github.com/jonphillips/yes-chef/pull/268): the S3/S4 label-proposer review fixes were never
committed before #268 merged, so **#268 shipped the pre-review proposer** and this PR lands the fixes on top of
main. Verified in-PR: Core `LabelProposerTests` **9/9**; the app-test target builds and
`RecipeCaptureLabelSuggestionTests` **2/2** + `ServeWithRepairTests` **2/2** run.

**The four #268 findings (ADR-0049 S3/S4, unified label proposer):**
- **Finding 1 (blocking).** Namespace confirmation used an `isPresented:`-with-payload-nilling setter — SwiftUI
  writes `false` before the button action, so the confirm no-op'd. This is the ADR-0030 destructive-setter
  defect recurring ([[alert-ispresented-destructive-setter]]); fixed by moving to the `item:`-binding house
  pattern, with `confirmNamespaceSuggestion(_:)` taking the payload.
- **Finding 2 (blocking).** `LabelProposer.parse` was all-or-nothing; now returns
  `LabelProposal(accepted:rejected:)` and maps per row, so one unmappable suggestion is surfaced, not fatal (D2).
- **Finding 3.** `.namespace` carries `[dimension, firstChild]` and files the recipe under the **child**, never
  a bare root — the hand-enforced precursor to Amendment 2's "a facet is not assignable" (D9 rule 4).
- **Finding 4.** Model tier is threaded through the proposer (defaults `.onDevice`) for the S5/S6 consumers.
- **Smaller:** a "Suggest Again" retry, accepted suggestions merge only at commit (no re-extract stickiness), a
  "Categories & Tags" row, and app-layer regression tests.

**App-test target repair (rode in the same PR).** `ServeWithRepairTests` called a
`WorkbenchDetailModel.presentServeWithRepair` surface that never existed, breaking the app-test compile; the new
test file had also never been wired into `project.pbxproj`, so it was silently excluded from the bundle. Both
fixed, so the app-test target — and the new tests — actually run.

**ADR-0049 Amendment 1 recorded here (doc only).** The decision to retire the category seed-state + tombstone
machinery — seed the ~24 starter categories in place by fixed id, make them non-deletable + hideable, drop
`categorySeedStates` / `categorySeedTombstones` — because the deletion-suppression apparatus is over-built for
~10 friendly users ([[category-seed-retire-tombstone]], [[withdraw-not-defer-orphaned-schema]]). **Not
implemented in this PR.** Amendment 2 then **absorbed** it: the teardown ships inside D1's facet migration (PR
[#270](https://github.com/jonphillips/yes-chef/pull/270)), not as a separate synced data pass — see the entry
above.

## Prep-plan Slice 3 — the omission guard follows refine vs regenerate intent

**✅ Merged 2026-07-30.** PR [#265](https://github.com/jonphillips/yes-chef/pull/265) "Prep plan · S3 —
Regenerate intent", branch `codex/prep-plan-regenerate-intent`. Spec:
[`efforts/prep-plan-dish-links-and-dates.md`](efforts/prep-plan-dish-links-and-dates.md) § Slice 3. **One
column on the local-only `aiHandoffs` table, no sync, no prod-schema-promotion entry** — a plain local
migration ([[migration-writes-bypass-sync-triggers]] is about synced tables and does not bite here); **no
two-device pass**. Verification per the PR: `check-drift.sh` green, elevated `generic/platform=iOS` app build
green, `git diff --check` green.

**The problem it closed.** Slice 1's day-anchored session labels *guaranteed* the "Review omitted steps before
saving" banner would fire on the first post-Slice-1 regenerate of any pre-Slice-1 plan:
`omittedCurrentPrepStepEvidence` diffs on exact `PrepPlanStepVisibleContent` (`session` + `task` + `serves`),
and a regenerate legitimately rewrites both the `session` labels (Slice 1's whole purpose) and the `task`
prose — so 100% of prior steps read as "missing." The guard was answering the wrong question: its
accidental-drop protection only makes sense against an edit meant to be **incremental**, and a regenerate is
wholesale replacement.

**The fix — intent, not transport, drives the baseline.** A `.refine` / `.regenerate` intent threads into
`AIHandoffReviewStager.menuReview` for both the onboard button and the outboard paste door. **Refine** keeps
the current-plan baseline and the loud omission + dropped-link guards (byte-for-byte unchanged — this is the
ADR-0040 lossless-or-loud protection). **Regenerate** uses an **empty** baseline, so `omittedCurrentPrepStepEvidence`
and `droppedSourceDishEvidence` both return `[]`, `advisoryNotes` is empty, and the review presents as a clean
replacement with a positive "replaces your N-step plan" confirmation instead of the alarming omission
language. Intent is **threaded, never inferred** from how many steps happen to match — that heuristic *is* the
bug. New `aiHandoffs.regenerates: Bool` (default `false` → every existing row reads as `.refine`) ferries
intent across the copy→paste gap for the outboard round-trip **only**; the onboard transient handoff carries it
as a plain in-memory parameter. App layer: `regeneratePrepPlan()` stamps `.regenerate`; the chat Apply/Finalize
path stays `.refine`; a new **"Handoff to Regenerate"** action sits beside "Handoff Prep" in the prep-plan `…`
menu. Tests cover refine/regenerate staging, the intent round-trip on the row, the migration default, and the
positive review wording (across `AIHandoffMenuPasteTests`, `AIHandoffAdvisoryTests`, `DatabaseBackupTests`, new
`AIHandoffMenuPrepPlanReview.swift`).

**Doc-hygiene note:** the CURRENT_HANDOFF bump did not ride in PR #265 as convention expects
([[handoff-bump-rides-in-slice-pr]]) — this entry and the handoff/effort-doc removals were reconciled
2026-08-03 once the omission was caught.

---
## Prep-plan Slices 1–2 — the menu's dates reach the model; `sourceDish` becomes human-settable

**Device-confirmed 2026-07-30 (day-anchored labels); PR [#262](https://github.com/jonphillips/yes-chef/pull/262),
branch `codex/prep-plan-dish-links-and-dates`.** Spec:
[`efforts/prep-plan-dish-links-and-dates.md`](efforts/prep-plan-dish-links-and-dates.md) §§ Slice 1–2.
*(Finalize this entry's verification record on merge.)* **No schema** — both slices use fields that already
exist and already sync.

**Slice 1 (Core only).** `MenuChatContext` now carries the placement start date and serializes concrete per-day
dates; the prompt asks for **day-anchored** session labels only when the menu is placed, and keeps the
relative-horizon wording when it is not. Confirmed on the placed NJ-Avalon menu: bands came back as
"Previous Saturday afternoon" / "Previous Sunday" instead of the ambiguous "One day ahead / Two days ahead"
that motivated the effort ([ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md) D2). No app build
needed for this half.

**Slice 2.** `sourceDish` is human-settable for the first time — `PrepPlanStepRepository.update` gained a
`sourceDish` parameter, the editor sheet gained a Dish picker with an explicit "No dish", and a Core matcher
proposes one default from the `serves` string (exact, then trailing-parenthetical-normalized; ambiguous and
compound `serves` → no suggestion). **The matcher only proposes — nothing writes until the human saves**, which
keeps it on the right side of ADR-0040 D3. ADR-0040 amended: the corollary's accepted cost ("text imports drop
the chip") is now **recoverable by hand**.

**One thing the device pass surfaced → spun out as Slice 3.** Regenerating a plan flags ~every existing step
under "Review omitted steps before saving": the omission diff keys on exact `session`+`task`+`serves`, and a
regenerate rewrites the labels (Slice 1's purpose) *and* rephrases the tasks, so 100% read as "missing." The
guard is ADR-0040 lossless-or-loud answering the wrong question — it is for an incremental *refine*, not an
intended wholesale *regenerate*. Fix is scoped as Slice 3 (refine-vs-regenerate intent; local `aiHandoffs`
column for the outboard round-trip only); it is the live Next Up target and does **not** reopen this PR.

## Playbook edit grain Dispatch 2 (S3) — Serve With is synced rows, not a blob

**✅ Merged 2026-07-30, device pass owed to Jon.** PR [#261](https://github.com/jonphillips/yes-chef/pull/261),
branch `codex/playbook-serve-with-rows`, merge `f1517f7`. Spec:
[`efforts/playbook-edit-grain-2026-07-26.md`](efforts/playbook-edit-grain-2026-07-26.md) § Slice S3;
[ADR-0048](decisions/ADR-0048-playbook-edit-grain.md). **This closes the playbook-edit-grain effort — all three
dispatches (S0/S0.1, S1, S3) are done.** Verified in-PR: `scripts/check-drift.sh` green, `swift test` **518
tests / 97 suites**, elevated `generic/platform=iOS` build green.

**What it does.** Adds the synced `recipeServeWith` table with a provenance enum (model-suggested vs
hand-authored — its *own* enum, deliberately not `LearningProvenance`, which records transport) and sparse
ordering. Legacy blob data is migrated **deterministically** — reusing each `ServeWithItem.id` as the row id,
ranks from array index × stride, dates from the recipe's `dateModified` — so a brand-new synced table does not
have each device upload its own copy ([[migration-writes-bypass-sync-triggers]]). Playbook, chat, handoff
review, and regeneration all route through row-grain storage; **regeneration upserts by identity and preserves
hand-authored rows and their ranks** (the primary test — delete-and-reinsert would reproduce the identity loss
the slice removes). A malformed legacy blob is preserved, reported with its recipe id, and yields no rows,
surfacing an inline repair affordance rather than aborting migration. `Recipe.serveWith` is left readable one
release, not dropped. **Schema: `recipeServeWith` IS synced** — registered in `CloudSync` and added to the
prod-schema promotion list in this same PR.

## Archived Recipes crash — an empty-state branch *inside* a List, in eight places

**✅ Device-verified by Jon 2026-07-29** — deleting the single archived recipe now shows the empty state with no crash. Found the same day by accident: Jon needed a genuine hard delete to set up the ADR-0030 OQ1 measurement, opened Settings → Archived Recipes for the first time ever, and the app died on **both** attempts. **No schema, view layer only.** Verified: package suite **518 tests / 97 suites**, elevated `generic/platform=iOS` build `** BUILD SUCCEEDED **` with no new warnings in the seven changed files — and, decisively, **the tap**, because neither automated check can observe a UIKit batch update.

**The defect.** `ArchivedRecipesView` branched on the empty state *inside* its `List`: `List { if rows.isEmpty { ContentUnavailableView(…) } else { ForEach(rows) { … } } }`. Deleting the last row flips that branch, so the List's single child changes kind in one update and `UICollectionViewListCoordinatorBase.performUpdates` raises the classic invalid-batch-update `NSException` → `SIGABRT`. Only the **last** row triggers it, which is why a screen nobody had opened carried it for months. Two competing explanations were ruled out with evidence before anything was edited: unstable `ForEach` identity (`RecipeListRowData.id` is `recipe.id`, stable) and any Core-level failure (`permanentlyDelete` is correct and the row really was deleted).

**The write commits *before* the crash — that is the part that mattered.** The recipe was genuinely deleted on the first tap; the crash made a destructive action look like it had failed, so Jon ran it again. Harmless here because the row was already gone. **A destructive action that commits and then crashes trains the user to retry it**, and the next one of these may not be idempotent.

**Fixed in eight places, in two shapes.** `.overlay` where the List had no `Section` header (`ArchivedRecipesView`, `RecipeListPresets`, `MenuDetailSections`, `RecipeCategoryFilterView`, `RecipeCategorySelectionView`) — the `ForEach` becomes unconditional so the List only ever goes 1 row → 0. `Group { if empty { … } else { List { … } } }`, Apple's documented shape, where a `Section` header would otherwise show behind an overlay (`PantrySettingsView`, the grocery ingredient-choice sheet, `CategoryBrowserList`). Every site carries a comment naming the failure so the pattern is not read as harmless and copied back in. **Scope deliberately widened** past "can reach zero via a delete" to include **search**-driven empty states (`MenuDetailSections`, `RecipeCategoryFilterView`): identical structural swap, and reached far more often than a last-row delete. The one genuinely low-risk site (a selection list with no delete) was converted anyway so it does not survive as a template. **Visual change across eight screens:** empty states now render as centered `ContentUnavailableView`s rather than list rows, and the `.frame(maxWidth: .infinity, minHeight: 220/280)` workarounds that existed to make them tolerable inside a `List` are gone.

**The lesson is about which screens get exercised.** This sat behind an affordance that had never been used, in a codebase whose tests are healthy — the same shape as the app-test-target entry further down, where a green build laundered a live bug. **Unexercised UI is not low-risk UI; it is unmeasured UI.** It also cost real time in the middle of an unrelated measurement, which is the usual way this class of bug gets paid for.

## Playbook S1 — one shared row editor; Reader Feedback adopts it

**✅ Done 2026-07-29.** Branch `codex/playbook-edit-grain-s1`, PR
[#260](https://github.com/jonphillips/yes-chef/pull/260) (commit `615cb1c`, "Extract shared playbook row
editor", plus the review follow-up commits). Spec:
[`efforts/playbook-edit-grain-2026-07-26.md`](efforts/playbook-edit-grain-2026-07-26.md) § Slice S1. Owner:
Codex implement, Claude architect/review. **No schema, no prod-promotion entry** — app layer only. Closes
**Dispatch 1**; only Dispatch 2 (S3) remains on the effort.

**What it does.** Extracts the `LearningsSection` / `LearningRow` interaction into one generic
[`EditableRowsSection`](../../YesChefApp/EditableRowsSection.swift) — inline tap-to-edit (`TextField`,
`axis: .vertical`), swipe-to-delete, and three **opt-in** capabilities: an add affordance, reorder, and a
caller-supplied provenance badge. Learnings is rewired to it as a **pure refactor** (same title, empty state,
divider logic, reorder mapping, add flow, and `.inApp` "Hand-authored" badge). Reader Feedback adopts it and
**loses the bulk Edit/Done mode**: edit is now per row (no `TextEditor` box, no mode toggle), delete is a
per-row swipe.

**What it removes.** `LearningRow` and the four bulk-edit members Finding 3 named —
`isEditingReaderFeedback`, `readerFeedbackDrafts`, `readerFeedbackDraftBinding(for:)`,
`commitReaderFeedbackEdits(_:)` — with zero dangling references. The slice deletes more from the two call
sites than the component adds, exactly as predicted.

**The reframe held (Findings 2 & 4).** Reorder is opt-in, not assumed: `RecipeNote` has no `sortOrder`, so
Reader Feedback passes a `nil` reorder handler — the component cleanly omits `.reorderable()` /
`.reorderContainer` rather than degrading, and **no column was added to make the shape uniform**. The badge is
injected by the caller, not inherited by the component.

**Review + device caveat.** Approved with only minor non-blocking follow-ups (duplicate-initializer
simplification, an `Edit learning:` → `Edit Learning:` VoiceOver-label capitalization, a trailing blank line),
folded into the PR. The one thing flagged for Jon's device pass: Reader Feedback now renders
`RecipeMarkdownText` inside a `.buttonStyle(.plain)` tap-to-edit button, so a row tap competes with any
tappable markdown link in a feedback body — confirm the interaction on device.

**Verification.** Elevated `generic/platform=iOS` build plus `scripts/check-drift.sh` (lint, package tests,
app-test-bundle compilation).

---
---
## The `YesChefAppTests` link wall falls — SQLiteData 1.8.2 bump

**✅ Done 2026-07-29.** Branch `codex/playbook-edit-grain-s0-1-repair`, PR
[#259](https://github.com/jonphillips/yes-chef/pull/259) (commit `5ae16fa`, "update sqlite-data"), on top of
the S0.1 work in PR [#258](https://github.com/jonphillips/yes-chef/pull/258). Owner: Codex implement, Claude
architect/review. **No schema, no prod-promotion entry** — build tooling plus test dependencies. `project.pbxproj`
was regenerated with `xcodegen generate`, not hand-edited.

**What it closes.** For months `check-drift.sh`'s `build-for-testing` stage died at
`Ld … SQLiteData.framework` with an undefined-symbols wall, and the standing guard in `CURRENT_HANDOFF.md`
declared it upstream's problem — *"do not investigate it, do not try to fix it."* That guard is now
**retired**: the app test target **compiles, links, and runs**. `check-drift.sh` is green and
`YESCHEF_RUN_APP_TESTS=1` reports **29 tests in 9 suites passed**, including the three Playbook S0.1 tests in
`YesChefAppTests/ServeWithRepairTests.swift` that had **never been built** — S0.1 shipped them behind a link
failure, so their first real execution happened here.

**What changed.**
- **sqlite-data `1.6.6` → `1.8.2`** and **swift-structured-queries `0.31.3` → `0.34.0`** — floors raised in
  both `YesChefPackage/Package.swift` and `project.yml`.
- **CustomDump added** as a package and as a `YesChefTests` dependency in `project.yml`: the target called
  `expectNoDifference` without ever linking the framework — the same class of defect as our
  `StructuredQueriesCore` insurance, one layer out ([[exported-import-not-link-time]]).
- **`try database.write` → `try await database.write`** at two sites in `ServeWithRepairTests.swift`: the async
  GRDB overload now wins inside an async `withDependencies(operation:)`, so the sync call no longer type-checks.

**Known and deliberately not fixed.** sqlite-data's manifest **still omits `StructuredQueriesCore` from its
`SQLiteData` target on 1.8.2**. `SQLiteData.framework` links it anyway — via Swift **autolinking** against the
`-F …/PackageFrameworks` search path, **not** a declared dependency — so the resolution is **build-order
sensitive**. Our own `StructuredQueriesCore` declarations in `project.yml` stay as **insurance**. **If this
failure ever returns, `xcodebuild clean` first** — a stale eager-linking TBD produces an identical-looking
undefined-symbols wall.

---
---
## Playbook S0.1 — a repair path for an unreadable Serve With blob

**✅ Done 2026-07-29.** Branch `codex/playbook-edit-grain-s0-1-repair`, PR
[#258](https://github.com/jonphillips/yes-chef/pull/258), commits `5ee76c7` → `e79a481` across **three
architect review rounds**. Spec:
[`efforts/playbook-edit-grain-2026-07-26.md`](efforts/playbook-edit-grain-2026-07-26.md) § Slice S0.1. Owner:
Codex implement, Claude architect/review. **No schema, no prod-promotion entry** — Core plus app layer.
Closes Dispatch 0.

**What it owed.** S0 shipped a block with one exit: **Clear**, which destroys exactly the bytes S0 exists to
preserve. That is not shippable indefinitely, and it is a hard prerequisite for Dispatch 2 — post-S0 the row
migration hits a corrupt blob and fails loudly by design, so without repair that recipe's migration is
permanently stuck.

**The shipped work.** `ServeWithCodingError.malformedData` now carries `recipeID`, threaded through all ten
`decode` call sites. `RecipeRepository.repairServeWith` validates the cook's edited bytes through `decode`
**first**, then stores them **exactly as supplied** via a `Data?` helper that bypasses `encode` — this recovery
path must never normalize or re-serialize, and the doc comment says so, because a later refactor will want to.
The sheet shows the raw blob as monospaced text, saves only on a clean decode, and keeps an invalid edit open
with its failure and no write. **No salvage-partial-items, no auto-repair** — that stays closed. Non-UTF-8 bytes
render as Base64 with an explicit note, which is the only lossless textual form for them. Repair is reachable
from the Playbook failure label, the section menu, recipe chat, workbench chat, and every `HandoffInAppTransport`
failure on both surfaces; the transport takes an injected `presentServeWithRepair` closure that defaults to a
no-op, so surfaces opt in rather than inherit.

**Review round 1 — the identity threading was right; the reachability was half-wired.** Only the workbench got
the repair route. `RecipeDetailView` still built its transport with the default no-op and `askButtonTapped` /
`askSection` set a bare `errorMessage` — so on the Playbook, **Hand off** (which, unlike Paste and Edit, is not
disabled for an unreadable blob) produced a dead-end alert sitting in the same menu as a working Repair button.
The fix was not to thread the Playbook's `@State` upward but to **converge the recipe surface on the pattern
this same PR had just established on the workbench**: a model-owned `Destination.repairServeWith`, presented
from `RecipeDetailView`. The workbench's own lookup was already provably complete — it searches
`draftRecipeDetail + candidateRows`, which is exactly the set `WorkbenchChatContext.init` decodes `serveWith`
for, since references build through `WorkbenchReferenceChatContext` and carry none. Two more from the same
round: nothing let a cook **preserve** bytes they were about to overwrite — acute in the Base64 case, where
they cannot read what they are destroying — so the sheet gained a Copy of the *original* stored form (not the
draft, which would defeat it); and `Clear`'s confirmation gained an unreadable-specific variant that names the
destruction and points at Repair, now that the two sit adjacent in one menu.

**Review round 2 — the tests existed but had never run.** All new app-layer logic arrived untested while
`check-drift.sh` had been reported as "SwiftLint + Core suite," which is not what it does: it *builds and
links* `YesChefAppTests` but leaves execution behind `YESCHEF_RUN_APP_TESTS=1`. So 177 lines of test were
added to close a coverage finding with nothing but compilation behind them — the precise state the script's
own comment block documents the repo sitting in for months, and where *"three of the five original failures
were stale expectations left behind by an API swap that nothing ever ran."* Ordered an explicit run before
merge. **Adding a test and executing a test are separate claims, and a coverage finding closes only on the
second.**

**Review round 3 — two architect nits, both net-negative, both reverted.** Recorded because the shape
generalizes. (1) "`updateServeWithData` takes `Data?` but repair always passes non-optional" ignored that the
helper is *shared* and `encode` legitimately returns `nil` for the empty list; tightening a shared helper's
signature to suit one caller pushed the duplication into the other, and the hot write path behind every Serve
With mutation briefly existed twice. (2) "Remove the now-unreachable `ContentUnavailableView` branch" left an
`if case let .success` with no else, so an unreachable-but-explaining path became an unreachable-and-**blank**
sheet. Both reverted; `RecipeEnrichment.swift` ended byte-identical to its pre-nit state, and the restored
fallback now carries a Repair action, so it is better than what the nit attacked. **A nit aimed at a shared
helper's signature is a change to every caller, and "this branch is dead" is not a reason to delete what it
says — only a reason to stop paying for it.**

**Tests.** App-layer coverage in `YesChefAppTests/ServeWithRepairTests.swift`: the presentation's identity
guard (mismatched recipe, absent blob) and both textual forms; and, on *both* `RecipeDetailModel` and
`WorkbenchDetailModel`, that an unknown recipe returns `false` and **leaves `destination` untouched** — the
assertion that actually protects the caller's alert fallback. Core gained invalid- and valid-repair writes,
asserting the bytes *and* `dateModified` on the rejected attempt. **516 Core tests and the elevated
`generic/platform=iOS` build are green and are the whole of this slice's evidence.**

**⚠️ The app-layer tests in this slice have never been compiled, linked, or run — read this before trusting
them.** `check-drift.sh`'s `build-for-testing` stage dies at `Ld … SQLiteData.framework` (exit 65, the known
upstream missing-`StructuredQueriesCore` defect, [[exported-import-not-link-time]]), reproduced on clean
`main`. So `ServeWithRepairTests.swift` is not known to compile, let alone pass, and the pure-value half of it
— `ServeWithRepairPresentation`'s identity guard and UTF-8/Base64 forms — is SwiftUI-free logic that would run
on every dispatch if it lived in Core. **Move it down as a rider on S1** ([`efforts/app-target-tests-to-core.md`](efforts/app-target-tests-to-core.md));
only the two model-routing tests genuinely need the app target.

**The verification claim failed twice in one PR, in both available directions.** Round 2 caught tests added
but never executed. Round 3's fix was reported as *"executed `YESCHEF_RUN_APP_TESTS=1 scripts/check-drift.sh`:
516 Core tests and 29 app tests passed"* — and that was **incorrect**; `test-without-building` was never
reached, and the count was propagated into `check-drift.sh`'s own comment, `CURRENT_HANDOFF.md`, this entry,
and the PR body before anyone asked for output. It came apart the moment the ask changed from *"re-run it"* to
*"paste the tail of the log, name your toolchain, and reproduce on clean `main`"* — Codex then withdrew the
claim itself, unprompted and in full. **A verification report is a claim about an artifact, so ask for the
artifact.** The standing `Ld` guard is what made it survivable: it had already said this exact failure was
upstream and pre-existing, so the only thing lost was the belief that the app tests meant something.

---
## Playbook S0 — the Serve With decode becomes loud

**✅ Done 2026-07-29.** Branch `codex/playbook-edit-grain-s0-loud-decode`, PR
[#257](https://github.com/jonphillips/yes-chef/pull/257). Spec:
[`efforts/playbook-edit-grain-2026-07-26.md`](efforts/playbook-edit-grain-2026-07-26.md) § Slice S0. Owner:
Codex implement, Claude architect/review. **No schema, no prod-promotion entry** — Core plus app layer.
Dispatch 0 of three; it shipped on its own and first, as the effort doc required.

**The bug it closed.** `ServeWithCoding.decode`'s `(try? …) ?? []` sat on the read side of three
read-modify-write paths — `appendServeWithPlan`, `replaceServeWithPlan`, `removeServeWithItem` all decoded,
mutated, and wrote back — and `encode` returns `nil` for an empty list. So a corrupt blob was **destroyed** by
the next regenerate, append, or delete-one, today, with no migration involved. This was a live data-loss bug,
not migration prep, which is why it was pulled out of Dispatch 1 into its own dispatch
([[editable-at-the-grain-stored]], ADR-0040 lossless-or-loud).

**The shipped work.** `decode` now `throws(ServeWithCodingError)` — typed throws, which is what lets callers
bind the concrete error without a cast. `nil` (absent) still decodes to a legitimate empty list; only
undecodable bytes throw. All three repository mutators decode *before* writing, so no path can round-trip a
corrupt blob into an empty one. The Playbook renders the failure in place instead of an empty section, and
disables **Edit** and **Paste** for an unreadable blob. **Clear** stays enabled and deliberately never decodes
— destroy-on-purpose remains allowed, overwrite-by-accident does not — and it is the only exit until S0.1
lands.

**Review round 1 — the fix was half a fix.** The write side was correct, but `RecipeChatRecipeContext.init`
still swallowed via a `Result.items` helper that existed *only* to preserve the swallow, and
`RecipeHandoffContext.init` enforced the invariant at a distance (`_ = try decode(...)`, discarded, then
re-decoded through the silent path one line down). The result: tapping **Ask** on a corrupt recipe opened a
chat that told the model the recipe had no Serve With, and the live Serve With verb then ran a full
extract → review → commit round-trip that only died at the last step — while `askSection`, on the same screen,
hard-failed immediately. Fixed structurally: the init throws, `.items` is deleted, and the invariant is now
compiler-enforced rather than remembered. That flushed out two more silent call sites nobody had found —
`WorkbenchChatContext.init` and `WorkbenchCandidateChatContext.init` build recipe contexts through
`.map(RecipeChatRecipeContext.init(detail:))`, which no grep for `RecipeChatRecipeContext(` matches. Also
fixed in the same round: **Edit** opened a *blank* editor on a corrupt section (`isFilled` is true on failure),
which is the same display lie the slice exists to kill, one menu deep.

**Review round 2 — the cleanup introduced a crash, from a bad architect suggestion.** Collapsing the now-dead
blank-editor branch to `preconditionFailure` looked safe and was not: `.sheet(item:)` re-invokes its content
closure on every body re-evaluation while presented, `initialText:` is evaluated each time, and
`serveWithItemsResult` reads observable state. So opening Edit on a *readable* Serve With and then receiving a
corrupt blob **by sync** — the likeliest way one appears at all — re-ran the closure and trapped. Disabling the
button prevents entering that state, never remaining in it. Fixed by moving the branch into the sheet closure
so the editor is never constructed and `initialText` never computed for an unreadable blob; the failure
presents a `ContentUnavailableView` instead.

**Scope call Jon made during review: the block stays, and it is wide.** A corrupt blob now fails every AI
surface that reads that recipe — the section and adjust-recipe hand-offs, the recipe chat panel, and (through
`WorkbenchChatContext`) the whole workbench chat plus both workbench hand-offs, since Serve With ships as
sibling context in all of them. Accepted deliberately: losing the bytes is worse than losing the surface. It
is not shippable indefinitely without a recovery path, so **S0.1** was written into the effort doc in this same
PR as a hard prerequisite for Dispatch 2 — post-S0 the row migration hits a corrupt blob and fails loudly by
design, and without repair that recipe's migration is permanently stuck.

**Tests.** All three write paths blocked on a corrupt blob, asserting the bytes *and* `dateModified` are
unchanged; both context inits throwing; **Clear** still succeeding on a corrupt blob (the escape hatch, now
pinned); `decode(nil) == []` still a legitimate empty list. 516 package tests and the elevated
`generic/platform=iOS` build green, run by the architect. `check-drift.sh` fails at
`Ld … SQLiteData.framework` — reproduced identically on clean `main`, i.e. the known upstream defect, not this
slice.

---
## Grocery rapid add — a persistent Add Item field, plus Accept All on review

**✅ Done 2026-07-29.** Branch `codex/grocery-rapid-add`. Spec:
[`efforts/grocery-rapid-add-2026-07-26.md`](efforts/grocery-rapid-add-2026-07-26.md). Owner: Codex implement,
Claude architect/review, Jon device pass. **No schema, no prod-promotion entry** — app layer plus one
shared-component extraction and one small Core addition.

**The shipped work.** A persistent Add Item field pins above the aisle sections (`safeAreaInset(edge: .top)`),
matching the Paprika reference. Return and a trailing button are the *same* commit path, both clear the field
and both keep focus, so items go in one after another without touching anything else. `IngredientFractionPillRow`
was **extracted** from `RecipeEditorView` into its own shared file — not reimplemented — and appears under the
field while it is focused. Lines run through `IngredientParser`, so `2 cups chicken broth` lands as a row
titled "chicken broth", quantity `2`, unit `cups`, filed by the existing deterministic `GroceryStoreArea.seed`
lookup with no model call. The stale-editor bug is fixed at the root: both editors' drafts moved out of
`@State`-seeded-in-`init` and onto the destination payload, so a dismissed-and-reopened sheet can no longer
hand back the previous view's text — and the same fix landed on `GroceryListEditorView`, the third instance
the effort doc did not name. On the review sheet, **Accept All** takes the trailing toolbar slot and
**Discard All** demotes to a text button beside the instruction line, keeping its confirmation dialog:
prominent and destructive stop being the same button.

**Review round 1 — two silent-failure bugs, both invisible to a device pass.** The debounce shipped as a
single cancel-and-restart Task, which cancelled not just the pending sleep but a **sweep already in flight**.
`GroceryCategorizationAttemptCache.namesToClassify` records names as attempted *at read time*, so a sweep
killed mid-flight burned its names and no later pass — debounced or the undebounced on-appear one, which
shares the cache — would ever retry them. The rapid-add burst was the trigger, meaning the feature's headline
scenario was the thing that broke it, and only for items the deterministic seed misses, i.e. exactly the ones
the classifier exists for. Fixed by splitting the debounce into a cancellable sleep task and a **never-cancelled
sweep task** that queues behind its predecessor. Second: `addItemLine` silently dropped the parser's `comment`
(the effort doc listed the tuple as five fields; it is seven), so `2 cups chicken broth (low sodium)` lost
"low sodium" — the exact [ADR-0040](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) lossless-or-loud
violation the spec had gone out of its way to close for `preparation`. Fixed by lifting the parse→map into
`GroceryRapidAddItem` in Core, joining both fields, with a test.

**Review round 2 — the same disease on the other caller, and a test that could not fail.** The
never-cancelled-sweep fix left a `Task.checkCancellation()` sitting *between* a completed classifier call and
the write that applies it. Harmless for the debounced path, which is no longer cancelled — but the on-appear
`.task` **is** cancelled on disappear, so navigating away at the wrong moment discarded a paid-for on-device
inference while leaving its names permanently burned. Removed, with a comment recording why there deliberately
is no check there. Separately, the test claiming to pin Slice E's riskiest acceptance called
`item.commit(item.unmodifiedApprovedText, …)` **twice with byte-identical expressions** and asserted the two
results matched — `f(x) == f(x)`, incapable of failing, while reading as coverage and so retiring the concern
falsely. Rewritten to assert hardcoded expected text per presentation, renamed to what it actually tests, and
documented as *not* covering individual-vs-bulk equivalence — that lives in the app layer, and what keeps the
paths in step is the single `unmodifiedApprovedText` property all four call sites read. Also: rows stayed
tappable during Accept All (only the committing row was disabled), so a mid-run Discard raced the bulk pass's
snapshot; both row types now take `isBulkCommitting`.

**The one that decided whether the feature was good was the one that looked skippable.** Slice C — the
debounce — was the perf guard, not the ask, and both of its bugs lived there. `categorizeUncachedItems()` does
three whole-table scans, two write transactions and two full reloads; fine at one add per sheet, an
[ADR-0029](decisions/ADR-0029-main-thread-write-and-fetch-cost.md) writer convoy at ten adds in twenty seconds.
Debouncing removed the multiplier this effort itself created. The deeper sweep rewrite stays a deliberate
ADR-0029-shaped follow-up.

---
## ADR-0014 Amendment 1 — the colon is the ingredient section syntax, and identity is manipulated where identity exists

**✅ Done 2026-07-28.** PR [#255](https://github.com/jonphillips/yes-chef/pull/255), branch
`codex/adr-0014-amendment-1-sections`, merge `d49a940`, commits `0d69763` → `89bb1e2` across **two
architect review rounds plus a device pass**. Spec:
[ADR-0014 Amendment 1](decisions/ADR-0014-recipe-text-editing-model.md#amendment-1--the-header-is-syntax-the-section-is-storage-and-the-split-happens-at-edit-time-2026-07-28).
Owner: Codex implement, Claude architect/review. **No schema, nothing added to the prod-promotion list** —
the `isHeader` column stays in place and readable; only the *writing* of it stopped.

**The shipped work.** `IngredientSectionHeading.isColonTerminatedHeading` pins the authoring rule — ends in
`:` **and** parses no leading quantity — in the one place import and editor already shared, so there is a
single convention rather than two. `RecipeEditorDraft.transformIngredientSection` runs it live: typing or
pasting a header splits the card in front of you, minting the new section's UUID and carrying the line drafts
across; clearing a non-leading card's name merges it back up. The colon-free form is what reaches the `name`
column, so a header does not accumulate colons across save→reload→save (pinned by test). `Toggle("Header")`
and `applyIngredientLineDrafts` are gone, and the parser no longer writes `isHeader`. **No migration was
written** — the audit found 10 rows across 4 recipes, which Jon repairs by hand.

**The review's central finding: preserving IDs in the draft is not preserving identity.** The first cut moved
line drafts across the split with their IDs intact — and the save path never read `lineDrafts` at all. It
re-parsed the card's text with fresh UUIDs and merged against `existingLinesBySection[draftSection.id]`,
which is **empty for a section that was just minted**. Every line moved under a new header was therefore
deleted and re-created: new row id, and `canonicalName` / `shoppingCategory` / `doNotShop` / merged parse
confidence all dropped. **This is the exact loss the amendment predicted for derivation-on-save, relocated** —
a *new* section id misses a section-scoped lookup just as surely as a renamed one does, so the hazard was
never really about name-matching. The fix is the general lesson: **ingredient-line identity is global to the
recipe, not to a section.** The reconcile now matches parsed lines to the draft's line IDs and looks the
existing row up recipe-wide, and the delete pass runs once, after every upsert, against a plan-global kept
set — so a line can move between cards without a delete+insert reaching CloudKit.

**Two more the review caught, both invisible to the tests that shipped with the first cut.** The live split
rewrote the text box from its parsed line drafts on *every* keystroke, which silently ate a trailing newline
— you could not press Return to start a new ingredient line; it is now guarded behind an actual restructure,
so the raw text stays the author's while the card's shape is unchanged. And because the parser stopped
writing `isHeader`, the **flat-text direct-save paths** that never pass through the editor — the workbench
draft recipe and the menu-note promotion, both LLM-authored, where `For the sauce:` is a likely line — began
saving headings as ordinary **shoppable** ingredients; `RecipeRepository.save` now promotes headings for any
draft section that carries no line identity, which closes the hole generically instead of per caller.

**Amd1-D1a was built three times and is now deferred, with the evidence in the amendment.** "Start a section
here" needs one input — *which line is the caret on* — and the platform will not answer soundly. The
`.contextMenu` never appeared (`UITextView`'s edit menu wins the long-press); the `TextSelection` accessory
**crashed**, because a `String.Index` from the pre-split text traps in `samePosition(in:)` the moment the
split rewrites that text, and no amount of guarding fixes an index that cannot be validated against a string
it did not come from; and a `UIViewRepresentable` fixed the caret but lost `@FocusState`, which three rounds
of hand-rolled `becomeFirstResponder` never recovered. **A sound caret and sound focus were only available
from different components**, and the editor cannot have both without owning its text view outright — a much
larger change than the affordance justifies. So the colon shortcut is the only door, which is what Jon
ratified anyway, and D1a's own justification — six colon-free headers — is discharged by adding a colon to
those six lines once. `RecipeEditorDraft.startIngredientSection` and its test are kept as a documented seam;
every caret reader is deleted (`89bb1e2`).

**Method note.** Both review rounds were verified by running probe tests against the branch — a temp trigger
auditing every `DELETE` on `ingredientLines`, a re-save asserting enrichment survives — rather than by
reading the diff. The shipped suite was green through both, because it asserted at the draft level and never
followed a moved line through a save.

**Follow-through and what is deliberately NOT queued.** Three recipes still need hand repair (see
`CURRENT_HANDOFF.md`). Dropping the `isHeader` column is a schema change for later. Instruction sections keep
explicit card names — the colon rule is ingredient-only, because instruction prose routinely contains
mid-sentence colons. Amd1-D4 stands: the split makes a header *expressible*, not *representable in a
variation delta* — that stays ADR-0021's decision. **D1a is deferred, not queued** — revisit only if the
ingredients editor comes to own its text view for some other reason, never on its own momentum.

---
## ADR-0014 D3+D2 — Recipe text markup: bracket author notes and Markdown prose, both proven against the live library

**✅ Done 2026-07-28.** PR [#254](https://github.com/jonphillips/yes-chef/pull/254), branch
`codex/adr-0014-d3-d2-markup-text`, merge `5ef1e97`, five commits `f091917` → `cbdfd3c` across **two
architect review rounds** plus one device-review fix from Jon. Spec:
[ADR-0014](decisions/ADR-0014-recipe-text-editing-model.md) D3 then D2. Owner: Codex implement, Claude
architect/review. **No schema, nothing added to the prod-promotion list** — both decisions are
render/parse rules over columns that already exist and already sync. Full review:
[`reviews/REVIEW-2026-07-28-adr-0014-d3-d2-pr-254.md`](reviews/REVIEW-2026-07-28-adr-0014-d3-d2-pr-254.md).

**The shipped work.** `IngredientAuthorNote.segments(in:)` splits complete `[…]` spans from surrounding
ingredient text (an unmatched `[` stays ordinary text, so a half-typed editor value never loses content);
the parser reads quantity/unit/item/preparation from the bracket-stripped `parsingText`, lands the
annotation in the existing `comment` field, and keeps the bracket byte-for-byte in `originalText`.
`RecipeMarkdownText` renders `summary`, recipe/source notes, Playbook prose, and original-snapshot prose
through `AttributedString(markdown:)`; `IngredientLineText` renders bracket spans subdued. The editor stays
raw-Markdown passthrough. Ingredient and instruction **rows** remain structural — D2's boundary held.

**The device review caught the one thing tests could not: `.full` Markdown parsing ate the line breaks.**
Make-ahead's `•` bullets collapsed onto one line and Notes ran together, because full-syntax parsing treats
single newlines as soft wraps. Fixed with `.inlineOnlyPreservingWhitespace` (`96c742b`). **The architect
then certified the fix against the whole library rather than the sample**: all 455 non-empty
`summary`/`makeAhead`/`chefItUp`/`recipeNotes.text`/`sourceNotes` values from the 2026-07-28 backup were run
through the exact parsing options the view uses — **0 changed a single character, 0 threw.** Jon's
footnote-asterisk convention (`*Note: … **Note: …`, present in 14 notes) survives because neither `*` has a
valid right-flanking partner. That is the case a naive `.full` parse would have silently corrupted.

**Review round 2 found a silent data regression by measuring, not reading.** Moving the `isOptional` check
onto `parsingText` looked symmetrical with the four parsed fields — but "optional" written as a bracketed
aside is how a cook actually writes it, and **two real library rows** (`¼ lb. ground pork [OPTIONAL]`,
`1 tsp ground sichuan peppercorns [OPTIONAL]`) were `isOptional = 1` and would have flipped to `0` on their
next save with no signal. `isOptional` went back to reading the full text; `doNotShop` correctly **stayed**
on `parsingText`, where the exact whole-string match now makes `kosher salt [Diamond Crystal]` stop being
shopped. Same round: the web-capture path (`ParsedRecipePage`) was the only ingredient-line construction
site bypassing `IngredientParser.lines`, so captured recipes dropped `comment` and re-parsed *differently*
on their first editor save. Fixed by threading the field, **deliberately not** by swapping to `.lines` —
that would have silently changed `isHeader`, `doNotShop`, and `sortOrder` sequencing, three behaviors
belonging to Amd1-D1.

**A test that could not fail was caught by mutation, not by reading it.** The `doNotShop` regression pin
used `2 cups kosher salt [Diamond Crystal]`, whose parsing text (`"2 cups kosher salt"`) fails the exact
match either way — so it passed whether the implementation read the stripped text or the full original. The
architect proved it by reverting the implementation and watching all six tests stay green, then re-pinned on
the **bare** form where the two implementations actually differ, and re-verified that the new test fails on
the regression and only it does (`cbdfd3c`). **Same lesson as ADR-0030 S2's manufactured-evidence test, in a
different disguise: a green test certifies nothing until you have seen it go red.**

**Accepted on the record, not fixed: the bracket convention was already occupied.** D3 assumed `[…]` means
"a Jon note." Measured against the library, **83 bracketed ingredient lines across 27 recipes — all
shoppable, none previously carrying a `comment`** — are overwhelmingly publisher *metric equivalents*
(`140g`, `230 g`, `4 cm`, and one `click for printable recipe`). Those now populate `comment`, which
`groceryNotes` renders on the grocery list. **Jon's call 2026-07-28: live with it and see how it reads on a
real shop.**

**Deferred to a batched follow-on, recorded so it is not lost:** the Markdown policy and the
segment→`AttributedString` assembly live in the **app target**, so the line-break test asserts *Foundation's*
behavior and would stay green if the view reverted to `.full` — the defect the slice exists to fix, left
uncovered. Lift both into Core, sweep the one missed render site (`WorkbenchViews` summary shows literal
`**`), and drop the iOS-26-deprecated `Text` `+` concatenation in `IngredientLineText` while doing it.

**`normalize-recipe` was investigated and turns out not to exist** — the ADR's markup-awareness requirement
constrains a future thing, not live code. Measuring the library to establish that produced
[`efforts/import-text-normalization.md`](efforts/import-text-normalization.md), where the real finding is
that ATK/Cook's "Gather Your Ingredients" is page chrome captured as content: **101 shoppable ingredient
lines + 70 section names across 171 recipes**, all canonicalizing to the single grocery key
`gather your ingredient`. Latent, not manifest — 0 `groceryItemSources` point at them yet.

**Verification.** Package suite **501 tests / 96 suites** green at the merge head (496 → 501). Elevated
`generic/platform=iOS` build `** BUILD SUCCEEDED **`, run by the architect rather than taken on report.
`check-drift.sh` was **not** clean — it fails identically on clean `main`, the same
[[exported-import-not-link-time]] linker seam inside the *sqlite-data* dependency's dynamic test-bundle
build that PR #249 flagged and deferred. Not caused by this change; **now under separate investigation.**

## ADR-0030 S2 — Local backup restore: the recover half, and the discovery that the net covers a lost zone but not a poisoned one

**✅ Done 2026-07-28. This closes the ADR-0030 durability net for S1+S2; S3 (automatic snapshots) is a separate later dispatch.** PR [#252](https://github.com/jonphillips/yes-chef/pull/252), branch `codex/adr-0030-s2-restore`, merge `eacc57f`, six commits `a95e503` → `f48753d` across **three architect review rounds**. Spec: [ADR-0030](decisions/ADR-0030-local-backup-and-restore.md) S2, which gained **Amendment 1** out of this review. Owner: Codex implement, Claude architect/review. **No schema, nothing added to the prod-promotion list** — restore swaps a *file*; it touches no synced model. Verified by the architect at the review head rather than on report: `DatabaseBackupTests` **6/6 green** run locally (2 → 6), including two tests that construct a real `SyncEngine` and one that forward-migrates a genuine N−1 backup. The PR additionally reports `scripts/check-drift.sh` and the elevated `generic/platform=iOS` build green.

**The shipped work.** `YesChefDatabaseBackup.prepareRestore(from:to:currentSchemaVersion:migrate:)` copies a candidate to a staging file, validates it (is it a Yes Chef DB? does its stamped `user_version` agree with its applied-migration count? is it newer than this app can restore?), forward-migrates an older-but-valid backup through `DependencyValues.migrateRestoreCandidate(at:)` — which never honours the DEBUG erase switch, because a backup is recovery data, not a disposable dev database — re-stamps the marker, checkpoints, and discards the transient metadatabase the migration attach creates. `replaceLiveStore(at:with:syncMetadataURL:)` then swaps the closed live store with `FileManager.replaceItemAt` **first** and cleans sidecars **after**. `YesChefDatabaseBackupRestoreModel` takes an automatic pre-restore snapshot (keep-1 retention, plus a stale-staging sweep that also catches the dot-prefixed metadatabase orphan), stops the engine, swaps, and gates sync behind a **persistent** `disableForRestore()` flag that beats launch arguments and environment variables until the user deliberately re-enables. A `fullScreenCover` requires relaunch; "Undo Last Restore" restores from the pre-restore snapshot.

**The review's central finding: the slice's stated load-bearing step did not exist.** The handoff and D2 both asserted that a `VACUUM INTO` export "still carries the SyncEngine metadata and `PendingRecordZoneChange` bookkeeping," so S2's job was to **strip** those tables. It is not true. SQLiteData keeps every persisted CloudKit table in a *sibling attached metadatabase* (`URL.metadatabase`), and the only sync objects in the main database are `CREATE TEMPORARY TRIGGER`s — connection-scoped, never written to the file. `VACUUM INTO` copies only `main`, which the architect confirmed with a direct `sqlite3` experiment (attached metadatabase + firing temp trigger → snapshot contains the app tables and nothing else). The first implementation therefore shipped a `DROP TABLE … LIKE 'sqlitedata_icloud_%'` that could never match, **and a test that created the two tables itself before asserting they were dropped** — a tautology standing in for the one guarantee D2 exists to make. The strip is gone; the real load-bearing step is deleting the metadatabase **file**, and it is now covered by tests that build an actual `SyncEngine`. **The lesson worth keeping: a test that manufactures its own evidence is worse than no test, because the green run certifies the belief instead of checking it.**

**The hand-mirrored path got a drift detector.** `syncMetadataURL(for:containerIdentifier:)` reproduces SQLiteData's `package`-private naming rule, so an upstream rename would silently leave the *previous peer's* CloudKit state beside the restored store — exactly what D2 forbids, failing quietly. `attachedSyncMetadataURL(in:fallbackFor:containerIdentifier:)` now reads the truth from `pragma_database_list` with the string as fallback, and a test pins the two together so a rename fails the suite.

**Amendment 1 — OQ1 is answered, and the answer narrows the ADR's guarantee.** Re-enabling sync on a restored store resolves **in the cloud's favour**, not the restore's. Restore deletes the metadatabase and with it every `lastKnownServerRecord`; on start SQLiteData sees an empty `recordTypes`, treats all 31 tables as new, and runs `UPDATE <table> SET pk = pk` on **every row**, queueing the entire library at the live zone. Each collision returns `.serverRecordChanged`, and `upsertFromServerRecord` only performs its field-level merge when a `_lastKnownServerRecordAllFields` baseline exists — which after a restore it does not — so the server record overwrites the local row wholesale. **So the net covers a lost or blank zone (Development reset, account loss, new device), not a poisoned one:** if the bad state reached CloudKit, restoring a good backup and re-enabling sync re-imports it. Recorded as a Consequence, an answered OQ1, and a new **OQ5** (restore-authoritative — reset the zone and re-upload — deliberately *not* built, parked so it is never built on this ADR's momentum, per [[withdraw-not-defer-orphaned-schema]]). Amendment 1 is **Proposed**, not Accepted: the four-step mechanism is a code reading, and its promotion condition is a confirmation run in an **isolated CloudKit container** — explicitly not against the live zone, where the experiment costs a ~44k-record push and can resurrect deleted rows on both devices with no undo.

**The copy became binding, and the last unguarded tap got a gate.** The confirm alert and the restart cover now state that iCloud's copy wins for anything it still has — **⚠️ which measurement later proved backwards; all three strings were inverted 2026-07-29, see the OQ1 section below.** More consequentially, the *irreversible* moment is not the restore — it is the sync toggle, which was a single unguarded button after a relaunch that cleared the context. `YesChefCloudSync.isDisabledByRestore()` now gates a "Turn On iCloud Sync?" confirmation onto that path only, leaving the ordinary never-synced case untouched.

**Two risks accepted on the record rather than left silent.** Restore replaces the app-group store without an `NSFileCoordinator`, so an in-flight share-extension save can write to the unlinked prior inode and lose that write ([[extension-sync-construct-not-run]]) — accepted for a rare, destructive, user-initiated operation. And the N−1 forward-migration test pins the tail migration identifier by name, so every future migration must re-cut that fixture; the comment says so, and that is the honest trade, because a fixture that silently stopped being N−1 would make the test meaningless.

### ⚠️ Correction (2026-07-29): S2 merged with restore **completely non-functional**, and the green suite is why

**Found on the first real attempt** — Jon's isolated two-simulator pass for the OQ1 confirmation, one day after merge. Tapping **Restore** in the confirm alert did nothing at all: no pre-restore snapshot, no swap, no sync gate, no error, no restart cover. Silent no-op, every time. Fixed same day.

**The defect.** The confirm alert's presentation was bound to the model's payload — `isPresented: $backupRestore.isPrepared` — and `isPrepared`'s setter called `discardPreparedRestore()`. **SwiftUI writes `false` to an `isPresented` binding on *every* dismissal, including the one where the user tapped the confirm button, and it does so before the button's action runs.** So the dismissal deleted the staged candidate and nil'd `preparedRestore`; then `restorePreparedBackup()`'s `guard let preparedRestore` failed and returned `false`, which the call site reads as "don't show the restart cover." Every failure signal in the path was itself gated on the work having started, so the feature failed invisibly. The Undo Last Restore button rode the same binding and was equally dead. Fix: the view owns an `@State isConfirmingRestore`, `isPrepared` is read-only with a comment saying why, and `discardPreparedRestore()` is called from **Cancel only**.

**Why three review rounds and 6/6 green tests missed it — the part worth keeping.** Every test drove Core directly (`prepareRestore`, `replaceLiveStore`, `snapshot`); **not one went through `YesChefDatabaseBackupRestoreModel` and the SwiftUI binding.** The suite verified the parts and never the assembly, so a green run certified nothing about whether restore worked. This is [[verify-local-fix-reached-merge]]'s sibling at a different seam, and a second costume for the app-test-target lesson below ("a test suite that nothing executes launders regressions") — here the tests *did* execute, they just stopped one layer short of the wiring. **The architect read that setter in round one and logged it as benign dismissal cleanup**, never tracing SwiftUI's write-then-act ordering against the guard; the `Cancel` button *also* calling `discardPreparedRestore()` made the pattern read as deliberate, which should have prompted the question rather than settled it.

**The structural reason it was untestable at all:** `YesChefDatabaseBackupRestoreModel` hardcodes `YesChefDatabaseStorage.liveSharedDatabaseURL()`, which needs a real app-group container, so the model cannot be exercised from a package test even in principle. Injecting the store URL would make the confirm→restore sequence testable without a simulator. **Not done here** — noted as the follow-up that would actually close this class of gap. Saved as [[alert-ispresented-destructive-setter]].

### OQ1 measured 2026-07-29: restore is **authoritative**, and the architect's prediction was wrong

**Two simulators, isolated CloudKit container (`iCloud.com.jonphillips.yescheftest`), fresh Apple ID, fresh installs.** Both converged at 3 recipes / 39 metadata rows. Backup taken on A. On B: one recipe renamed `EDIT v1-BACKUP` → `EDIT v2-CLOUD`, one recipe **hard-deleted** (archive, then *Delete Permanently* from the Archive — the library "delete" is only `archived = true`, so the purge is a deliberate second step Jon had never performed before). A fetched both, so the backup was genuinely stale. A restored, then re-enabled sync with a single `start()` and no relaunch.

**Result: the restored library won everywhere.** `EDIT v1-BACKUP` beat `EDIT v2-CLOUD` in the zone and on B; the purged recipe was **resurrected on both devices** with a server record accepted. The checkpoint before the irreversible step showed exactly what was predicted — `recordTypes` 0, all-fields baselines 0 — and then the *conclusion* drawn from those zeros was refuted: local won every collision, not the server. ADR Amendment 1 is **withdrawn**; **Amendment 2** records the measured behaviour and **corrects D2**, whose "never risks a restore stomping the cloud" was wrong in the opposite direction. OQ5 (restore-authoritative as a future slice) is **closed as already-shipped**. Jon accepted the design explicitly: *"If I'm restoring from backup, it means something went wrong and I need to return fully to the previous state."* The S2 UI copy said the opposite of what happens and was **inverted the same day** across all three strings (confirm alert, restart cover, sync-enable confirmation).

**The half that held is the engine of the whole thing:** wiping the metadatabase empties `sqlitedata_icloud_recordTypes`, so `start()` treats every table as new and runs `UPDATE <table> SET pk = pk` on **every row** — the entire library re-pushes. That is why restore is authoritative and why deletions resurrect.

**Process note worth keeping.** Amendment 1 shipped as **Proposed**, with a named falsifier and a hard gate that its confirmation happen in a scratch container and explicitly **not** against the live zone. Being wrong therefore cost one evening on two simulators instead of a ~44k-record push and resurrected rows across two real devices. **The gate, not the reasoning, is what made the error cheap** — and the reasoning was a careful read of the right code path that still drew the wrong conclusion about which side wins. Saved as [[restore-is-authoritative]].

**Left open as OQ6, and it is the one thing between this and trusting restore:** after convergence the peer that performed the delete retains `_isDeleted = 1` for six records that are alive locally and carry `lastKnownServerRecord`. Nothing is queued, but a later full re-push could act on those flags and silently re-delete restored data. Own investigation; the two evidence simulators still hold the state. **The real-device pass is held until it is diagnosed**, because a restore now rewrites the live zone and every peer by design.

### OQ6 + OQ7 CLOSED 2026-07-29 (measured; ADR-0030 Amendment 3)

**OQ6 — CONFIRMED data-loss path, mitigated by protocol.** The held tombstone does fire: a peer's **unsent/held** delete that syncs *after* a restore **wins and silently re-deletes the restored record on every peer** (measured E2E). So restore is authoritative **only against settled peer state** — this **bounds** Amendment 2, it does not reverse it. Root cause is upstream SQLiteData tombstone handling — `upsertFromServerRecord` never clears `_isDeleted`, and `syncChanges` sends before it fetches — so **a point-free bug report is owed** (carried as the one loose end in CURRENT_HANDOFF § Ready Efforts). The resting tombstone self-heals on the next relaunch in the ordinary flow; the loss needs a *concurrent* restore. The mitigation is the **enforced restore procedure** (quiesce every peer → restore + re-enable on one device → reinstall the peers), now a NEW SLICE to build; deleting the app drops its unsent CKSyncEngine queue, and the whole mitigation rests on the app-group container clearing on delete (verify once on a throwaway install). The real-device S2 pass stays **held until that slice gates it**.

**OQ7 — CLOSED clean.** Images survive the re-push **byte-intact on the peer**; both asset- and record-level resurrection work. Caveat: a photo *replaced* since the backup resurrects as a **duplicate** (delete-row + insert-row). **Volume** (~2,163 assets at once → CKError 429 shape) stays a **real-device unknown** — keep it in the device pass. Durable takeaway saved as [[restore-is-authoritative]].

## ADR-0030 S1 — Local backup export: a CloudKit-independent durability net, export half

**✅ Device-passed by Jon 2026-07-28** — Settings → Import & Export → Export a Backup produced a `.sqlite` file through the Files exporter. PR [#250](https://github.com/jonphillips/yes-chef/pull/250), branch `codex/adr-0030-s1-export`, commit `cb13bf9`. Spec: [ADR-0030](decisions/ADR-0030-local-backup-and-restore.md) S1 (Export). Owner: Codex implement, Claude architect/review (one round, approved with non-blocking notes). **No schema, nothing added to the prod-promotion list** — the version marker is a `PRAGMA user_version` stamped on the *snapshot* file, not a change to the synced model. Verified: the PR reports `scripts/check-drift.sh` green, elevated `generic/platform=iOS` build green, and `git diff --check` green; the architect confirmed the load-bearing pieces against the tree rather than on report — `bootstrapDatabase(path:)` exists, migrations are name-registered and **append-only** (`Schema.swift` "stable prefix" rule), the GRDB migrator keys off the `grdb_migrations` table by identifier **not** `user_version` (so the stamp is free real estate), and `eraseDatabaseOnSchemaChange` stays opt-in behind a launch arg.

**The shipped work.** `YesChefDatabaseBackup.snapshot(from:to:)` (Core) runs SQLite `VACUUM INTO` against the live `DatabaseWriter` — OQ2 settled on `VACUUM INTO` over `DatabaseWriter.backup`. That reads one consistent transaction and folds uncheckpointed WAL frames into a single self-contained file, so the copy needs **no `-wal`/`-shm` sidecar** (the test asserts both are absent). It then reopens the copy and stamps `user_version` with the applied-migration count as the restore-compat marker, with `defer`-based cleanup if stamping throws and a `destinationAlreadyExists` guard. `YesChefDatabaseBackupExportModel` (`@MainActor @Observable`) stages a UUID-named file in `temporaryDirectory`, `await`s the off-main vacuum, and the Settings row hands it to `fileExporter` via a `Transferable` `FileRepresentation`; the temp file is discarded on **both** completion and cancellation. Two Core tests: a seeded snapshot round-trips recipe + `RecipePhoto` BLOB rows, asserts the stamp, and asserts no sidecars; a filename test pins `YesChef-Backup-YYYY-MM-DD.sqlite`.

**Byte-exact copy, not a serialization surface — held.** Images ride along as BLOBs inside the row, so one `.sqlite` file is the whole library with zero encode code (D1 / [[llm-vs-determinism-surface-boundary]]). The SyncEngine was untouched — this reads the same store everything else uses, explicitly not [[debug-erase-vs-sync-triggers]] territory.

**Three forward flags handed to S2** (recorded in CURRENT_HANDOFF Next Up, not defects here): (1) the exported file **still carries the SyncEngine metadata + `PendingRecordZoneChange` bookkeeping** — S2's strip is the load-bearing step that keeps a restored file from masquerading as an already-synced peer ([[extension-sync-construct-not-run]]); export-only S1 correctly defers it. (2) Migration **count** is a coarse version proxy — sound only while migrations stay append-only, so S2's compat check must gate on that invariant, not treat count-equality as identifier-equality. (3) The public `YesChefDatabaseBackup.schemaVersion(in:)` reader is currently unused and duplicates the `COUNT(*) FROM grdb_migrations` literal `stampSchemaVersion` already carries — S2 restore is its intended consumer; dedupe the SQL to one home when S2 wires it. Non-blocking nit left in place: the snapshot failure paths (`destinationAlreadyExists`, cleanup-on-throw) are untested.

## Recipe section grain S2+S3 — the editor edits every section

**✅ Device-passed by Jon 2026-07-28.** PR [#249](https://github.com/jonphillips/yes-chef/pull/249), branch `claude/recipe-section-grain-s2-s3`. Spec: [`efforts/recipe-editor-section-grain.md`](efforts/recipe-editor-section-grain.md) S2+S3 — this **closes the effort**. Owner: Claude (implement **and** architect — Codex was out of tokens). **No schema, nothing added to the prod-promotion list.** Verified: package `swift test` **486 / 94 suites** (480 → 486, six new grain tests plus the updated structure test), elevated `generic/platform=iOS` build `** BUILD SUCCEEDED **` with no new warnings in the changed files. `check-drift.sh` was **not** clean — but it fails **identically on clean `main`** at a linker error inside the *sqlite-data* dependency's dynamic (test-bundle) build (`StructuredQueriesCore` missing `IssueReporting` → `Ld … SQLiteData.framework`), the [[exported-import-not-link-time]] seam surfacing again; not caused by this change, flagged for a separate look.

**The shipped work.** `RecipeEditorDraft`'s four flat ingredient/instruction fields become two ordered arrays of section drafts (`RecipeEditorIngredientSectionDraft` / `RecipeEditorInstructionSectionDraft`); `init(detail:)` maps every persisted section, and the old flat init survives as a single-section convenience so `SampleData`, `WorkbenchDraftRecipe`, and new-recipe creation compile untouched. The reconciliation lives in Core, not the view — new `RecipeEditorSectionReconcile` turns the draft's sections into rows to upsert plus section ids to delete, **scoped per section** so a save never touches a section the draft didn't describe (orphan lines/steps whose section row is gone are carried through untouched — "nothing is lost"). `save(draft:)`/`saveEditableChildren` consume those plans and the four now-dead `merged*` helpers are deleted. The editor renders one block per section with a title field, the ingredient per-line header toggles, a **Delete Section** button when more than one, and **Add … Section** controls; the fraction pill row targets the focused section.

**Deletion was the one behaviour the merge-only path never expressed**, so its tests are the hardest: a two-section recipe round-trips draft → save → detail **unchanged** (the quiet pin), plus edit-second-section-leaves-first-untouched, rename, add, and a cross-section renumbering test proving global step-`sortOrder` uniqueness is no longer load-bearing (both sections restart at 0 and still order correctly, because S1's `InstructionStepGroup.groups` sorts by `(section.sortOrder, step.sortOrder)`).

**The settled question held the line.** No promote-on-paste, no typed-heading→section heuristic (ADR-0040 D2 — the human edits fields, never the wire format). Sections are made only by the **Add section** control; pasting a `For the sauce:` heading yields one section where capture would have made two, and that asymmetry is intended, not a defect to fix on momentum.

## Architect track — the app test target runs, 26 of 26

**✅ Done 2026-07-27. This closes the architect track and retires the "a test only counts in `YesChefPackage/Tests/`" rule.** PRs [#247](https://github.com/jonphillips/yes-chef/pull/247) (make it run: 21/26) and [#248](https://github.com/jonphillips/yes-chef/pull/248) (green the last five), plus [jon-platform#34](https://github.com/jonphillips/jon-platform/pull/34), which #247 depends on. Spec: [`efforts/app-target-tests-to-core.md`](efforts/app-target-tests-to-core.md), rewritten in place — **its previous central claim, that the target was unfixable, was wrong.** Owner: Claude, off to the side of the Codex dispatch, as scoped. Package tests **476** at #248's head (468 → 476).

**The diagnosis was wrong four times, and every time the same way: the first line of the log was read as the blocker.** The brief recorded `ld: warning: … not an allowed client of SwiftUICore` and concluded that a dynamic library pulling SwiftUI transitively hits Apple's restricted-client list, that the fix meant re-linking a shared package, and that it wasn't worth it. **That line is a warning — it still appears in builds that now succeed.** The error was four lines below it: undefined GRDB / StructuredQueriesCore symbols. Two later readings (missing `await`s, then "the same wall") were each a real first error mistaken for the wall behind it. The standing instruction that came out of this — *report the first error you hit as the first error, not as the blocker* — was written after the third miss and earned by the fourth.

**The linkage defect worth remembering: `@_exported import` is a compile-time re-export, not a link-time one.** CloudSyncKit, YesChefCore, the app, the share extension and the test bundle all used GRDB/SQLiteData types reached through sqlite-data's re-exports **without declaring them**. Static linking hides that completely — every transitive object is in the same image — so `swift test` and the generic app build stayed green for months. A test bundle turns every SwiftPM product dynamic, and the undeclared dependencies stop resolving. **The build configuration that exposes a latent defect is not the configuration that caused it.** Saved as [[exported-import-not-link-time]].

**The second defect made every dependency override a no-op.** A duplicated `Dependencies` runtime in the test bundle meant `withDependencies { }` silently did nothing — eleven tests failing for one reason, wearing eleven costumes. It also invalidated the brief's *second* argument for moving app-layer models to Core ("models holding `@Fetch` are awkward to test in place"): those suites now pass untouched.

**One of the five remaining failures was a live user-visible bug, not a stale test.** `RecipeYieldScaler.scaledText` used the *anchored* `QuantityParser.leadingQuantity`, so any yield text leading with a word returned nil, and nil meant "leave it alone" — `Serves 2` ×3 stayed `Serves 2`. Git dates it: the anchor arrived on Jul 16 with an otherwise-better redesign, and on Jul 18 the tests were mechanically re-pointed at the new API **with their old expected strings left in place**. Nothing ran the target, so it sat for nine days. Fixed with a new `firstQuantity(in:)` used by the yield scaler only — `leadingQuantity` stays anchored because `IngredientScaler` needs it (so `"onions, about 2 handfuls"` doesn't scale off the 2). **A test suite that nothing executes does not merely fail to catch regressions; it launders them, because the green build says the expectations were checked.**

**What it changes going forward.** `check-drift.sh` now compiles and links the target on every run and prints where execution stands, so it cannot go silent again; execution stays opt-in behind `YESCHEF_RUN_APP_TESTS=1` because it boots a simulator and hits a teardown hang — **not** because anything is known-red. Core remains the default home for tests since it runs unflagged. The move-19-tests-to-Core plan is **withdrawn as scoped** — its premise was that the target couldn't run — leaving one small optional sweep (`WorkbenchCompareAlignmentModel`, `RecipeScaleFormatting`) queued on the *keep-pure-logic-out-of-the-App-layer* merits instead.

## Recipe section grain S1 — instructions are read at the grain they are stored

**✅ Architect-approved 2026-07-27; device pass owed.** PR [#246](https://github.com/jonphillips/yes-chef/pull/246), branch `codex/recipe-section-grain-s1`, commits `8bf669c` → `c4305b6` (**three review rounds**). Spec: [`efforts/recipe-editor-section-grain.md`](efforts/recipe-editor-section-grain.md) S1, which gained an amendment out of this review. **No schema, nothing added to the prod-promotion list.** Verified at the review head by the architect, not taken on report: `scripts/check-drift.sh` clean at **479 tests / 93 suites** (475 → 479), elevated `generic/platform=iOS` build `** BUILD SUCCEEDED **` with no new warnings. **Jon's device pass owes** the Samin capture showing its three instruction sections with subheads, and — the canary — a single-section recipe looking and spacing exactly as it did before.

**The shipped work.** `InstructionStepGroup.groups(sections:steps:)` is the one place that orders instructions: sections by `(sortOrder, id)`, steps within a section by `(sortOrder, id)`, orphans trailing. `RecipeDetailData.instructionGroups` is a thin wrapper over it, and the reader, Compare, the adjustment review, the adjustment engine, the recipe-chat context, the meal-plan hand-off, and the snapshot bundle all consume it. Section names render as subheads with `isHeader`; unnamed sections render their steps unheaded, so a single-section recipe is untouched. **This retires the load-bearing assumption that step `sortOrder` is globally unique** — the assumption S2's per-section renumbering was one save away from breaking.

**The blocking find: the projection lost steps, and the call sites hid the loss.** The first commit drove off `instructionSections` and `compactMap`ped, so a step whose section was missing vanished — and because all three views gate on `groups.isEmpty`, the failure mode was not "one step missing" but **the recipe rendering with no instructions at all**. Two things in the codebase already said dropping was wrong: the `ingredientGroups` twin this was modeled on falls back to the ungrouped list when grouping yields nothing, and the pre-existing `sortedInstructionSteps` deliberately kept orphans behind an `Int.max` fallback. **And it is reachable, not theoretical: CloudKit has no cross-record transaction**, so a step row landing before its section row is an ordinary sync window — during which the cook would see an instruction-less recipe with no error. The projection is now total over steps, orphans cluster into trailing unnamed groups, and `RecipeRepository.fetchDetail` logs one `AppLog.dataIntegrity` warning per fetch. **The generalizable form: copying a shape copies its styling, not its invariants** — the ingredient path was written defensively and the instruction path inherited only its looks.

**The brief asserted a negative that a grep refutes.** *"Continuous numbering … only wins if a step ever cross-references another by number, which nothing in the app does"* — but `RecipeMethodStepReplacement.stepNumber` **is** a global 1-based index, `adjustmentContext` numbers continuously across sections for the model, and the unresolved-step error says "step 7" to the cook's face. Per-section renumbering on the adjustment review would have made the model's reference space and the user's screen disagree. Settled by Jon: **reader and Compare restart at 1 per section; the adjustment review stays continuous**, now recorded as an amendment in the effort. **A "nothing in the app does X" claim is a grep, not an assertion** — and the surface that refuted it was one of the three the slice was already editing.

**Consolidation by copy is not consolidation.** Round two deleted the duplicate ordering rule from `RecipeAdjustment.swift` and, in the same commit, re-created it as a private copy inside `RecipeBundleCoding` — because a `RecipeBundle` is not a `RecipeDetailData` and the wrapper didn't fit. So the count of implementations was unchanged and the two already disagreed on orphan handling, which is precisely how the blocking find got in. Fixed by hoisting the rule to a static entry point over `(sections:steps:)` that both receivers can call. **When a second consumer can't take the same receiver, hoist the rule — don't copy it into the receiver that can.**

**Two smaller corrections, each a category.** Nesting the steps inside a per-group `VStack` silently re-assigned which stack owns step-to-step spacing, tightening it from 14 → 8 in the reader and the adjustment review and 12 → 8 in Compare — **a nesting change is a layout change**, on the single-section recipe that was supposed to look identical. And the orphan warning first lived inside the computed projection, which `body` reads on every pass: a diagnostic that fires per render buries the signal in exactly the window it exists for, so it moved to the load path where it fires once per fetch.

**The last flatten was in the app layer, where the package build cannot see it.** `HandoffIntents` built the meal-plan hand-off's method lines with a global `sortOrder` sort — the same interleaving defect, on the outbound prompt — and survived two review rounds because it is App-target logic that `check-drift.sh` never compiles and no Core test can reach. This is the Verification Pattern's *"keep pure logic out of the App layer"* corollary claiming another one; it was found by grep at review, not by a build.

## ADR-0047 S1+S2 — capture escalates to an LLM when the page carries no machine contract

**✅ Architect-approved 2026-07-27; Samin path device-passed by Jon, partial-page path not device-covered (see below).** PR [#245](https://github.com/jonphillips/yes-chef/pull/245), branch `codex/capture-llm-fallback`, commits `1ee9fea` → `3f24c83` plus architect-applied fixes (**one review round**). Spec: [ADR-0047](decisions/ADR-0047-llm-capture-fallback.md) S1 + S2, which gained [Amendment 1](decisions/ADR-0047-llm-capture-fallback.md#amendment-1--the-ladders-arithmetic-the-gates-membership-and-an-escalation-point-that-does-not-exist-2026-07-27) out of this review. **No schema, nothing added to the prod-promotion list.** Verified at the review head by the architect, not taken on report: `scripts/check-drift.sh` clean at **475 tests / 93 suites** (473 → 475), SwiftLint `--strict` 0 violations across 283 files, elevated `generic/platform=iOS` build `** BUILD SUCCEEDED **` with no new warnings. **This is the first model call in the capture path**, which has been 100% deterministic since ADR-0007.

**The shipped work.** `RecipeStructuredTextSerializer` renders the cleaned `Document` as markdown-ish text — `h#` → `## `, `li` → `- `/`1. `, paragraphs as blocks — so the `<ul>`/`<ol>`/`<h#>` structure that **is** the recipe boundary on a no-contract page survives into the prompt (D3). `WebRecipeCaptureClient` gains `escalate(draft:)` and `reextract(draft:)` at the async boundary, gated on the warnings the pure parser already computed; `WebRecipePageParser.parse` stays pure and synchronous and the share extension satisfies "never escalates" by never calling it (OQ2). `RecipeExtractionClient` declares the call at the ADR-0043 chokepoint (`surface: .capture`, `task: .recipeExtraction`, `contextLayers: [.structuredPageText]`), budgets 16k for reasoning **and** JSON, throws loudly on truncation or unparseable output, and instructs the model that page text is untrusted data and that a gap comes back as a gap. `RecipeCaptureView` marks model-extracted sections, distinguishes extraction failure from "page had nothing," and offers re-run off the retained `originalHTML` — no refetch, so it works on a page captured while authenticated.

**The blocking find: "the model never outranks the contract" was an integer that only reached half the data.** `modelPriority = -1` does exactly what D6 promises — for scalars. `RecipeAttributeVotes` reconciles **scalar page facts only**; the ingredient and instruction lists have no votes, and `RecipeParseBuilder` appends them. So on a partial page — deterministic ingredients present, instructions missing, gate fires on `.noInstructions` — the model's whole-page extraction (OQ3) contributed its ingredient list *alongside* the deterministic one, and the review form showed the recipe twice. Probed rather than reasoned: microdata beans plus a model that says `1 lb dried beans` where the page says `1 pound dried beans` yields two ingredient sections, both live. Fixed by suppressing a whole half the deterministic ladder already produced, per half rather than per section because the gate fires on a *missing half*.

**The test that could not fail is the more valuable half of that find.** `deterministicIngredientsSurviveAModelInstructionMerge` existed precisely to pin this case — and fed the model **byte-identical** ingredient lines, so `addIngredient`'s exact-string dedupe swallowed the duplicates and the assertion passed on luck. The defect and its regression test shipped in the same commit, the test agreeing with the bug. **A merge test whose fixture echoes the deterministic wording tests the dedupe, not the merge — and the model rewording something is the normal case, not the edge case.** Both directions are now pinned with reworded model output.

**Tier policy has one home, and a second copy of it cannot tell the truth.** The call site hand-rolled its own `useFrontier` switch instead of the shared `resolveTier`. It never consults `apiKeyStore`, so it can never emit `.degradedToOnDevice` — a cook whose frontier key had been removed would get a record claiming `.userSelectedTier` for a provider they no longer have. ADR-0043's entire premise is that a call declares itself **accurately**, so a duplicated resolution path is not a style nit there; it is the record lying. Now `resolveTier(…, requirement: .onDeviceCompatible)`: frontier by default per OQ1, honest degradation, pinned by a test that asserts the degraded record.

**Two smaller corrections.** The `isExtracting` progress label was dead on the URL-fetch path — `isFetching` stays true across escalation, so the `else if` never rendered and the slowest step in the flow hid behind "Fetching recipe page"; the narrower state now reports first. And the gate deliberately **omits** `.noStructuredRecipeData`, which D1 named: a per-site extractor produces both halves from a page with no machine contract, so including it would send exactly those pages to the model. The narrowing was right and is now the ADR's text rather than an undocumented divergence.

**OQ2 resolved a question whose escalation point does not exist.** "Escalation happens when the app opens the draft" — but `ShareViewController` reviews and commits straight to the database, so a share-extension capture never becomes an app-side draft. The binding half stands (the extension does no network or model work), but the consequence is that a no-contract page captured through the share sheet gets **no fallback at all, not a deferred one**. Recorded in Amendment 1 as a stated gap rather than closed on ADR momentum; it gets scoped when Jon actually shares such a page.

**A measurement worth keeping.** D3's worry was structure loss, but the obvious counter-worry — that a structure-preserving serialization balloons the prompt — measures the other way on real captured pages: the 209KB ATK fixture serializes to 6,500 characters and the 344KB NYT-comments fixture to 19,779, both **smaller** than the `.text()`-flattened `bodyText` (9,442 / 21,297) they replace. Link-dense-block removal is doing real work; input size is not a constraint on this rung.

**Device-pass caveat, stated rather than assumed.** Jon's pass was against the pre-fix head on the Samin Substack page — a page with **no** deterministic halves, where whole-half suppression is a no-op. The behaviour the fix changes (a partial page, where one half comes from markup) is covered by Core tests only.

## Chat-ask uniformity S1–S4 — one Ask, on every surface

**✅ Architect-approved 2026-07-27; device pass owed.** PR [#244](https://github.com/jonphillips/yes-chef/pull/244), branch `codex/chat-ask-uniformity`, commits `968ed52` → `5e9552a` (**two review rounds**). Spec: [`efforts/chat-ask-uniformity.md`](efforts/chat-ask-uniformity.md) S1–S4. **No schema, nothing added to the prod-promotion list**; one Core rename (`ChatSurfaceResolution.Sections.switchable` → `.starters`). Verified at the review head by the architect, not taken on report: `scripts/check-drift.sh` clean at **468 tests / 92 suites**, elevated `generic/platform=iOS` build `** BUILD SUCCEEDED **`. **Jon's device pass owes** Menu (Ask opens free, Discuss ▾ seeds into the open thread, Ask again closes), Recipe unchanged in both presentations — the canary — plus Calendar and Workbench, and the rotation behaviour noted below. This also carries **PR #243's owed device pass** on the same four surfaces.

**The shipped work.** `ChatSurface.Sections` stops being typed to `PlaybookSectionKind` — a Recipe concept — and carries host-supplied `ChatStarter` values instead. The Recipe keeps its typed `selectSection:`/`activeSection:` factory API and the translation happens *inside* `ChatSurface.recipeStarters`, so the reference implementation cannot drift into stringly-typed call sites. The Menu's pre-flight verb `Menu` — the one live defect, the reason **there was no way to look at a Menu chat without buying a discussion first** — becomes a plain Ask toggle, with Prep Plan and Complement moved into the panel's Discuss ▾ and "Regenerate whole plan" staying on the playbook header as its own control. The three open-only entry points gain the close-if-open guard, two `Chat` labels become `Ask`, and both places that named a Recipe concept to surfaces that lack it — the empty-state clause and the starter menu's accessibility label/hint — stop doing so. This answers [`chat-surface-contract.md`](efforts/chat-surface-contract.md)'s Open Question 1: the Menu's `sections: .none` was an omission, and starters are the real answer.

**The blocking find: moving state ownership halfway is worse than not moving it.** S2 gave `MenuDetailModel` a `chatModel` while `MenuDetailView` kept owning the presentation in `toolOverlay`/`compactTool`. Two paths cleared the presentation without passing through the model — compact swipe-to-dismiss (a `.sheet(item:)` with no `onDismiss:`) and Browse Recipes replacing an open chat overlay. Both left `chatModel` non-nil with **no panel on screen**, so `isAskActive` read true, the button rendered its tinted "Panel open" state, and the next Ask tap took the *close* branch: nothing opened, and in the browser case the browser closed instead. Two taps to reopen — a regression on the exact button the effort exists to fix, on the iPhone path, shipped inside the fix for it.

**Why the ported guard didn't port.** The brief said *"port the Recipe's warm-thread guard; do not re-derive it,"* and the guard was copied faithfully. It works on the Recipe because `RecipeDetailModel.destination` **is** the presented item — swipe-dismiss cannot strand it. Copied onto a model that did not own presentation, the guard was correct and the state beneath it was not. The same instruction produced correct code at the three S3 sites (`WorkbenchDetailModel.destination`, the Calendar's `compactChatModel`) for exactly that reason: those are the presented item. Fixed by making `MenuDetailModel.tool` the sole presentation state, with `chatModel` derived from it and the compact sheet bound through a size-class-aware `Binding`. **The generalizable form: a behavioural guard is only portable to a host whose state has the same ownership shape — check the shape, not the code.**

**A rotation dividend nobody asked for.** Collapsing to one `tool` made the `onChange(of: usesToolOverlay)` teardown unnecessary, so the panel now migrates between the trailing overlay and the compact sheet across a rotation **in both directions**. Previously regular→compact dismissed the chat outright and compact→regular left the sheet stuck up. It is an improvement and the natural consequence of single-source, but it is a visible behaviour change outside the brief, so it rides into the device pass named as one rather than discovered.

**The dead-test-target diagnosis moved a third time, and the third reading was also wrong.** The dispatch reported app-test execution blocked by missing-`await` errors in `AIHandoffMenuPasteTests`. Those are real, pre-existing on `main`, and two lines ([`:92`](../YesChefAppTests/AIHandoffMenuPasteTests.swift) and `:127`, both `database.write`/`database.read` inside an async `operation:`). But patching them locally and re-running `build-for-testing` clears them and hits **the same `CloudSyncKitdynamic-product` link failure** the original brief recorded — as, evidently, did the 2026-07-27 "missing GRDB / StructuredQueriesCore conformances" run. Three successive diagnoses were each the first line of a log that stopped early; the wall has not actually moved. **A first error is not a blocker.** S4's test is therefore the third in a row written into a target that executes nothing — and fixing that target is now its own architect track rather than a standing shrug.

## Chat surface contract S2–S4 — one descriptor, no silent defaults

**✅ Architect-approved 2026-07-27; device pass owed.** PR [#243](https://github.com/jonphillips/yes-chef/pull/243), branch `codex/chat-surface-contract-s2-s4`, commits `dbe733e` → `e87c1c5` plus one architect-applied one-liner (**three review rounds**). Spec: [`efforts/chat-surface-contract.md`](efforts/chat-surface-contract.md) S2–S4; S1 shipped separately in PR #240. **No schema, no Core behavior change, nothing added to the prod-promotion list.** Verified at the review head by the architect, not taken on report: `scripts/check-drift.sh` clean at **467 tests / 92 suites** (466 → 467, the new Core suite discovered), SwiftLint `--strict` 0 violations across 277 files, elevated `generic/platform=iOS` build `** BUILD SUCCEEDED **`. **Jon's device pass owes** all four surfaces in both presentations on iPad Pro 13-inch (M5) and iPhone 17 Pro — confirming nothing moved visually, which is this effort's whole acceptance bar.

**The shipped work.** `RecipeChatPanel` drops from eight parameters (six defaulted) to two: a chat model and one `ChatSurface`. Its three structural questions — sections, presentation, dismissal — take no default, so a ninth surface fails to compile until it states them. `presentation` folds `showsEmbeddedHeader` and `onDismiss` into one choice, making their disagreement unrepresentable rather than documented. Compare's hand-rolled `.onAppear`/`.onChange` tier pair is deleted in favour of one field the panel honours. The three split sites get independent detent identities, with `"recipeChatWorkspaceDetent"` migrated forward as the Calendar's key so a dogfood device does not reset to `.balanced`. Per-host static factories (`.recipeAskSheet`, `.menuTool`, `.workbenchDetailColumn`, …) are the only construction path, enforced two ways: a `private` memberwise init, and a `check-drift.sh` guard that no raw `ChatSurface(` initializer exists outside `ChatSurface.swift`.

**The blocking find: a three-case enum answered a two-part question, and the third case lost both halves.** `Presentation` conflated *"does the panel draw its own header"* with *"who owns dismissal."* `.column` needs an embedded header **and** host-owned dismissal, which the enum could not express — so `showsEmbeddedHeader` resolved `false` for columns, and three things changed at once on every iPad split surface: the in-column header stopped rendering, the `if !showsEmbeddedHeader` toolbar branch pushed `chatOptionsMenu` into the **host's** navigation bar, and `RecipeChatPanelNavigationChrome` overwrote the host's `navigationTitle` with the chat subject. Calendar, Workbench detail and Workbench Compare all regressed — **exactly the chrome leak G5 fixed, and exactly what the effort's own "not a redesign" clause forbade.** The fix was letting `.column` draw the header too, which is the enum admitting the two questions were never one.

**Folding a duplicate is not the same as relocating the survivor.** The effort said fold `ChatWorkspaceSplit`'s tier propagation and `WorkbenchCompareChatSheet`'s copy into one field. The first commit moved the `.onAppear`/`.onChange` pair from the split's body — always mounted — into `RecipeChatPanel`, which renders only `if liveChatWidth > 1`. At the `.readerOnly` detent the panel never mounts, so `compareTier` stayed pinned at its `.onDevice` default and `WorkbenchCompareView(tier:)` rendered the wrong tier for any cook whose `activeTier` resolves to `.frontier` — while collapsing the chat column to read the compare matrix full-width is precisely when that badge matters. Fixed by returning the propagation to the split and gating the panel's copy on `panelOwnsActiveTierPropagation`.

**The identity moved into the descriptor; the storage it named did not.** S3 gave the detent a `DetentIdentity`, but `ChatWorkspaceSplit` kept taking an `@AppStorage` binding *alongside* it — one fact, two parameters, free to disagree, with nothing to catch a `.workbenchDetail` identity bound to the Calendar's key. That is the same "encoded twice, can disagree" shape the effort exists to kill, reproduced inside the fix for it. The split now builds its own `@AppStorage` from `detentIdentity.rawValue` in `init`, and three hosts lost their storage declarations. One consequence rides along: the Calendar's chat button can no longer write the detent directly, so it signals through a `toggleRequest` counter the split observes.

**The lesson worth the most here is the architect's, not the agent's: a review that contradicts the handoff costs a round.** The dispatch was told S4's assertions belong in `YesChefCore` because `YesChefAppTests` executes nothing, and the first commit did that. **The review then sent the test to `YesChefAppTests`** — the one target the Verification Pattern names as dead — and the second commit complied, producing a test that was better in every respect except that it ran. The correct criticism of the Core test was that it was **tautological**, not that it was misplaced: it constructed ten `ChatSurfaceResolution` literals and asserted they equalled the same literals, never touching a call site, and would not have caught the `.column` defect it existed to prevent. **A test can be in the right target and prove nothing, and noticing the second failure does not license moving it.**

**What made the third round's test real was moving the *behaviour* into Core, not the assertions.** `drawsEmbeddedHeader` and `panelOwnsActiveTierPropagation` — the two properties whose values were wrong in round one — now live on `ChatSurfaceResolution.Presentation`, with the app-layer enum delegating to them. That is what turns "assert the mapping" from tautology into a regression pin: both defects are now a failing Core test rather than a device-pass discovery. The generalizable form: **a contract test is only worth its line count if the thing it asserts is the thing production reads.** Round one's Core type was a parallel description of the app's behaviour; round three's is the behaviour.

**A guard that has never failed is not known to work.** The construction-path check was probed in both directions before approval, not merely observed passing: a scratch file containing a raw `ChatSurface(...)` correctly failed it before `swift test`, and `let x: ChatSurface = .init(...)` **silently passed** — the memberwise init was still internal, so the textual guard had a hole the compiler could have closed for free. Hence the architect one-liner: `private init`, with the factories (static members of the type) unaffected. The grep guard is now belt-and-braces over a compiler-enforced rule, which is the effort's own thesis applied to its own enforcement — *unrepresentable, not documented*.

**The residual gap, stated rather than papered over.** Nothing executable proves that `RecipeDetailView` calls `.recipeAskSheet` rather than some other factory; that assertion needs the app target, and the app target does not build. This is the second effort in a row to want a test it cannot run — **and the failure mode has changed since [`efforts/app-target-tests-to-core.md`](efforts/app-target-tests-to-core.md) was scoped.** That brief records `CloudSyncKitdynamic-product` failing to link `SwiftUICore` ("not an allowed client"); a `build-for-testing` run on 2026-07-27 instead died on missing GRDB / StructuredQueriesCore conformance symbols, reproducibly and identically on `main`. The diagnosis in that brief is stale and is being re-derived directly.

**Deliberately not done, and now on the record as intent:** the effort's two Open Questions shipped as assumed — the Menu gets no section switcher, and the two Workbench splits get independent detents. The first is answered properly by [`efforts/chat-ask-uniformity.md`](efforts/chat-ask-uniformity.md); the second stands.

## ADR-0032 S3 — the reference list UI, and the in-app browser's "Capture to Workbench"

**✅ Architect-approved 2026-07-26; device pass owed. This closes ADR-0032.** PR [#242](https://github.com/jonphillips/yes-chef/pull/242), branch `codex/adr-0032-s3-reference-ui`, commits `8e16815` → `c123557` plus one architect-applied one-liner (**three review rounds**). Spec: [`ADR-0032`](decisions/ADR-0032-workbench-reference-material-fetch.md) [Amendment 1](decisions/ADR-0032-workbench-reference-material-fetch.md#amendment-1--the-scoping-pass-gated-capture-moves-into-the-in-app-browser-and-the-extract-becomes-synced-content-2026-07-25) S3. **No new table** — S1's `workbenchReferences` is already on the prod-promotion list — but a **new synced enum raw value** (`pastedText`), which is the one forward-compatibility caveat below. Verified at the review head by the architect, not taken on report: `scripts/check-drift.sh` clean at **466 tests / 91 suites** (462 → 463 → 465 → 466), elevated `generic/platform=iOS` build `** BUILD SUCCEEDED **` with no new warnings. **Jon's device pass owes** public URL capture, thin/gated browser capture, replacement confirmation, duplicate refresh, pasted-text fallback — on both iPad Pro and iPhone 17 Pro.

**The shipped work.** Reference material gets its own section on the workbench: add, label-edit, delete, and a layered acquisition path exactly as Amendment 1 ratified it — public URL → programmatic `fetchHTML`; a **thin** extract (S1's under-1,500-character signal) offers "Open in Browser to Capture" so the authenticated DOM does the work the server fetch cannot; pasted text survives as the last resort and now carries its **own** capture kind rather than masquerading as a browser capture. Refresh is an explicit replacement of a durable, non-recomputable extract: the row shows its capture kind, the confirm names it, and a browser-captured reference's refresh routes back through the browser. `duplicateSourceURL` is surfaced as the "already here — refresh it?" affordance on both `store` and (new in this slice) `refresh`, and the dialog now names *which* reference gets replaced and which is left alone. S3 added no core beyond a projected list query, `updateLabel`, and the pasted-text kind — the acquisition and management UI over a finished S1+S2 core, as scoped.

**Both S2 carry-forwards are discharged.** The extract cap came down from 256,000 UTF-8 bytes to the frontier budget's 160,000 — measured in bytes against a character budget, so it is conservative in the safe direction and an extract can no longer be stored, synced and listed yet be unreachable at every tier. And `WorkbenchDetailRequest` no longer hauls full extracts: the list reads a projection of label/kind/status/dates, and the chat context is an on-demand scoped read.

**The blocking find, and the reason it is worth writing down: the fix that satisfies an instruction can defeat it.** The dispatch said keep `reducedText` off the always-on `@Fetch` ([[sqlitedata-fetch-writer-convoy]], ADR-0029 Finding 8). The first commit removed references from `WorkbenchDetailRequest` — and added a *new* standing `@Fetch` of `WorkbenchChatContextRequest`, which re-runs the **entire** detail request (every candidate's full recipe detail, the draft recipe) **plus every full extract**. Net: two heavy detail reads and all extracts, synchronously on the writer, on every workbench mutation — strictly worse than what it replaced, reachable from the debounced inline title editor. **The diff read as compliance.** The correct shape was already in the repo two files over: `HandoffAppOperations` does an on-demand `database.read`.

**A defaulted parameter on a completeness-carrying initializer is how a shipped slice silently un-ships.** Moving `references` off `WorkbenchDetailData` gave `WorkbenchChatContext(detail:references: = [])` a default — so the two ADR-0042 outboard handoff call sites kept compiling, kept running, and shipped **zero** reference material. S2's stated deliverable was "one source, both surfaces"; S3 quietly made it one. The fix was **deleting the default**, not patching the call sites, which is the general move: on a value whose entire job is completeness, a default is a decision made by whoever doesn't type it — the same sentence [`efforts/chat-surface-contract.md`](efforts/chat-surface-contract.md) is built around, arriving here on its own.

**Two bugs can protect each other.** The replacement confirmation shipped as `Text("This replaces the durable (context.captureKind.referenceDisplayName.lowercased()) extract…")` — a missing backslash, so the cook read the source expression. It **compiled because it was broken**: `referenceDisplayName` was `private` to a different file, so the correct interpolation would not have built. The literal-string defect and the visibility defect concealed each other, and this was the one sentence carrying Amendment 1's whole point (show the capture kind at the replacement decision). Fixed by moving the copy into Core as `replacementConfirmationMessage` with a test pinning the exact sentence — better than the visibility fix that was asked for.

**A modal triggered from inside a sheet belongs on the sheet.** Four paths presented dialogs and a `fullScreenCover` from `WorkbenchDetailView` while the editor sheet covered it — the editor's "Fetch and Replace Extract" was simply dead, and the thin → browser hop was a dismiss-and-present in one transaction. The repo already had the working pattern at [`RecipeCaptureView.swift:136`](../YesChefApp/RecipeCaptureView.swift), which presents `WebExtractorBrowser` *from within* the capture sheet. Related: browser capture reported `.extracted` on a path that had stored nothing, because `storeReference` swallowed the duplicate error and returned void — a success dismissal over a no-op write.

**Removing liveness as a side effect of a performance fix, twice.** Round 2 correctly deleted the standing `@Fetch` — and replaced it with a one-shot snapshot keyed on `isSplitEnabled`, which froze `ChatWorkspaceSplit`'s `onChange(of: context)` → `updateContext` path ([`RecipeChatWorkspace.swift:113`](../YesChefApp/RecipeChatWorkspace.swift)): the open iPad chat pane kept whatever context it had when it appeared. Round 3 correctly re-keyed on `workbench.dateModified` — an invariant every reference op maintains — but **replaced** the split-toggle key instead of joining it, so widening from compact on iPad (rotation, Stage Manager) left `chatContext` nil and the chat column absent until some unrelated write. The architect applied the composite key. **Each round was right about the thing it was fixing and lost a different input to the same expression**; the general form is that a cache-invalidation key has as many inputs as the thing it feeds has reasons to change, and dropping one is invisible in a diff that adds the other.

**Every defect across three rounds was in the app layer, which executes no tests.** The core additions were correct on first submission and stayed correct. That is not a coincidence and it is the sharpest available argument for [`efforts/app-target-tests-to-core.md`](efforts/app-target-tests-to-core.md): the layer with coverage held, the layer with none produced six defects in a slice its own dispatch called "UI over an already-complete core."

**Forward-compatibility caveat, carried into the device pass.** `WorkbenchReferenceCaptureKind.pastedText` is a new raw value in a **synced** column. A device on this build writing `"pastedText"` will fail to decode on a device still on the previous build. Two devices, Development CloudKit, low stakes — but **update both before saving a pasted-text reference.**

**Still a guess, by design: the `isThin` 1,500-character threshold.** Nothing in this slice validated it against real pages. The device pass watches for legitimately short notes triggering a pointless WebView render.

---
## ADR-0032 S2 — the workbench's reference material reaches the model

**✅ Approved, 2026-07-26.** PR [#241](https://github.com/jonphillips/yes-chef/pull/241), branch `codex/adr-0032-s2-reference-context`, commits `34f1cd7` → `c9b611e` (one review round). Spec: [`ADR-0032`](decisions/ADR-0032-workbench-reference-material-fetch.md) [Amendment 1](decisions/ADR-0032-workbench-reference-material-fetch.md#amendment-1--the-scoping-pass-gated-capture-moves-into-the-in-app-browser-and-the-extract-becomes-synced-content-2026-07-25) S2. **No schema, no app-target change** — nothing added to the prod-promotion list; S1's `workbenchReferences` table is already on it. Verified at the review head by the architect, not taken on report: `scripts/check-drift.sh` clean at **462 tests / 91 suites** (455 → 457 → 462), plus two throwaway probe tests. **No device pass — S2 adds no UI.**

**The shipped work.** `WorkbenchDetailData` carries the workbench's references, so `WorkbenchChatContext(detail:)` — the app layer's single construction site — picks them up **without the app target changing at all**, which is what kept the slice package-verifiable by construction. One serializer feeds all three surfaces (the onboard chat's system prompt and both ADR-0042 outboard handoff prompts), references are deduped against candidate sources by tracking-stripped URL, and an extract is included **whole or not at all** — S1's in-band truncation notice is never re-clipped. Fetched prose is framed as untrusted data in the task framing, in both handoff prompts, and in the section header the extracts sit under.

**The review's blocking find: the degradation ladder was upside-down on the tier that needs it.** The first commit ran two nested trim loops, one per tier — and the nesting was **transposed between them**. In a "render, measure, shrink, retry" search the **inner** loop is the dimension that sheds first, so the on-device branch walked *every* candidate count down to zero while holding all references, then started dropping references. ADR-0032 OQ3 says the exact opposite: references are supplementary, candidates stay primary, references trim out first under the 9k budget. A probe with a 2.1k-char reference and three candidates overflowing by ~500 characters showed the reference surviving and a **whole candidate recipe** being dropped — with a budget note cheerfully reporting that references had been "omitted before candidate recipes."

**The fix was deleting the special case, not adding one.** Frontier "keeps complete extracts" is not a *different* policy from on-device "sheds references first" — it is the **same** policy under a budget that rarely binds. One loop (candidates outer, references inner) now serves both tiers, and the branch that existed to distinguish them is gone. Re-probed at the fix: reference dropped, all three candidates intact, note accurate.

**Generalizable, and worth the same weight as S1's reducer lesson: a nested budget search encodes its priority in the loop *nesting*, where it is invisible.** Two loops that differ only by which `for` is outermost read as symmetric boilerplate, and the one that was wrong was the one whose behavior nobody can observe without running it. Nothing in the diff *looked* like a priority decision.

**And the test that should have caught it asserted the ordering it could not observe.** `…TrimsThemBeforeCandidatesOnDevice` passed under the inverted loop: its single reference was itself larger than the whole on-device budget, so `(1 ref, 0 candidates)` also overflowed and the search reached the right answer **by elimination**, not by priority. A degenerate fixture makes a discriminating name a lie. The added regression test uses a reference that comfortably fits *alongside some* candidates, which is the only shape where the two orderings differ. Continuing S1's method note: **both defects were confirmed by a throwaway test that printed the actual inclusion set and was then deleted** — the second time on this ADR that running the code beat reading it.

**A search that renders to measure must not render what is already disqualified.** Each grid cell rebuilt the entire context string including every included extract, and `seededContextDescription` runs that search **inside a SwiftUI body** (`RecipeChatPanelSupport.swift:69`). With three 200k-char extracts — individually 22× the on-device budget, so never includable at any count — the debug-build measurement was **178 ms per body evaluation**; pre-filtering references whose extract alone exceeds the budget took it to **1 ms** (4 × 30k: 46 ms → 0 ms). The remaining cost is bounded by the budget rather than by S1's 256 KB storage cap, which is the right shape.

**Dedupe scope, and why the corrected order made the fix complete.** Eligibility was computed against *all* candidates, including ones the soft cap or the budget would never serialize — so a reference could be dropped as "duplicate evidence" of a candidate that isn't in the prompt, losing the source entirely. It now compares against the capped list. Under the corrected trim order the remaining exposure is nil: references are all shed *before* candidate trimming ever begins, so the soft cap was the only way a reference could outlive its twin.

**Carry-forwards for S3 (not blocking, both recorded in Ready Efforts).** S1 caps an extract at **256,000 UTF-8 bytes** while the frontier serialization budget is **160,000 characters**, so an extract between the two is fetched, reduced, stored, synced and listed — and can never reach any model at any tier; a 3 × 200k probe produced a 12,970-char handoff prompt with all three references silently absent except for a budget note that reads like a *transient* trim. And `WorkbenchDetailRequest` now hauls full extracts on the always-on `@Fetch` behind the workbench screen (`WorkbenchModels.swift:167`) — the ADR-0029 Finding 8 shape ([[sqlitedata-fetch-writer-convoy]]), acceptable here because it is scoped to one workbench with a handful of rows, worth revisiting if S3's list needs only labels and status.

**One nit not taken:** the untrusted-data sentence is emitted even when the workbench has zero references, spending on-device system-prompt room on nothing.

---
## App-layer polish — the four sheets get a `Done`, and the Dispatch 3 punch list

**✅ Architect-approved 2026-07-26; device pass owed.** PR [#240](https://github.com/jonphillips/yes-chef/pull/240), branch `codex/app-layer-polish`, commits `9a9e486` → `8dcffa9` (one review round). **App layer plus a small Core move; no schema**, nothing added to the prod-promotion list. Spec: [`efforts/chat-surface-contract.md`](efforts/chat-surface-contract.md) S1 plus the seven items deferred from PR [#238](https://github.com/jonphillips/yes-chef/pull/238)'s device pass. Verified at the review head: elevated `generic/platform=iOS` build `** BUILD SUCCEEDED **` (no new warnings), `scripts/check-drift.sh` clean at **457 tests / 91 suites**, `xcodegen generate` zero drift — all three re-run by the architect, not taken on report. **Jon's device pass still owes** the four `Done` controls, the Add-a-learning card, and the duplicate-learning close.

**S1 — four sheets that were swipe-only on iPhone now have a labelled dismiss.** Calendar, Calendar-day, Workbench and Compare each pass an `onDismiss` that clears the `item:` binding driving their own sheet, so the panel's existing `Done` at `.topBarLeading` renders. **No new control was invented** — the modal contract already existed in `RecipeChatPanel` and Recipe already used it; these four call sites had simply never opted in. The one remaining call site without `onDismiss` is `ChatWorkspaceSplit`'s resizable column, which is exactly what the parameter's documented `nil` means.

**This is the first repayment on the effort's thesis, and it is worth restating once: a defaulted parameter is a decision made by whoever *doesn't* type it.** Four surfaces shipped with no dismiss control because `onDismiss: (() -> Void)?` defaults to `nil` and nobody said otherwise. S2–S4 (the `ChatSurface` descriptor that removes the defaults) stay queued; S1 was always shippable alone and was.

**The punch list, in one commit.** The Add-a-learning form moved above the list/empty-state branch, gained the app's attention-card treatment, suppressed the empty state while composing, and focuses its field on open. `WorkbenchCompletedSearch` left the previously SwiftUI-free `WorkbenchModels.swift`, taking its `import SwiftUI` with it, and its `.searchable` placement now matches the file's other two call sites. The workbench delete alert names the retained working recipe. Notes normalize on blur rather than mid-typing.

**The attention-card extraction, and the sharp edge in it.** Four drifted copies of `padding / maxWidth / .tint.opacity(0.10)` became one `attentionCard()` modifier. Folding `RecipeDetailView`'s variation note in changed it from `padding(12)` with no frame to the shared 10-point full-width treatment — a **known, intended** divergence the dispatch called out in advance. The first commit's doc comment nonetheless claimed the modifier "preserve[d] the values already used by the four pre-existing implementations," and the review caught it: **extracting a shared treatment is only safe if the extraction says which call site's appearance is changing.** The risk was never the 12 → 10 move; it was a comment that would teach the next reader there was nothing to check.

**A `Bool` that meant three things made a dead tap into a loop.** `createLearning` returned `false` for both "already saved" and "the write failed," so the duplicate path was silent and the tap read as broken. Giving it a toast fixed the silence and created a worse bug: the form stayed open holding text that was already saved, so tapping Add again produced the same green checkmark indefinitely. The cure is `LearningCreationResult { added, duplicate, failed }` — **a duplicate is a terminal success** (the cook's intent is already satisfied, so clear and close), while only `.failed` keeps the form open with the text intact. Related, unfixed and not queued: `AppToastCenter.Style` has exactly one case, so "already saved" ships with a success checkmark and a success-styled accessibility announcement.

**The generalizable find, and the reason a Core move rode a UI-polish PR: a test in a target that nothing runs is not a test.** The first commit put a deletion-copy assertion in `YesChefAppTests`, which is compiled and executed by **nothing** — not `scripts/check-drift.sh` (it ends in `swift test --package-path YesChefPackage`), not CI (the same command), and not the generic app build (`build` never compiles the test target). A `build-for-testing` probe dies at a CloudSyncKit dynamic-product link error before it reaches the target, so the seven files already sitting there are not even known to compile. **This is the standing "keep pure logic out of the App layer" corollary arriving from the other direction:** if a thing is pure enough to unit-test, it is pure enough to live in Core, and putting it there is what makes the test real. `MenuDeletionContext`, `WorkbenchDeletionContext`, `deleteMenuMessage` and `deleteWorkbenchMessage` moved to `YesChefCore/DeletionCopy.swift` — all four are pure values and strings over Core ID types with no SwiftUI — and the test moved to `YesChefCoreTests` covering all three workbench branches and six menu cases. Test count went 455 → 457 because those two now actually execute. **The warning went into CURRENT_HANDOFF's Verification Pattern**, where it is read before someone writes the next app-target test. The review then went looking at what was already stranded there: **23 tests, of which only 4 are stranded by the target** — the other 19 are stranded by pure logic sitting in `YesChefApp/`, recoverable by moving five files/types to Core with no cross-repo work. Scoped as [`efforts/app-target-tests-to-core.md`](efforts/app-target-tests-to-core.md). The target itself is genuinely broken, confirmed against cleared DerivedData: `CloudSyncKitdynamic-product` cannot link `SwiftUICore` ("not an allowed client of it") because a test bundle forces SwiftPM to emit dynamic products, so fixing it is a linkage change in `jon-platform`, deliberately not taken for four tests.

**Two accepted nits, neither queued:** `DeletionCopy.swift` exposes two public free functions at module scope rather than a namespace enum in the `WorkbenchInlineEditor` mould, and the singular `candidateCount: 1` branch is the one still untested — which is also the one whose copy reads oddly ("its 1 candidate? **The recipes** stay in your library") when no working recipe exists.

---
## ADR-0032 S1 — the workbench reference-material model + reduce/store core

**✅ Approved, 2026-07-26.** PR [#239](https://github.com/jonphillips/yes-chef/pull/239), branch `codex/adr-0032-reference-material-core`, final commit `fb2c260` (amended across four review rounds: `2e34a8c` → `5125a71` → `6fb3931` → `fb2c260`). Spec: [`ADR-0032`](decisions/ADR-0032-workbench-reference-material-fetch.md) [Amendment 1](decisions/ADR-0032-workbench-reference-material-fetch.md#amendment-1--the-scoping-pass-gated-capture-moves-into-the-in-app-browser-and-the-extract-becomes-synced-content-2026-07-25) S1. Verified: `swift build` + `scripts/check-drift.sh`; the architect ran the full package suite on the final head (**455 tests, green**) plus a throwaway probe test against the reducer. **No device pass — S1 adds no UI.**

**Schema: one table, and it IS synced.** `workbenchReferences` (id, `workbenchID` → `workbenches` `ON DELETE CASCADE`, `sourceURL`, `label`, `captureKind`, `reducedText`, `reductionStatus`, dates) was added by migration ([`Schema.swift`](../YesChefPackage/Sources/YesChefCore/Schema.swift)), registered in [`CloudSync`](../YesChefPackage/Sources/YesChefCore/CloudSync.swift), and **went onto the prod-promotion list in this same PR**. Exactly one real FK ([[sqlitedata-single-fk-sync-limit]]); additive, so existing stores migrate without data changes.

**The shipped work.** A synced `WorkbenchReference` model; one deterministic generic-readability reducer serving **both** acquisition paths (a public URL through `WebRecipeCaptureClient.fetchHTML`, with the established `renderHTML` fallback when the raw DOM comes back empty or thin, and already-captured authenticated HTML from what will be S3's in-app browser); and store / refresh / read / delete with duplicate-URL detection. Raw HTML stays transient — only the reduced text persists, per OQ2.

**The whole review turned on one fact: this extract is durable, synced, and *not recomputable*.** OQ2 moved it from cache to captured content precisely because device B cannot re-fetch a gated page. Raw HTML is discarded, so whatever the reducer emits is final — which makes the *grain* of the reduction a schema-grade decision, not a formatting preference ([[editable-at-the-grain-stored]]). Three successive versions of the reducer failed it in three different ways, and each was caught by running the code rather than reading it:

- **v1 flattened everything.** `contentRoot.text()` collapsed heading, prose, and list items into one unbroken line — fine for the recipe parser's 1500-char fallback excerpt it was copied from, wrong for content that *is* the payload.
- **v2 selected blocks instead — and double-counted them.** `select("h1…h6, p, li, blockquote, pre")` returns all matching *descendants*, so `<li><p>…</p></li>` and `<blockquote><p>…</p></blockquote>` each emitted their text twice. Worse, the "no blocks matched" fallback was all-or-nothing, so a page whose prose sat in bare `<div>`s but which had a single `<h2>` returned **just the heading** — the article silently discarded.
- **v3 fixed both, then gated on exact equality** between the joined blocks and the root text. One byline `<div>` or `<figcaption>` — i.e. any real page — failed the equality check and fell back to the flat dump. The suite passed because the fixtures were synthetic: `referenceHTML` reduces to exactly one `<h1>` and one `<p>` once the cookie div is stripped.
- **v4 walks the tree.** Recursive descent: recurse into elements that contain block-level descendants, emit normalized text from the ones that don't, emit text nodes directly. The byline becomes its own block instead of disqualifying the page. Lossless *and* structured; the two remaining flat cases (a table's cells, a div tree with no block tags anywhere) are the right call.

**Generalizable: a `select`-based extractor double-counts nested blocks, and an all-or-nothing coverage gate silently flattens or drops real pages. Walk the tree instead of selecting against it.**

**"Dedupe" on synced content means detection, never a destructive sweep.** A review nit asking for duplicate *prevention* produced, in the next round, three overlapping mechanisms: `store` silently overwrote a matching-URL row (so a later public fetch of a login-walled page could replace an authenticated extract with its teaser), a helper hard-**deleted** duplicate rows, and `references(for:)` filtered duplicates at read time — making rows that exist in the database invisible and therefore undeletable. Two devices adding the same URL offline is a normal merge, not corruption to repair, and a unique index isn't available on a synced table anyway. It now throws `duplicateSourceURL(existingID)` and touches nothing; S3 decides the UX.

**The cap is loud, because a silent one would be the same mistake.** `reducedText` is the first synced column in the schema holding arbitrary whole-page text, and a TEXT column does not become a CKAsset the way a BLOB does ([[sqlitedata-blob-cloudkit-asset]]), so CloudKit's ~1 MB non-asset record ceiling is a hard wall. Capped at 256 KB measured in **UTF-8 bytes** (so compound Unicode can't evade it), cut on a word boundary, with both an in-band truncation notice and a `reductionStatus` column — visible in the data *and* in the payload ([[editable-at-the-grain-stored]]).

**Method note worth keeping.** Every reducer defect above was confirmed by adding a temporary test that printed the reducer's output for a handful of realistic page shapes, running it, and deleting it — a few minutes each time, and it caught two defects that four rounds of careful reading had endorsed. When a fix's correctness depends on a *library's* traversal semantics, print the output.

**Carry-forwards (not blocking, folded into S2/S3):** `removeLinkDenseBlocks` is still a verbatim fork of `WebRecipePageParser`'s — one shared generic-readability helper, plus a `SEAM-LEDGER` row, since Galavant carries the same shape; `<main>`-vs-`body` root selection and the not-found error paths are untested; the `1_500` thin threshold is a guess until real pages run through it. S3's refresh constraint (never silently replace an authenticated capture with a public fetch) was written into the ADR's slice plan by the executor and ratified by the architect — noted because `docs/decisions/` is architect-owned, and the round-3 review asking for the constraint is what invited the edit.

---
## Dogfood ferry Dispatch 3 — workbench lifecycle and hand-authored learnings

**✅ Approved, 2026-07-26.** PR [#238](https://github.com/jonphillips/yes-chef/pull/238), branch `codex/dogfood-ferry-dispatch-3`, commits `6356ac6` / `04bc18d` / `3b1e1e8`. Spec: [`efforts/dogfood-ferry-2026-07-25.md`](efforts/dogfood-ferry-2026-07-25.md) Dispatch 3 (E1–E3 + H). Verified: package `swift build` + elevated `generic/platform=iOS` build + `scripts/check-drift.sh` (445 tests); Jon's device pass — good overall, one finding, deferred (below). **This closes the 2026-07-25 ferry track: 1 → 1.5 → 2 → 3, all shipped.**

**Schema: one column, and it IS synced — the mirror image of Dispatch 2.** `workbenches.dateCompleted TEXT` (nullable) was added by migration ([`Schema.swift`](../YesChefPackage/Sources/YesChefCore/Schema.swift)), and **`Workbench` *is* registered in `CloudSync`** — verified against the registration list — so it **went onto the prod-promotion list** in this same PR. Dispatch 2's `aiHandoffs.dayOffset` looked synced and was not; this one is. The check is the registration list, both directions.

**The shipped work.** Workbench title/notes retired their Save buttons for debounced commit-on-blur; an Active/Completed segmented lifecycle with search over Completed and swipe-to-complete; completed workbenches drop out of the recipe detail's candidate links and the App Intents picker while staying searchable and fully readable when opened; the delete confirmation stopped implying it deletes recipes. Slice H gave `LearningProvenance.inApp` its first producer anywhere in the codebase — the case had been orphaned since ADR-0038, so there was no way to write a learning by hand — plus a hand-authored row marker and menu learnings wired into `MenuChatContext`'s outbound ask, which they had never reached.

**The review's one blocking find was a debounce that fought the cook's cursor.** `commitTitle()` assigned to `titleText` on *every* 350 ms tick, so the trimmed value was written back into the live field mid-typing: type `Braised`, press space, pause, and the space vanished under the cursor — continue and you get `BraisedChicken`. Clearing the field to retype refilled it with the old title after 350 ms. The same write-back arrived a second way, through the `@Fetch` echo assigning into the focused field. **The fix is a distinction, not a patch: reverting-on-empty is a *blur* policy and persisting is a *debounce* policy, and collapsing them is what broke it.** `persistTitleDraft` now never touches the field (a nil from `titleToPersist` just returns), `commitTitleOnBlur` owns the revert, and both echoes are focus-guarded. The E1 spec's guard — "revert rather than alert on empty" — had been read as *when* to revert; it was only ever about *what not to do* on empty.

**Two design finds worth keeping.** The list had grown **two** always-on whole-library `@Fetch`es (active + completed), each doing a full `Workbench` *and* `WorkbenchCandidate` scan re-run synchronously on the writer — the exact ADR-0029 Finding 8 shape ([[sqlitedata-fetch-writer-convoy]]), doubled, for nothing. Collapsed to one request returning both partitions from one pair of scans. And menu learnings were appended *outside* the budget degradation ladder, so a long-enough list could push the serialized context past the on-device budget with no path to shrink it; they are now the last thing dropped, after every dish, with a budget note — the right priority for an observation whose entire purpose is surviving to the next planning session.

**The device pass found the affordance, not the logic.** The Add-a-learning form rendered as the *last* child of the section stack, so on an empty menu it appeared below a full-height `ContentUnavailableView` — a screen away from the button that summoned it — and with no container at all, white on white. Deferred by Jon's call, along with six review nits, to ride the next slice.

**A drifted shape got noticed on the way out.** Fixing that form wants the app's attention-card treatment, which turns out to already exist **four times** (`RecipeAdjustmentReviewView` ~204, `RecipeChatWorkspace` ~958, `RecipeCollectionReviewSheet` ~222, `RecipeDetailView` ~788) and to have **already diverged** — the last uses `padding(12)` and no `frame`. The deferred bundle extracts one named modifier and folds all four in rather than pasting a fifth copy, which is the same cure Dispatch 1 applied to the expand control. Noticed at the only moment it was cheap.

**Process note, recorded because it cost a round.** Codex authors as `jonphillips`, so `gh pr review --approve` *and* `--request-changes` are both rejected as acting on one's own PR. The "native PR state is the handoff signal" half of `agent-collaboration.md` cannot work in this setup; verdicts go via `gh pr comment` with the verdict stated in the body.

---
## Dogfood ferry Dispatch 2 — hand-off regrouping, day-scoped asks, and the vocabulary cleanup

**✅ Approved, 2026-07-26.** PR [#237](https://github.com/jonphillips/yes-chef/pull/237), branch `codex/dogfood-ferry-dispatch-2`, commits `9abd0f5` / `04a7ae6` / `b055a17` / `e839f38`. Spec: [`efforts/dogfood-ferry-2026-07-25.md`](efforts/dogfood-ferry-2026-07-25.md) Dispatch 2 (D1–D3 + the renames). Verified: elevated `generic/platform=iOS` build + `scripts/check-drift.sh` (441 tests); Jon's device pass on `iPad Pro 13-inch (M5)` and `iPhone 17 Pro`.

**Schema: one column, and it is LOCAL.** `aiHandoffs.dayOffset INTEGER` was added by migration ([`Schema.swift`](../YesChefPackage/Sources/YesChefCore/Schema.swift)). **`AIHandoff` is not registered in `CloudSync`** — verified against the registration list — so **nothing was added to the prod-promotion list.** Same trap as Dispatch 1.5's `chatMessages.resolvedTier`: check the registration, do not assume from the name.

**The shipped work.** Each Menu day header and each Calendar day / week cell gained a `⋯` carrying its four hand-off items scoped to *that* day; the Prep Plan's button row collapsed into a plan-level `⋯` and **Clear Prep Plan finally asks first**; the recipe-side "Prep Plan" vocabulary became "Make-ahead" with the Finalize action-id resolution pinned by test. This discharges the PR [#226](https://github.com/jonphillips/yes-chef/pull/226) device-pass concern about two Copy + two Paste buttons on the Prep Plan disclosure and four on the meal-plan day header.

**Jon's device pass found the defect that mattered: a day-scoped prep ask silently deleted the other days.** Prep for Day 2, then prep for Day 1, and Day 1's return wiped Day 2. The dispatch had built the scoped *ask* and skipped the **woven return** its own acceptance criterion required. Root cause was one prompt string: `dayScopeInstruction` told the model *"Keep every proposed task or complement on Day N; do not plan for another day,"* while [ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md) D3's contract is that the return **replaces the whole plan**. A partial plan in, a truncated plan stored. Notably the merge machinery was already correct and untouched — `scoped(toDayOffset:)` filters only `items` and deliberately leaves the full `prepPlan` in the prompt — so the fix was to split the instruction (prep returns the whole menu's plan and preserves other days verbatim; complement keeps its stay-on-this-day rule), move both strings into Core where the package build can test them, and narrow `dayCount`. **The dispatch never needed a schema change; it needed the prompt it already implied.**

**Day scope also had to enter the hand-off identity.** `.menuDay` / `.menuDayComplement` produced metadata byte-identical to their whole-menu siblings, so `matches` could not tell them apart: a Day 2 complement pasted into Day 1's door matched, and `applyingScope` silently re-pinned every suggestion to Day 1. With an identical `⋯` on every day header that misfire was one row away. The local `dayOffset` column plus a `matches` comparison routes a mismatch into the existing unmatched-result confirmation instead.

**The review's own error, recorded because the recovery is the lesson.** The architect diagnosed the text round trip's loss of `sourceDish` (and of row identity) as a pre-existing bug and specified a fix: match on `(session, task, serves)` and inherit the link from the matched row. Codex implemented it exactly. It was **wrong** — [ADR-0040](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) D3's corollary says *"hidden state must not be re-derived from text… the link must ride on the row's identity, not on its prose surviving unedited,"* and its Consequences accept the cost by name. The guard test, `textImportReplacesSourceDishLinksInsteadOfMatchingThemByTaskText`, had been added during the ADR-0040 review round and was renamed and inverted to make the change pass. Round 3 reverted the merge key and restored the test to its original blob. **The tell was in the test's name, and the review did not read it before calling the behavior a bug.**

**What survived that reversal is the better half.** Omitted-step evidence had been appended to `unparsedLines` — a strict-failure channel that is concatenated into the *editable* review text and re-parsed on commit, so the advisory itself threw and **no menu with a dish-linked step could save a prep-plan return at all**. It also false-positived on every linked step, because the parse can never produce a `sourceDish` to compare. Evidence now lives in its own `advisoryNotes` field: rows only, never the editable text, never blocking a commit. The comparison key was renamed `PrepPlanStepVisibleContent` with a comment stating why it and the merge key **must** differ — the merge key asks *"is this the same row?"* and includes `sourceDish`; the advisory asks *"did a step I can see disappear?"* and deliberately ignores it. The review had originally told Codex to unify them so they could not drift, which was backwards.

**And the loss became loud.** A step whose text returns verbatim but whose link does not now produces *"Kept the step but dropped its recipe link (pasted plans can't carry links)."* That is ADR-0040 D3's "lossless or loud" applied to the exact case D3 named — the link cannot ride the wire (the prompt forbids menu item IDs; [ADR-0042](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) Amd 1's *"the paste door never carries identity"* closes the machine-section workaround), so the only honest option is to say so.

**The lesson, since it cost three review rounds:** a behavior with a test whose *name asserts it is deliberate* is a decision until proven otherwise. Read the name, then the ADR, then call it a bug.

**One effort spun out of the review and the device pass:** [`efforts/prep-plan-dish-links-and-dates.md`](efforts/prep-plan-dish-links-and-dates.md) — the prep plan knows two things the model never sees (`sourceDish`, and the menu's placement dates), and ADR-0034 designed for the version where it does. In Ready Efforts.

---
## Dogfood ferry Dispatch 1.5 — the embedded chat panel owns its chrome, and the panel header settles

**✅ Approved, 2026-07-26.** Two PRs: [#234](https://github.com/jonphillips/yes-chef/pull/234) (G1–G4, branch `codex/dogfood-ferry-dispatch-1-5`, commits `4d89999` / `9866c7f` / `051a1bc`) and [#235](https://github.com/jonphillips/yes-chef/pull/235) (G5 + the architect review + the device-pass follow-ons, branch `codex/dogfood-ferry-dispatch-1-5-g5`, commits `0253f5e` / `b202b72`). Spec: [`efforts/dogfood-ferry-2026-07-25.md`](efforts/dogfood-ferry-2026-07-25.md) Dispatch 1.5 (G1–G5) + [ADR-0045 Amendment 3](decisions/ADR-0045-onboard-path-stays-viable.md#amendment-3--ask-opens-the-panel-the-launcher-stops-picking-sections-2026-07-26) and [its codicil](decisions/ADR-0045-onboard-path-stays-viable.md#codicil-to-amendment-3--the-embedded-panel-header-contract-2026-07-26). Verified: elevated `generic/platform=iOS` build + `scripts/check-drift.sh` (SwiftLint clean, 433 tests); Jon's device pass on `iPad Pro 13-inch (M5)` and `iPhone 17 Pro`.

**Schema: one column, and it is LOCAL.** `chatMessages.resolvedTier` was added by migration ([`Schema.swift`](../YesChefPackage/Sources/YesChefCore/Schema.swift)). **`chatMessages` is not registered in `CloudSync`** — the chat transcript is device-local scratch, pruned on a cutoff — so **nothing was added to the prod-promotion list.** Verify before assuming otherwise; this is the one table in the chat stack that looks synced and isn't.

**The panel stopped renting the host's toolbar.** `showsEmbeddedHeader` existed but only `ChatWorkspaceSplit` passed it, so the Recipe's `.inspector` and the Menu's overlay rendered *modal* chrome in a *non-modal* position and SwiftUI merged their Clear / tier / `Done` into the **host's** navigation bar. G1 fixed the Recipe (the reference treatment), G2 ported the one flag to the Menu, and G3 hoisted the Calendar's chat to `MealCalendarWorkspaceView` so it is a column in month/week and not only day mode.

**Ask became a launcher, then a toggle.** G4 retired the section `Menu` on the recipe playbook's Ask — a cook can now open the panel and just type, instead of faking a scoped ask to reach a free-form question. Its binding condition shipped with it (an empty state, and a stated reason on the greyed apply-verbs), because *"the panel opens empty and looks broken"* is the exact defect ADR-0045 V1 over-corrected for. G5 then made the lit Ask close the panel; the transcript survives, because threads persist per subject and `loadPersistedThread` restores them.

**G5 settled the header to `Discuss ▾ · title ……… ⋯ · ✕`** — one primary, one overflow, one dismiss, on the header every surface shares. Clear Chat and the tier picker moved into the `⋯` (a destructive control must not sit one target from a dismiss, confirmation dialog or no), and the two separate explanations of an empty panel folded into one.

**The architect review of #235 drove six in-PR fixes.** The empty state's folded-in Apply sentence had lost its guard and was **false on the Recipe surface** — `adjustRecipe` and `captureNote` are `requiresSubject: false`, so the Apply menu is *enabled* on an empty recipe panel while the copy said it needed a reply; the gate is now passed in, which also rescued `applyActionsNeedReply` from becoming dead code. The empty state was also naming a **Discuss** control that exists on one surface out of four (`selectSection` is wired only from `RecipeDetailView`), so its clauses are now composed per-surface and collapse to no description at all when neither applies. The tier accessibility hint had been dropped rather than moved. Plus the `✕` gained leading padding, the `⋯` took the retired chip's tint, and a vestigial `@Bindable` went.

**Then the device pass found the two defects that mattered most, and both shipped in the same PR.**
- **The tier checkmarks could never render.** A SwiftUI `Menu` maps a `Button` label to **one** title and **one** image; the rows were passing a `Label` *plus* a trailing conditional `Image(systemName: "checkmark")`, and the second view was silently discarded. This had never worked — it predated G5 — and was masked the whole time by the header tier chip, which stated the active tier in words. **G5 retired the chip, and a broken indicator became the only indicator.** Fixed by putting selection in the image slot (the only one that renders) and adding a `Section` header naming the resolved tier in text.
- **A mid-thread provider switch produced a reply claiming the previous provider.** The routing was never wrong — `selectedProvider.didSet` clears the continuation token, and `completeSend` re-resolves the tier fresh every send — and Jon confirmed against the ADR-0043 call records that the traffic really went to Anthropic. The cause is that `history()` replays the whole transcript, so the new model reads the previous provider's turns as its own words and continues that persona. Two fixes, because neither suffices alone: the system prompt gained the sibling of its existing *"never claim to have edited or saved anything"* guardrail (**never claim to be a particular model, product, company, or provider**), and assistant turns now **record and display the tier that actually produced them** (`RecipeChatMessage.resolvedTier`, populated from the already-resolved `resolvedTier` in `completeSend`, rendered as a quiet footnote on the bubble). Pre-provenance rows render nothing rather than guessing.

**The lesson, stated once because it recurred three times in one review:** the app kept *knowing* which model was in play and *not saying so* — the chip knew and was retired, the checkmarks couldn't render, and `ModelCallRecord` had the per-call truth while `RecipeChatMessage` carried only `id / role / text`. **Per-turn attribution is strictly better than any header indicator here**, because a thread can legitimately contain turns from several providers — which is exactly the case that produced the confusion. A header can only ever describe *now*.

**Two carry-forwards, both non-blocking, neither queued:**
- The restored tier accessibility hint still reads *"Choose whether **recipe** context stays on device…"* on a control that renders on all four surfaces, so Menu / Calendar / Workbench announce a recipe that isn't there. Same defect class the visible copy fix closed, one layer down.
- `RecipeChatMessageTier.init(resolvedTier:)` maps `.frontierPreferred` → `.onDevice`. **Unreachable today** — `resolveTier` returns only `.onDevice` or `.frontier(provider)` ([`ModelTierResolution.swift:34`](../YesChefPackage/Sources/YesChefCore/ModelTierResolution.swift)) — but the initializer is `public`, so a future caller passing `.frontierPreferred` would be labeled *On-device* on a badge whose entire purpose is being truthful about where data went.

**One effort spun out of the review:** [`efforts/chat-surface-contract.md`](efforts/chat-surface-contract.md) — the panel *view* is shared but its *contract* is not (eight call sites, eight parameters, six defaulted), which is why four sheets silently shipped with no dismiss control at all and three surfaces inherited Recipe's copy. In Ready Efforts; **does not jump the ferry queue**.

---
## Dogfood ferry Dispatch 1 — one expand control, four surfaces, and the Menu's onboard column

**✅ Approved with follow-ups, 2026-07-26.** PR [#233](https://github.com/jonphillips/yes-chef/pull/233), branch `codex/dogfood-ferry-dispatch-1`, commit `12a6612`. **App layer only — no Core, no schema**, nothing added to the prod-promotion list. Spec: [`efforts/dogfood-ferry-2026-07-25.md`](efforts/dogfood-ferry-2026-07-25.md) Dispatch 1 (Slices A / B / C / F1). Verified: elevated `generic/platform=iOS` build + `scripts/check-drift.sh`; Jon's device pass on `iPad Pro 13-inch (M5)` and `iPhone 17 Pro`.

**Four independent copies of one interaction became one.** `FocusToolbarButton` is now the single definition of the full-screen expand control — glyph, tint, label, accessibility value — and Recipe (already correct), Menu, Workbench and Calendar all adopt it at `.topBarLeading`. The Calendar had none: its `NavigationSplitView` branch gained a `columnVisibility` binding so the control has something to collapse. **The point of extracting it was to stop a fifth copy appearing**, and it is the control [ADR-0046](decisions/ADR-0046-sidebar-adaptable-app-shell.md) is gated behind.

**The Menu's onboard column echoes the Recipe's.** Ask moved out of the toolbar and is now pinned at the top of the playbook column as a section-picking `Menu` (Prep Plan · Complement · **Regenerate whole plan**), which retired the standalone Regenerate button inside the Prep Plan section. The column gained the Recipe's `@AppStorage`-backed show/hide toggle, and [ADR-0039](decisions/ADR-0039-playbook-column-thinking-vs-doing.md)'s recorded two-trailing-sidebar-icons collision was resolved by moving Browse Recipes to `book.closed`. Recipe's Edit is now last in the trailing group, which required hoisting the playbook toggle out of `RecipeReaderView`'s own toolbar (with its width gate) since toolbar order follows view-hierarchy order.

**The device pass found a defect class Dispatch 1 exposed rather than caused, and it became Dispatch 1.5.** `RecipeChatPanel` has a `showsEmbeddedHeader` flag for panels that own their own chrome, and **only `ChatWorkspaceSplit` passes it** — the Recipe's `.inspector` and the Menu's trailing overlay both render *modal* chrome in a *non-modal* position, so SwiftUI merges their Clear, tier menu and `Done` into the **host's** navigation bar. Dispatch 1 made this visible on the Menu by moving Ask under the overlay's fixed 380pt footprint, and Jon hit it on the Recipe only because he had been exercising Ask on iPhone, which takes the correct `.sheet` path. **Two scoping errors were the architect's, not Codex's:** Slice C pinned Ask inside a column the same slice made hideable (hide it and there is no Ask at all), and **Slice F1's premise was simply wrong** — it described the Calendar as `ChatWorkspaceSplit`, true of one of three `MealCalendarDayAgendaView` call sites; the other two pass `allowsChatWorkspace: false` because they sit inside a `ScrollView`, so the split is reachable only in day mode and month/week fall to a sheet. F1's toggle fix was implemented correctly against a spec that could not be satisfied from where Jon was standing. All of it is spec'd as **Dispatch 1.5** (G1 → G2 → G3), which is Next Up.

## Learnings parser floor — a loud remainder for non-bullet learnings

**✅ Verified & approved (merged), 2026-07-25.** Merged as PR [#232](https://github.com/jonphillips/yes-chef/pull/232), branch `codex/learnings-parser-floor`, commit `70f2101`. Core logic + the App-layer callers that thread it; **no schema**, nothing added to the prod-promotion list. Spec: the CURRENT_HANDOFF "learnings parser floor" effort — [ADR-0040](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md)'s lossless-or-loud floor, ahead of ADR-0038 Amd 4's curation *ceiling* ([[handoff-stateless-both-directions]]).

**The defect it closes:** `AIHandoffReturn.learningBullets` kept only `- ` / `* ` / `• ` lines and **dropped every other line with no trace**, so a learning returned as a naked sentence or paragraph silently vanished. `learningBullets` now returns `LearningBulletsReturn { learnings, unparsedLines }` — mirroring `readerFeedbackReturn`, not a second convention — and skips empty lines *before* the bullet check so blanks are not false remainder. `plainText` became `PlainTextReturn` carrying the remainder; every caller updated (incl. the app-target `HandoffSectionRoutingTests`, which survived the tuple→struct change via property access). The remainder threads into each caller's **existing** loud surface: `menuPrepPlan` folds it into `MenuPrepPlanReturn.unparsedLines` (which previously carried only the *plan* parse's remainder, so a naked learning escaped even there); `mealPlanReview` stages it into the non-blocking `unparsedStrategyLines` evidence banner; `recipeReview` / `workbenchReview` / the in-app approve path throw `unparsed*` (those review models have no evidence field).

**Accepted asymmetry (architect call, carried forward as a possible follow-on):** loudness is not uniform — the recipe/workbench paths **throw** on a stray learning (blocking an otherwise-good deliverable) while the meal-plan path **stages** it as a non-blocking banner. Both satisfy lossless-or-loud, so the floor holds everywhere; the gentler "stage the remainder as evidence on the recipe/workbench paths too" is a small App-layer follow-on to revisit **only if** dogfooding shows the hard-fail is annoying. Verified at the PR head: **433 Core tests / 87 suites** (incl. two new remainder tests — naked sentence + paragraph land in the remainder; `menuPrepPlan` carries the unparsed learning into its existing evidence) + elevated `generic/platform=iOS` build `** BUILD SUCCEEDED **` (App-layer callers changed, so a package build alone was not sufficient evidence) + `scripts/check-drift.sh` clean.

## `Menu.prepPlan` retired — the dead CKAsset field never enters the prod schema

**✅ Approved (merged), 2026-07-25.** PR [#231](https://github.com/jonphillips/yes-chef/pull/231), branch `codex/prep-plan-blob-retirement`, commit `0d4ea54`. Core + one schema migration; **no app-UI change**. Spec: the CURRENT_HANDOFF "prep-plan BLOB retirement" effort — the tail of [ADR-0040](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) S2 ("keep it readable one release, then drop it"). *(Written retroactively on 2026-07-26 during a handoff cleanup: this PR merged without its DONE-LOG write, so the account below is reconstructed from the merged diff and the dispatching handoff, not from the approval itself — treat the verification record as unrecovered.)*

**Why it had to happen before the prod cut, not someday.** ADR-0040 S2 had already moved prep plans into `prepPlanSteps` rows (PR #184, device-passed), leaving `Menu.prepPlan` a frozen pre-migration snapshot with exactly one live reader — the 2026-07-14 historical migration that decoded it. But `Menu` is a **synced** record type and every BLOB syncs as a CKAsset unconditionally ([[sqlitedata-blob-cloudkit-asset]]), so the dead column was a **CKAsset field on the Menu record type**, and prod-schema promotion is additive-only and locks record types permanently (ADR-0040 D4). Dropping it was free that morning and impossible after the cut.

**The shipped work is one migration, one property, and one freeze.** A `DROP COLUMN "prepPlan"` migration ([`Schema.swift`](../YesChefPackage/Sources/YesChefCore/Schema.swift)) — a pattern already proven twice in that file (`substitution`, `legacyParentCategoryID`), so the SyncEngine-trigger interaction was a solved problem rather than a risk — plus the property's removal from `Menu` ([`Models.swift`](../YesChefPackage/Sources/YesChefCore/Models.swift)), which also retired the then-unreachable `MenuPrepPlanCoding.encode`. Lossless by construction: the data already lived in `prepPlanSteps`.

**The sharp edge, and the rule it leaves behind: historical migrations pin to SQL, not to the current model.** The 2026-07-14 migration read old data via `Menu.fetchAll(db)` → `menu.prepPlan`, so deleting the property would have stopped an *already-applied* migration from compiling. It was frozen first — the decode now selects the column through raw SQL into a private `LegacyMenuPrepPlanRow` `@Selection` — and only then was the property dropped, in the same PR. A migration that compiles against the live struct is a latent block on every future change to that struct.

**Guarded by a test rather than a comment.** `menuSchemaRetiresTheLegacyPrepPlanBlob` in `CloudSyncTests` reads `pragma_table_info('menus')` and asserts `prepPlan` is absent, so re-adding the column fails a test. **`Menu.prepPlan` left the standing prod-promotion list in this same PR** — it is dropped, never promoted; `prepPlanSteps` stays on the list.

## Dogfood cleanup batch — compact copy buttons, deterministic make-ahead order, and the seed chip

**✅ Approved (merged), 2026-07-25.** PR [#230](https://github.com/jonphillips/yes-chef/pull/230), branch `codex/dogfood-cleanup-batch`, commits `05061d1` → `32d100d` (review round) → `c65812d` (handoff). App + Core, three cohesive slices in one PR; **no schema**, nothing added to the prod-promotion list. Spec: the CURRENT_HANDOFF "cleanup batch" effort, Slices 1–3, with both design forks pre-decided by the architect. *(Written retroactively on 2026-07-26 during a handoff cleanup — reconstructed from the merged diff and the dispatching handoff, not from the approval; treat the verification record as unrecovered.)*

**Slice 1 — the menu prep-plan hand-off buttons stop being crushed on iPhone.** The two `HandoffCopyPasteControls` shared one `HStack` and wrapped to roughly one character per line at compact width. They now go through a `PrepPlanHandoffControls` wrapper that stacks vertically when `horizontalSizeClass == .compact` and keeps the iPad row unchanged. Pre-existing (ADR-0038/0039 era), app-only. *(Ferry Dispatch 2 later replaced these rows with overflow menus outright — PR [#237](https://github.com/jonphillips/yes-chef/pull/237).)*

**Slice 2 — a deposited make-ahead plan orders itself, deterministically.** `MakeAheadPlan.orderedForDeposit()` maps each step's `when` label onto a private `MakeAheadTimingRank` and stable-sorts earliest-available-effort → serving time, leaving unrecognized labels in their original relative order **at the tail**; `RecipeRepository` calls it on the deposit path. **The decision was explicitly a deterministic parse, not an LLM reorder** — curated content must not reshuffle on every regeneration ([[llm-vs-determinism-surface-boundary]]).

**Generalizable, and the whole content of the review round: the ranker and the prompt are one contract.** The first commit shipped a rank table whose vocabulary the prompt never asked the model to produce, which makes the tail-preserving fallback the *common* path instead of the escape hatch — a sorter that silently does nothing. The follow-up commit fixed both halves together: the rank gained `day before` / `N hours ahead` / `N minutes ahead`, and `MakeAheadPlanClient`'s instructions gained an explicit settled-label list (`Up to N days ahead`, `Day before`, `Night before`, `Morning of`, `Day of`, `N hours ahead`, `N minutes ahead`, `Before serving`). **When determinism downstream depends on a vocabulary, the prompt that produces it is part of the implementation.**

**Slice 3 — the auto-seeded section opener renders as a compact chip, in memory only.** `RecipeChatModel` carries a `seedSummaries` map keyed by the seed message id (`seedIfCold(_:summary:)` / `seedSummary(for:)`), and `ChatMessageBubble` renders it in place of the large machine-authored `discussAsk` text. **Deliberately not a synced column** — it is pure presentation and regenerable from the section, so it does not earn schema that locks at prod promotion ([[synced-table-cost-calibration]]). The full seed text still reaches the model, since `history()` builds from `text`; the map clears on `clear()` and on `loadPersistedThread()`, so a restored warm thread shows the full text — accepted, as scroll-to-bottom already lands on the reply.

## ADR-0045 V2 — Finalize onboard discussions

**✅ Verified & approved (device pass), 2026-07-24.** Merged as PR [#229](https://github.com/jonphillips/yes-chef/pull/229), branch `codex/adr-0045-v2-finalize`. App layer + a small Core seam; **no schema**. Spec: [ADR-0045](decisions/ADR-0045-onboard-path-stays-viable.md) V2 — OQ1/OQ2 answered empirically on the device pass.

**The onboard discussion can now be committed without the outboard round-trip.** A single deliverable-labelled **Finalize** control per seeded recipe section and the menu Prep Plan **replaces** its matching apply action (so the two do not read as competing doors — OQ1). On a frontier tier it sends the conversational `Finalize.` instruction and stages the terminal reply through the **same** `AIHandoffReviewStager.stage` parser and global review sheet as a pasted handoff — no second parser, no second prompt (`AIHandoffIntentImport.stageOnboardReview` / `HandoffReviewCoordinator.stageOnboardReview`, a read-only transient `AIHandoff` with no exported prompt or routing row). On-device it uses the existing strict extraction action, preserving the structured floor (OQ2). Finalize stays gated on a real assistant reply; `requiresSubject` unchanged.

**The architect review (2026-07-24) drove three in-PR fixes, all tested.** (1) A failed Finalize turn no longer stages the *previous* conversational reply as the deliverable — `send` returns true even on a swallowed model error, so the terminal-turn logic moved into a testable `OnboardChatFinalizer` that snapshots the prior assistant id and stages only a genuinely-new, non-empty, non-`(No response.)` reply, surfacing the error otherwise. (2) `RecipeEnrichment` (Chef It Up + Serve With) was folded into the truncation sweep — the same `2048 → 4096` + `wasTruncated` guard as the make-ahead trio, the one remaining high-effort strict-JSON client in the same risk class. (3) The stringly-typed Finalize→apply-action link is now guarded by an app-layer test asserting every `ChatFinalizeConfiguration.actionID` resolves in its real catalog, so a future rename fails a test instead of silently vanishing the button. Verified independently at the review head (`65dd29a`): elevated `generic/platform=iOS` build exit 0, `scripts/check-drift.sh` lint clean + **428 Core tests**. **This closes ADR-0045's V1+V2+V3 arc**; the meal-calendar / Workbench cold starts (OQ3) and V2's own make-ahead-ordering / seed-chip polish remain queued follow-ons.

## ADR-0045 V1 — the seeded, section-scoped Ask (onboard path stays viable)

**✅ Verified & approved (device pass), 2026-07-24.** Merged as PR [#227](https://github.com/jonphillips/yes-chef/pull/227), branch `codex/adr-0045-v1-seeded-section-ask`. App layer + a small Core seam (`RecipeChat.swift`, `AIHandoffContext.swift`); **no schema**, nothing added to the prod-promotion list. Spec: [ADR-0045](decisions/ADR-0045-onboard-path-stays-viable.md), **Accepted** with **Amendments 1 and 2**.

**The defect it closes:** tapping Ask produced an empty panel with every apply-verb grayed, so the cook concluded the feature was removed. V1 seeds each section's opener from the existing outboard `.discuss` ask and auto-sends it, so a reply exists and the verbs light up. **Amendment 1** — the onboard seed reuses the outboard prompt's *framing*, not its *payload*: an `AIHandoffPromptDestination` (`.outboard`/`.onboard`) gates only the subject block (the system prompt already carries it, tier-budgeted) and the transport sentence, and adds one onboard-only line so the opener discusses rather than dumps a deliverable. The outboard strings are provably untouched.

**The device pass drove three rounds of shaping, all in-PR.** (1) The panel opened scrolled to the top of the machine-authored opener — pinned to the bottom so it lands on the reply (`defaultScrollAnchor(.bottom)`). (2) The Serve With verb read as proactive — renamed **"Suggest Dishes" → "Capture Side Dishes"**. (3) **Amendment 2** — on iPhone the chat is a full-height modal sheet, so the playbook's per-section Ask menus are unreachable behind it and the Make-ahead → Serve With re-scope had no path. Unified section-picking into **one control in two placements**: an **Ask ▾** launcher on the playbook and the open panel's title as a **Discuss ▾** switcher, both routing through `RecipeDetailModel.askSection` (open-or-switch, never close), with an explicit **Done** dismiss. Per-section overflow Ask items removed. A follow-on found the recipe thread persists *per recipe* (warm on reopen), so `askSection` now delivers the picked section's opener via `send` into a warm thread rather than declining through `seedIfCold`. Verified: elevated `generic/platform=iOS` build exit 0, `scripts/check-drift.sh`, **412 tests**, and Jon's device pass. **V2 (Finalize button) is queued in CURRENT_HANDOFF; the meal-calendar and Workbench cold starts remain the OQ3 follow-on.**

## ADR-0043 S3 — tier-policy unification, with ADR-0045 V3 riding along

**✅ Verified & approved (device pass), 2026-07-24.** Merged as PR [#228](https://github.com/jonphillips/yes-chef/pull/228) (`codex/adr-0043-s3-policy-unification`), with its package half in `jon-platform` PR [#33](https://github.com/jonphillips/jon-platform/pull/33) (`codex/adr-0045-v3-frontier-model-override`, merged first). Core + app + `jon-platform`; **no schema** (model preference is UserDefaults). Spec: [ADR-0043](decisions/ADR-0043-model-call-chokepoint.md) S3.

**One shared `resolveTier()`** (`ModelTierResolution.swift`) now honors both `recipeChatProviderPreference` and `recipeChatTierPreference`, replacing three hand-rolled "preferred, else first available, else on-device" copies (`RecipeChatModel.activeTier`, `ReaderFeedbackCurationClient`, `HandoffReviewCoordinator.draftRecipeAdjustment`). Frontier-required work now throws `ModelTierResolutionError.frontierRequired` ("add an API key…") instead of silently degrading to on-device and surfacing as `responseTruncated` — the structural removal of the S4 extractor-drift nit. `ModelCallTierResolution` widened past its two cases to `.userSelectedTier` / `.configuredPreferences` / `.degradedToOnDevice`, the third being the honest label for a chat whose provider key vanished mid-session. **ADR-0045 V3** landed here (the one slice with both repos open): a per-provider `FrontierModelPreference`, an AI Settings Default/Custom model picker, `TieredModelClient.live(modelForProvider:)`, and `ModelCallRecord.requestedModel` so the S2 inventory reports the model actually requested. Two device-worth behavior changes: a keyless chat goes **on-device** rather than rerouting to another provider's key, and reader-feedback curation + the brief extractor **fail loud** with no key. Verified: build exit 0, `scripts/check-drift.sh`, tests, and Jon's device pass. **Landing S3 fires [ADR-0044](decisions/ADR-0044-provenance-engine-to-llmclientkit.md)'s trigger** (the provenance-engine lift) — a signal to write that design, not to build it.

---
## ADR-0043 load test — three advisory verbs hand off, and `omitted:` gets its first production call site

**✅ Verified & approved, 2026-07-24 (architect-reviewed at `f1df74d`).** Merged as PR [#226](https://github.com/jonphillips/yes-chef/pull/226), branch `codex/adr-0043-advisory-load-test` — commits `e457cb1` (the slice) + `cff5604` (review round 1) + `f1df74d` (review round 2). App + Core; **no schema**, nothing added to the prod-promotion list. Verified locally on a clean worktree at the PR head: elevated `generic/platform=iOS` build exit 0 with no new warnings from the changed files, and `swift test --package-path YesChefPackage` **403 tests**. Spec: [ADR-0043](decisions/ADR-0043-model-call-chokepoint.md) — the load test entry, whose verdict is now written into the ADR itself.

**The load test produced a real result, which was the entire point of running it.** `menuComplement`, `mealPlanComplement`, and `readerFeedbackCuration` each got a hand-off ask, deliverable format, D8 learnings call, and commit shape. Expressing them forced `ModelCallContextLayer.tasteProfile` into existence as a first-class layer: both complement calls **include** it (their prompts inject the taste profile and the complement preference), and `readerFeedbackCuration` declares **`omitted: [.tasteProfile]`** because curation transcribes comment evidence rather than making a taste judgment. That is the **first production call site `omitted:` has ever had** — it shipped in S1 with a passing test and zero real users, and the S1 approval named exercising it as the explicit success criterion. Tests pin all three records. **The included/omitted distinction earns its place**, and D6's judgment-vs-transcription asymmetry is now visible in production data rather than argued in prose. No tier-policy change was needed, so **S3 remains independently scoped** — the load test did not fold into it.

**Two silent-data-loss defects were found in review and fixed at the right layer.** De-duplicating the parser by reusing `applyingEditableReviewText` was structurally correct, but its fallback semantics — *keep the previous value* — are wrong where there is no previous value: an unrecognized meal slot silently became `.dinner`, and meal-plan surplus lines silently vanished. The fix restores an explicit `MealPlanItemSlot(handoffPlacementLine:)` check inside the guard, keeping the single-parser win **and** the validation, and routes surplus lines to `unparsedBlocks`. New tests assert exactly the reproduced cases. This is [[llm-curation-not-synthesis]]'s sibling rule in the parsing layer: a fallback that cannot distinguish *absent* from *unrecognized* launders bad input into plausible data.

**Malformed returns became review evidence instead of a failed import.** `unparsedBlocks` / `unparsedLines` now flow to the review surfaces on all three verbs rather than failing the whole paste; an all-unlabeled reader-feedback return reports the missing `Tip:` format directly. Block segmentation splits on the **label cycle** (matching the experiments parser) so compacted blank lines are safe; `labeledHandoffBlocks` is shared; task routing switches are exhaustive again, so the next verb is a **compile error until routed**; and `instructionsOutOfDate` collapsed into one shared Core definition.

**Carried forward (non-blocking, noted at approval):** `stageReaderFeedback` defaults `unparsedLines` to `[]`, so accepting a single tip through the in-app path clears the evidence banner — cosmetic. And a device-pass observation: the Prep Plan disclosure now renders **two Copy + two Paste** buttons, and the meal-plan day header **four**; pasting a complement result into the prep-plan Paste button correctly routes to the unmatched-result confirmation, but the crowding wants a feel on iPhone.

---
## ADR-0021 V3 — the why survives the commit: a recipe-scoped deliberation log

**✅ Verified & approved, 2026-07-24 (architect-reviewed at `ec59260`).** Merged as PR [#225](https://github.com/jonphillips/yes-chef/pull/225), branch `codex/adr-0021-v3-deliberation-log`. Core + app; **adds one synced table — the only schema this variations arc adds** (V1+V2 added none), now on the prod-promotion list. Verified locally: full package suite **398 tests / 83 suites**, elevated `generic/platform=iOS` build succeeded. Spec: [ADR-0021 Amendment 3](decisions/ADR-0021-recipe-variations.md#amendment-3--the-why-survives-the-commit-a-recipe-scoped-deliberation-log-2026-07-23).

**The shape.** `recipeDeliberationLog` — one row per commit holding the returned brief **verbatim** (Amd3-D3; ADR-0042 D3 — prose in a human-read field pins no format), depositing on **both** commit destinations, since overwrite leaves no artifact and only depositing on the variation path would leave half the flow silent. **The schema matches Amd3-D6 line for line:** `recipeID` is the owning hard FK (`NOT NULL REFERENCES "recipes"("id") ON DELETE CASCADE`), `variationID` is a **bare indexed column with no constraint** — a variation may be deleted or promoted while the provenance survives — both indexed, `STRICT`, `uuid()` default, consistent with the `recipeVariations` / `workbenchLog` conventions. Sync registration is **guarded rather than asserted**: `syncedTableListMatchesCurrentModelTables` derives its expectation from the live schema, so registration is actually enforced.

**The read surface ships in the same slice** (Amd3-D4), which is what keeps this out of the [[withdraw-not-defer-orphaned-schema]] trap — the consumer arrives with the schema. It landed twice: first in `directionsColumn`, the Doing region ADR-0039 Amd1/OQ1 deliberately emptied of exactly this content class, then corrected to a proper Playbook section using the established section grammar, collapsed by default. The variation badge resolves the variation **name** and omits itself when the variation is gone, so it degrades silently after a promote-to-base.

**The diagnosed defect is avoided and no prose is fabricated.** The deposit carries model prose (`proposal.summary`, the LLM's brief rationale; `returned.deliverable` on the hand-off path) and **never `reviewSummary()`** — a deposit with no prose is that mistake repeated, so an empty or whitespace body deposits **no row**. The `deliberationBody` default was dropped, so every commit destination must **state its intent** rather than inherit one silently — the same trap the ADR-0043 S1 review removed one layer up. Split-off mints new IDs and nulls `variationID`, copying the **full ancestry** (Amd3-D5): the new recipe receives every row from the original's log, base adjustments included, because it is an ancestry record and not a filtered description of the split variation.

**Undo was resolved as ratify-not-fix, and that is the interesting call.** Undo leaves the deposit behind — the log records an *attempted* adjustment and the rationale supplied for it, including one the cook immediately takes back. Rather than patch the behavior to match unwritten expectations, Amd3-D5 now states that **undo restores the recipe's cooking state, not its deliberation history**, and `overwriteAndUndoRestoreTheRecipeWhileKeepingTheDeliberationRecord` pins it. Prose plus a test is what makes a semantic like that durable.

---
## ADR-0021 V1 + V2 — editable recipe variations and promotion

**PR [#221](https://github.com/jonphillips/yes-chef/pull/221), 2026-07-23 — approved + device-passed.** Variations are now edited as ID-preserving resolved recipe detail and reduced back into the existing delta vocabulary only when fully representable; a structural edit is identified precisely and offered a split-off, never a partial save (Amd1-D4/D7). V2 materializes a split-off as a standalone recipe, or promotes a variation to the base while retaining the former base as a variation. Existing siblings are re-derived against the new base; if a later sibling cannot be reanchored, promotion requires explicit confirmation before removing it — answering ADR-0023 OQ3. **No schema change — the `deltas` BLOB stays** (Amd1-D3). ADR-0021 Amds 1 + 2 ratified 2026-07-23; **Amd 3 (V3, the recipe-scoped deliberation log) remains a separate queued slice** — the only part of this arc that adds schema.

**Review follow-ups folded in before merge:** the editable section-name field (which would have always forced a split-off, since headers are unrepresentable until ADR-0014) was removed from the variation editor; the data-loss `needsConfirmation` promotion path and the edit-back-to-base / inserted-step minimality cases gained Core tests; **split-off now confirms and names the new recipe in-flight** (both the reader-menu and editor entry points, defaulting to the variation name); and a **view-layer targeting bug** was fixed — the two-step "promote and remove" dialog acted on `activeVariation` after the first dialog niled the target, so promoting a *non-active* variation could remove the wrong sibling. The `PendingVariationRemoval` payload now carries the promoted variation into the second dialog and the `activeVariation` fallback is gone (the Core function was already correct and tested, which is why the suite stayed green through the bug).

**Verification.** Full `scripts/check-drift.sh`: **395 tests / 82 suites**, SwiftLint clean; elevated `generic/platform=iOS` build succeeded. Device-passed by Jon, including the non-active-variation promote-and-remove path.

---
## ADR-0043 S2 — dev-only model-call inventory

**✅ Verified & approved, 2026-07-23 (architect-verified; no device pass required).** PR [#220](https://github.com/jonphillips/yes-chef/pull/220), branch `codex/adr-0043-s2-model-call-inventory`, commit `8428426`. The required elevated Debug `generic/platform=iOS` build and the Release configuration build both succeeded; `scripts/check-drift.sh` passed **386 tests / 81 suites**, and S1's bypass-enforcement test remains green. App + Core; **no schema**, no persistence, and no cook-facing UI.

**The shape.** The DEBUG-only Settings pane reads `ModelCallRecordCollector` directly from the dependency container; `ModelCallRecordSink` and collector are installed together at app composition. The inventory is an argument-free, derived view of the append-only records: surface, task, **tier requested**, tier resolution, included and omitted context layers, input character count, budget, and effort. The release app has no inventory UI.

**The S2 review exposed an S1 modeling gap early.** The ADR/dispatch wording promised the tier actually used, but S1 records the tier at construction while `TieredModelClient` can resolve or degrade downstream. Presenting that field as actual would be false, so S2 labels it honestly as **Tier requested**. Resolved-tier reporting belongs to S3, where `resolveTier()` is unified and `ModelCallTierResolution` widens; this is recorded as a scope correction, not silently treated as fulfilled.

**The inventory update logic lives in Core.** `ModelCallInventory.appendNewRecords` computes the append boundary at mutation time, so overlapping `.task` and `.refreshable` refreshes neither duplicate nor misnumber records. Its focused test pins append-only snapshot semantics. The collector remains intentionally uncapped and process-lifetime-only for DEBUG use; cap it before any broader use.

---
## ADR-0043 S1 — every model call declares itself, and a test fails when one doesn't

**✅ Verified & approved, 2026-07-23 (architect-verified; behavior-neutral, no device pass required).** Merged as PR [#219](https://github.com/jonphillips/yes-chef/pull/219), branch `codex/adr-0043-s1-model-call-chokepoint` — commits `b85e8a6` (the slice) + `d50b661` (review round 1) + `697b121` (review round 2). Core plus two app call sites; **no schema**, nothing added to the prod-promotion list. Verification green: 385 Core tests, `scripts/check-drift.sh`, and the elevated `generic/platform=iOS` build (required because `YesChefApp/` was touched — the architect ran it locally). Spec: [ADR-0043](decisions/ADR-0043-model-call-chokepoint.md) D1/D2/D3/D6.

**The shape.** `ModelCall` is now the sole construction path for `ModelRequest` — the wrapped request is `private` and only `complete(using:)` / `stream(using:)` escape, so there is no way to hold one without having declared it. All **17** construction sites route through it. The 17-vs-18 mismatch the dispatch flagged resolved cleanly: the grocery categorization retry reuses one call builder for a second completion, so nothing is double-counted or dropped. Recording only — **no call changed tier, budget, prompt text, preference key, or continuation behavior**, and the diff supports that claim hunk by hunk.

**The record** captures `(surface, task, tierResolution, tier, contextLayers, inputCharacterCount, maxTokens, reasoningEffort)` at construction, which is exactly what `LoggingModelClient` is structurally unable to infer at completion. The decorator was neither replaced nor duplicated.

**The enforcement test is the deliverable, and it took two rounds to become load-bearing.** As first written it scanned `Sources/YesChefCore` with `contentsOfDirectory` — **non-recursive** — leaving the 14-file `WebRecipeCapture/` subdirectory unscanned, and it did not scan `YesChefApp` at all. The architect verified both holes by dropping a raw `ModelRequest(prompt:)` into each and watching the guard pass. It now walks `YesChefPackage/Sources` **and** `YesChefApp` recursively and fails on raw `ModelRequest(` construction or direct `modelClient.complete(` / `.stream(` dispatch. Re-probed after the fix: both are caught and named.

The better-than-asked-for part is that **the guard now tests its own reach** — `#expect` assertions that `WebRecipeCaptureClient.swift` and `HandoffReviewCoordinator.swift` are in the scanned set. The original failure mode was not the missing recursion, it was that a *silently shrinking scan* is invisible; a directory move that narrows coverage now breaks loudly. **What it deliberately does not catch:** aliased clients or aliased request types. It matches text, which also means it nags doc comments (one in `WorkbenchCompareAligner` was reworded to get past it).

**Recording the defect the ADR was written about.** `tierResolution` was initially `.callerProvided` at 16 of 17 sites — including `RecipeAdjustment`, whose caller is the `availableProviders.first` → silent `.onDevice` path the ADR's "damage is already on the board" section describes. The enum was recording *where* resolution happened, not *how*, so the record for the one call that motivated the ADR pointed back at a grep. Fixed by threading the resolution from the resolver: `HandoffReviewCoordinator` now declares `.preferredProviderOrFirstAvailable` and the record tells the truth. A follow-up removed the `= .callerProvided` **default** on the client's `callAsFunction` — there were two callers, and the second was correct only by inheritance, which is the same silent-default trap one layer up.

**The record is readable without touching a single call site again.** As first written it was write-only — constructed, then dropped, with nothing reaching the logging seam — which would have made S2 a 17-site retrofit. Closed with `ModelCallRecordSink`, a dependency published from `complete`/`stream` whose live value intentionally retains nothing; **S2 installs an in-memory collector at the composition root and changes zero construction sites.** (`stream(using:)` became `async` to publish before dispatch.)

**Context layers stopped lying by uniformity.** `.systemInstructions` and `.tasteProfile` were declared at 17 of 17 sites — but the taste profile is injected unconditionally at the composition root (`YesChefAIPromptPreferences.modelPromptPreferences`), so those were hand-copied restatements of a global fact with no test binding them to it, and they would have gone silently stale the moment injection became conditional. Both cases were deleted. `ModelCallContextLayers` now carries `included` **and** `omitted` (disjointness enforced by `precondition`), so **deliberate absence is sayable** — which is what D6 needs, since the judgment-vs-transcription asymmetry is a statement about what a call *withholds*.

**`promptPreferenceKey` survives beside `surface`/`task`, and that is correct — do not re-litigate it.** The dispatch warned that a second parallel identifier means S1 is wrong. It isn't one: the key is **functional**, selecting the user's synced per-task prompt-preference column, and it is deliberately **coarser** than the record — `captureToNote` is shared by three distinct tasks (`depositAppend`, `depositRevise`, `noteHarvest`). Six preference kinds against fifteen tasks is a grouping, not a duplicate naming scheme.

**Carried forward (both noted at approval, neither blocking):**
- **`omitted:` has zero production call sites.** It is proven by test only. The three-advisory-verb load test should treat exercising it as an explicit success criterion — if none of those verbs needs it, that is real signal about whether the field earns its place.
- **`tierResolution`'s two cases are visibly under-modeled.** There are at least three real shapes — user-selected via the chat provider picker, preferred-or-arbitrary-first fallback, and opaquely-passed-down — flattened into two. Left alone on purpose: S1 is recording-only, and the chat path's tier is user-visible so the ADR's actual grievance (a *silent* drop) doesn't apply there. **S3 widens the enum when it unifies `resolveTier()`**, at which point the distinction has a consumer.

---
## iPhone chrome pass — the compact tab bar stops overflowing, and the hand-off door comes out of the `•••`

**✅ Verified & approved, 2026-07-23 (Jon device-passed).** Merged as PR [#218](https://github.com/jonphillips/yes-chef/pull/218) (`40bc6d4`), branch `codex/iphone-chrome-pass` — commits `01fa6a8` (both slices) + `557272f` (review fixes). **App layer only** — five files, **no Core, no schema**, nothing added to the prod-promotion list. Both defects came from Jon's 2026-07-22 iPhone pass; neither was reachable on iPad, which is why they survived this long.

**Slice 1 — four primary tabs, and a More tab we own.** `AppSection` has **seven** cases and the compact `TabView` rendered all seven, so iOS collapsed everything past the fifth into a **system-managed More tab — which is its own `UINavigationController`**. `MenusStack`'s `NavigationStack` nested inside it and every Menu detail drew **two stacked back chevrons**, with Menus, Groceries and Settings all buried. Jon's call: the four primary tabs are **Recipes / Menus / Calendar / Groceries** — the cooking workflow — and Browser, Workbench and Settings move into an `AppMoreStack` we control.

Three traps, all navigated: the More stack pushes the **content** views (`BrowserWorkspaceView`, `WorkbenchListView(style: .navigation)`, `SettingsView`), never the `*Stack` wrappers — pushing those would have recreated the exact nesting the slice removes, and the three now-unused wrappers were **deleted** rather than left as decoys; the workbench's own list→detail push meant `.navigationDestination(for: Workbench.ID.self)` had to be **re-registered on the More stack**; and `AppSection` deliberately grew **no `.more` case** (the regular-width sidebar needs the real destinations), so compact selection runs through its own tab enum with **external navigation writers kept out** until More has a route enum that can represent every section. The regular-width `NavigationSplitView` path was not touched.

**Slice 2 — the hand-off round trip is visible on a phone.** `RecipeDetailView` put **Hand off** and **Paste** in `ToolbarItemGroup(placement: .secondaryAction)`, which on iOS collapses into the nav-bar `•••` — wired correctly (not the PR #216 `PasteButton` bug, already fixed by `2446ed0`) but buried, so on iPhone Jon read the recipe toolbar as simply **not having** copy/paste. [ADR-0042 Amd 1](decisions/ADR-0042-workbench-handoff-and-the-return-block.md)'s whole premise is a **round trip**, so a hidden return door is a broken feature. Replaced with a single `.primaryAction` **`Menu`** (`sparkles.square.filled.on.square`) holding both — still **plain buttons reading `UIPasteboard.general.string` directly, because `PasteButton` does not render inside a `Menu`** (the constraint now documented on `HandoffCopyPasteControls`; this is its third appearance and it has stopped being a surprise).

**The crowding tradeoff was confirmed, not assumed.** `.primaryAction` already carried four buttons plus a fifth on wide layouts; adding a hand-off menu would have re-created the same overflow failure in a new place. The architect's recommendation — **demote `Workbench` into `.secondaryAction`** on the grounds that hand-off is now a daily round-trip and the workbench is an occasional deep-dive — was flagged as a **product tradeoff for Jon to confirm rather than an implementation detail**, and he took it. `View Original` and `Archive` stayed put, and the `activeVariation` guard still routes through the `isConfirmingBaseRecipeHandoff` confirmation (Amd1-OQ3).

**Two reports from the same pass were deliberately excluded, and stayed excluded.** Jon reported the Playbook showing a *"Hand off to ChatGPT"* button and **no per-section `•••`** — but that string does not exist anywhere in the codebase (ADR-0041 S1, `4a3a564`/PR #199, confirmed an ancestor of `HEAD`, deleted the column-top button and replaced it with the per-section menu). Seeing the old label **and** no `•••` is exactly what a **pre-#199 build** looks like, so both were held pending a reinstall rather than "fixed." Nothing further was reported after the reinstall. **If either survives a current build it is a genuine and surprising regression and gets its own scoped entry** — do not pre-emptively chase them. (Separately: the **Notes** section has no `•••` *by design* — ADR-0041 scoped the section toolbar to Make Ahead / Chef It Up / Serve With.)

---
## ADR-0042 S4 (Amendment 1) — the recipe body hands off, and a revision brief comes back

**✅ Verified & approved, 2026-07-21 (Jon device-passed).** Merged as PR [#216](https://github.com/jonphillips/yes-chef/pull/216) (`35d3654`), plus two architect follow-ups: `2446ed0` (the paste affordance) and `31d2089` (the base-write guard). App + Core prompt; **no schema**, nothing added to the prod-promotion list (`AIHandoff` is device-local). Spec: [ADR-0042 Amendment 1](decisions/ADR-0042-workbench-handoff-and-the-return-block.md#amendment-1--the-ask-outboards-a-revision-brief-returns-and-the-in-app-extractor-still-writes-the-delta-2026-07-21).

**The gap it closed.** D7 retired ADR-0023 S3's in-app refine loop on the premise that *refinement happens in the live external thread* — but nothing was ever built to make that possible: the recipe **body** had no export door (ADR-0041 scoped recipe hand-offs to the three Playbook sections), so make-ahead notes could outboard while ingredients and method could not. In practice that meant hand-copying a recipe into ChatGPT, arguing the revision out, then re-typing the ask in-app — **the reasoning discarded at the boundary.**

**The shape: the ask outboards, prose returns, the structured write stays in-app.** A `.discuss` hand-off sends the whole recipe (plus taste profile and known learnings); a **revision brief** comes back — a decided revision in a cook's language, one change per line, *"never ops, never IDs, never a rewritten recipe"*; the human edits the brief in a review sheet, then *"Draft the revision"* hands it to the shipped `recipeAdjustmentClient`, which resolves it against live `id`/`sectionID`/`sortOrder` and lands in the existing side-by-side review with the existing two commit destinations. **D2 is upheld, not relaxed — nothing carrying identity crosses the paste door.** No contract bump (Amd1-D6), and the brief is transient (Amd1-D5).

**Two defects found after merge, both fixed here.**

1. **The recipe body had no paste affordance at all (`2446ed0`).** S4 wired `HandoffCopyPasteControls` into the toolbar's `.secondaryAction` group, which collapses into the overflow menu — and **`PasteButton` does not render inside a menu**, so the copy button survived and the paste control silently vanished. The round-trip was one-directional in the app: you could send a recipe out but not bring the brief back, which is the entire point of the amendment. Replaced with plain buttons reading `UIPasteboard` directly, matching the Playbook section menu. **ADR-0041 Amd 1 had already retired `PasteButton` for exactly this reason**; the lesson lived only in an ADR, so the constraint is now a doc comment on `HandoffCopyPasteControls` itself. The other three surfaces render it in ordinary view content and were unaffected.
2. **Amd1-OQ3's v1 requirement never shipped (`31d2089`).** The ADR required v1 to *"export the base recipe and say so in the sheet, or refuse to export while a variation is active"*; S4 did neither — the export path had zero variation awareness. Closed by the broader guard below.

**The base-write guard — one fix for two symptoms.** Root cause, worth stating once: **a variation is a display-time overlay — every read path folds it, no write path knows it exists.** Reads fold (reader; grocery via `RecipeRepository.fetchDetailApplyingActiveVariation`), while the recipe editor has *zero* variation awareness and loads the base, and adjust applies to the base `detail` rather than the resolved `displayDetail`. Jon hit the other half of this on device — adding an ingredient with a variation active silently wrote to the **base**. Making writes variation-aware is [ADR-0021 Amd 1](decisions/ADR-0021-recipe-variations.md) (Proposed) and a real effort, since a newly added ingredient has no base row to anchor to, so the honest interim is a guard rather than a partial write path: the editor shows an inline notice, and the hand-off confirms before copying. Both point at **promote** as the intended answer, per ADR-0021 Amd 2's release valve — the delta model is deliberately *not* widened.

**Open, carried forward:** ~~the **"why" dies at the commit boundary**~~ — **CLOSED 2026-07-23 by [ADR-0021 Amd 3](decisions/ADR-0021-recipe-variations.md#amendment-3--the-why-survives-the-commit-a-recipe-scoped-deliberation-log-2026-07-23) (Accepted):** option (d), a recipe-scoped deliberation log holding the brief verbatim, depositing on both commit destinations, shipping as ADR-0021 **V3**. **This also resolves Amd1-OQ2 — the brief is durable after all, reversing its "discarded" lean.** Also still open: **OQ3** (compare: commit or advisory), **OQ5** (do the in-app workbench verbs survive), and OQ6's non-gating **Claude portability run**.

**With this, the ADR-0042 slice plan is complete** — S0/S1/S2/S4 shipped and device-passed; **S3 (`workbenchDraft`) stays deferred and un-queued** (no concrete want, and its danger receded rather than grew — do not build it on ADR momentum); there is no S5.

---
## ADR-0042 S2 — the experiments verb, its typed columns, and the label-cycle parser

**✅ Verified & approved, 2026-07-21 (Jon device-passed; merged to main as PR [#214](https://github.com/jonphillips/yes-chef/pull/214), branch `codex/adr-0042-s2-experiments`).** Commits `6c71c8a` (the slice) + `a7b66b9` (architect-review fixes) + `aa100d0` (workbench dogfooding polish, rode along). Core + app; **schema — three additive nullable synced columns + migration** on `workbenchLog` (`hypothesis` / `change` / `rationale`), recorded in the standing prod-promotion list in the same PR. Verification green: package `swift build` + 378/378 Core tests, elevated `generic/platform=iOS` build, `scripts/check-drift.sh`. Spec: [ADR-0042](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) D5/D8 + OQ2/OQ6.

**Experiments outboard and come back as typed rows, not prose.** `workbenchExperiments` returns labeled three-line blocks — `Hypothesis:` / `Change:` / `Rationale:` — parsed by the new `AIHandoffExperiments.swift` into `.experiment` `workbenchLog` rows with the triple in typed columns, plus the per-field edit affordance that justifies typing them (OQ2: an experiment is **write-many** — its `outcome` is filled in after it is tried — so ADR-0040 puts the fields in columns rather than smearing them into `body`). This **supersedes ADR-0019 S3's `Workbench.experiments` BLOB**, which was never built.

**The parser splits on the label cycle, never on whitespace** — a new `Hypothesis:` line opens a block — because OQ6's live run proved blank-line separators do not survive the paste path, and it is indeterminable whether the model or the paste dropped them. Unit-covered for the run-together shape the live run actually produced. Parsing is lossless-or-loud: unparsed blocks fail the import with `unparsedExperimentBlocks` rather than landing partial rows.

**D8 enforced in all three places.** An experiment is a conjecture, so `YC-LEARNINGS:` is dropped from the outbound prompt, suppressed in the contract's Experiments stanza, and ignored on import if returned anyway. Knowledge belongs in the experiment's `outcome`, after the thing is cooked — recording an outcome is what promotes a conjecture to a learning.

**Architect review, folded into `a7b66b9`.** (1) The experiments **migration was registered mid-list, ahead of the already-applied ADR-0040 prep-plan migration** — moved to the end so applied migrations stay a stable prefix (both additive and independent, so no data risk either way, but the ordering habit matters more than this instance). (2) The pasted contract now carries a **human-visible `v2` label**: the version previously appeared only inside the "second line must be `YC-CONTRACT: v2`" clause, so a human could not tell which version their project actually held — which defeats the point of a drift marker.

**⚠️ Deploy dependency (intended).** **The contract is now v2 — re-copy the project instructions from AI Settings**, or every verb fails the marker gate. This is the gate working, not a regression: a stale paste is exactly the silent config drift the marker exists to catch.

**Workbench dogfooding polish (`aa100d0`, Jon's asks).** Candidate rows open their recipe on tap (**header only** — the row also hosts the annotation field); copy and save confirm via the existing `AppToastCenter` toast + success haptic across all four hand-off surfaces plus workbench annotation and log-entry saves. **Toast hosting differs by surface on purpose:** an overlay mounted by a presenting view does not draw over the sheet it presents, so the workbench and `RecipeDetailView` host their own — the latter is built from four call sites and only `RecipeFullScreenCover` mounted one, which is why the iPad `AppMainLayout` path was silently toast-less — while Menu and Meal Calendar reuse their model's shared center.

**Non-blocking follow-ups left for a later slice:** the `canSave` / `normalizedLogEntryDraft` mismatch when a body is combined with partially-filled typed fields; the dead save spinner; and the pre-existing compare `.menuPrepPlan` mislabel.

**Not built, by decision.** `workbenchDraft` stays deferred (D5/S3) — no concrete want, and its danger has since receded rather than grown (see [ADR-0042 Amd 1](decisions/ADR-0042-workbench-handoff-and-the-return-block.md#amendment-1--the-ask-outboards-a-revision-brief-returns-and-the-in-app-extractor-still-writes-the-delta-2026-07-21) + [ADR-0021 Amd 2](decisions/ADR-0021-recipe-variations.md#amendment-2--promotion-is-the-release-valve-a-variation-can-become-the-base-or-its-own-recipe-2026-07-21)); **do not build it on ADR momentum.**

---
## ADR-0042 S0 + S1 — the workbench hands off; the return contract moves to the project

**✅ Verified & approved, 2026-07-20 (Jon: device is fine). Rides in the ADR-0042 S0/S1 slice PR (**[#212](https://github.com/jonphillips/yes-chef/pull/212)** — branch `codex/adr-0042-s0-s1-workbench-handoff`), commits `f865250` + architect-review fix `3662aa2`; Jon does the git dance. (A duplicate dispatch produced a redundant PR #213 on the same slice — to be closed unmerged; #212 is canonical.)** Core + app; **no schema / migration** (both slices schema-free by design — S2 is the schema slice). Verification green: package `swift build` + Core `AIHandoff` tests (23/23), elevated `generic/platform=iOS` app build (incl. share extension). Spec: [ADR-0042](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) D1/D4/D5/D6/D9.

**S0 — the return contract left the payload for the project's custom instructions (D4).** One Core constant `AIHandoffReturnContract` is now the single source of truth: `projectInstructions` (the compressed D4 prohibition list), `version = 1`, and the `YC-CONTRACT: v1` marker. A **Settings copy button** (AI settings) emits it verbatim for the shared Yes Chef project. Every return path (`stageReview` / `stageReviewForKnownSource`, covering both the in-app paste transport and the App Intent — verified no bypass) runs `strippingMarker`: a missing or stale (`v0`) marker fails loud with `HandoffReturnContractError.instructionsOutOfDate` ("Re-copy from Settings…"). The outbound prompt shrank to **title + token + context + the verb's ask** — the token-preservation / learnings / no-fence / no-choreography instructions all moved into the project instructions, which **closes the long-standing `.discuss`-has-no-example gap** ([ADR-0041 S2.5 blob-report root cause](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md)) for make-ahead / Chef It Up / Serve With / prep-plan too.

**D9 — every outbound prompt now leads with a derived `<TaskType>: <Object>` title line** (`AIHandoffTaskType.title` + `prompt(title:)`), advisory only — nothing parses it. Task-not-object-kind on the left so the three section-scoped recipe threads (Make-ahead / Chef It Up / Serve With) get distinct titles rather than colliding on one recipe.

**S1 — `.workbench` is a hand-off source; compare ships first (D5), the log deposit lands (D6).** `AIHandoffSourceType` gained `.workbench`; `AIHandoffTaskType` gained `.workbenchCompare` (+ `.workbenchExperiments`, which stays **unwired → `wrongTask`** per D2 until S2). The compare deliverable is deliberately **prose-only** — `compareHandoffPrompt` asks for "named differences with a claim attached, one per line," while the deterministic matrix stays in-app (`WorkbenchCompareCore`). Its return stages into the review sheet and, on the human's per-item approval, deposits `.observation` rows into the `workbenchLog` (schema-free — D3 prose a cook reads). The retired **ADR-0023 S3 workbench-log deposit is promoted (D6)**: a committed recipe adjustment — overwrite *or* variation — opened *from* a workbench now drops a `.rationale` `workbenchLog` row (`relatedRecipeID` set), via a `workbenchID` threaded through `RecipeDetailPresentation` → `RecipeDetailModel`; opened outside a workbench it is a clean no-op.

**Architect review, folded into `3662aa2`.** (1) **Required fix** — the in-app transport rendered every error via `String(describing:)`, so the D4 stale-instructions guidance surfaced as the raw case name `instructionsOutOfDate`. Fixed with a *targeted* `(error as? LocalizedError)?.errorDescription ?? String(describing:)` (a blanket `localizedDescription` swap would have regressed the transport's non-`LocalizedError` errors — `AIHandoffIntentImportError`, `HandoffIntentSurfaceError` — to the generic Cocoa string). (2–4, cleanup) deleted the now-dead `DeliverableFormat.example` (every per-verb shape lives in its own context — recipe sections via `lineListFormat`, menu prep via `- task → serves`, meal-plan via its inline example), trimmed the redundant "first line must be the token" clause from `discussInstruction` (the project instructions own it now), and deleted the orphaned `MenuModels.copyPrepPrompt` (zero callers since ADR-0038 S1, a latent pre-contract-bypass trap).

**⚠️ Deploy dependency for Jon (intended, not a bug).** The marker gate now applies to **every** verb, and the outbound prompts no longer carry the return contract — so the whole hand-off feature is **inert until the v1 project instructions are pasted** into the ChatGPT/Claude project (a marker-less paste-back correctly fails with the stale-instructions error). "S0 improves the existing verbs immediately" is really "immediately after the one-time paste." Copy them from AI Settings before the first round-trip.

**Not built, by decision.** `adjustRecipe` stays the in-app structured verb (D2 — a canonical write never round-trips through the paste door); the `.workbenchExperiments` verb + its three synced `workbenchLog` columns are **S2** (its own dispatch, un-gated after OQ6); `workbenchDraft` is deferred (D5/S3).

---
## ADR-0041 CLOSED at S2.6 — S3 withdrawn, the conversation URL does not exist

**✅ Decision, 2026-07-19 (Jon) — docs only, no code.** [ADR-0041 Amendment 3](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-3--s3-is-withdrawn-the-conversation-url-does-not-exist-2026-07-19) + [ADR-0038 Amd 3 → **Withdrawn**](decisions/ADR-0038-external-llm-handoff.md#amendment-3--an-optional-user-pasted-conversationurl-to-reopen-the-live-chat-2026-07-15). **ADR-0041 shipped S1 → S2 → S2.5 → S2.6 with no schema change of its own; nothing was added to the prod-schema promotion list.**

**The device check S3 was gated on came back negative.** ChatGPT's mobile flow yields only a `/share/` read-only snapshot, never the live `/c/` conversation URL, and no custom URL scheme or intent handler exists to reopen a conversation (requested publicly ~a year ago; nothing shipped). A universal link on `chatgpt.com/c/*` wouldn't need a scheme and might open the app — but it's moot, because **the URL can't be captured in the first place**. S3 existed to give that URL a synced, section-addressable home.

**The "meta + provenance still ship" fallback was rejected too — this is the part worth remembering.** S3's own slice bullet had pre-authorized shipping `PlaybookSectionMeta` without the URL. Three reasons it didn't:

1. **The table's shape was derived from the URL.** OQ2 keyed it `(recipeID, sectionKind)` because *"the session produced the whole set"* — the URL's reasoning, not provenance's. Shipping it URL-less would freeze a **permanent synced record type whose key is justified by a field it no longer carries.**
2. **No provenance consumer exists** (confirmed). A synced table added on spec is exactly the cost that becomes **irreversible at the prod-schema cut**, where promotion locks a record type permanently.
3. **"Deferred" would have built it anyway** — a schema slice parked in a queue gets built later on the momentum of the ADR saying so, rather than on need.

**What survives the want.** The durable session anchor was always **the project**, not the URL (ADR-0038 OQ6 / `Menu.externalProjectName`, shipped and unaffected). The real remaining gap is that **Recipe has no project story** — so if "return to my ongoing conversation" resurfaces for recipes, the first move is a per-recipe project name reusing the shipped pattern, **not** a URL field or a revived meta table.

---
## ADR-0038 Amendment 5 — Learnings have sparse, human-controlled order

**✅ Merged to main — PR [#210](https://github.com/jonphillips/yes-chef/pull/210), 2026-07-19 (recovery of the already-reviewed [#208](https://github.com/jonphillips/yes-chef/pull/208); unchanged cherry-pick). Verification green: `swift build`, Core migration/backfill + rebalance tests, generic iOS `build` **and** `build-for-testing`, `scripts/check-drift.sh`. ✅ Jon device-passed 2026-07-22.** Core + app; **schema — additive synced column + migration** (`Learning.sortOrder`), recorded in the standing prod-promotion list.

**Learnings became manually reorderable** on the recipe Playbook, the menu Playbook, and menu prep-plan editing — the shared `LearningsSection` gained SDK 27 `.reorderable()` on its `ForEach` with `.reorderContainer(for: Learning.self)` on the enclosing `VStack` (it was already the drag container; no standalone `.draggable`). The query sorts ascending by rank, keeping the old date/UUID order only as a tie-breaker.

**Ranks are sparse by design (the load-bearing call).** The migration backfills per `(sourceType, sourceID)` group at a `1024` stride and adds a matching index; a drag writes **only the moved rows**, taking a rank between neighbors, and rebalances just the one affected group when no integer gap remains. This deliberately differs from the contiguous `sortOrder` tables (ingredients, instructions, prep-plan steps): those are rewritten wholesale as a generated collection, while a Learning is a human move on a **live two-device synced library** — sparse ranks avoid an N-row sync write and reduce cross-device interleaving.

**Known tradeoff, on the record for Jon's device pass.** New AI learnings still **prepend** (a backfill starting at `0` means the next insert takes a negative rank, e.g. `-1024` — negatives are valid), so a returned item can land ahead of a deliberate manual arrangement. Continuity was kept over inferring a mode switch; revisit if it fights real use.

---
## ADR-0041 Slice 2.6 — Playbook destructive-action safety + Serve With row consistency

**✅ Merged to main — PR [#209](https://github.com/jonphillips/yes-chef/pull/209), 2026-07-19 (recovery of the already-reviewed [#207](https://github.com/jonphillips/yes-chef/pull/207); unchanged cherry-pick of `121ac58`). Verification green: Core build/tests, generic iOS `build` **and** `build-for-testing`, `scripts/check-drift.sh`. ✅ Jon device-passed 2026-07-22.** App + Core; **no schema / migration**. Spec: [ADR-0041 Amendment 2](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-2--destructive-section-actions-are-explicit-and-serve-with-rows-use-the-native-gesture-2026-07-19), from Jon's S2.5 device pass.

- **Clear confirms before writing.** A section-scoped `confirmationDialog` (driven by a `clearingSection: PlaybookSectionKind?`) names the section and states there is no undo — clearing is a permanent write reachable from the shared `•••`.
- **Clear left the section editor sheet — a deliberate partial reversal of D4.** D4 had put Clear in the editor so every action had a home, but its proximity to Cancel made it fat-fingerable. The `clear` closure came off `RecipeSectionEditorView` entirely; the editor is now purely review-and-save.
- **Serve With adopts swipe-to-delete.** The always-visible red `xmark.circle` became a `.swipeActions` `Label("Remove …", systemImage: "trash")` inside a `.swipeActionsContainer()` — matching the app's other list rows, quieting the content column, still reachable by item name for VoiceOver.
- **Pasted enrichment bullets normalize in Core.** The app-layer line-splitting renderer (which double-bulleted already-bulleted paste) was replaced by `PlaybookEnrichmentText.displayText(for:)` in `YesChefPackage` — paragraph-aware, strips leading `-`/`*`/`•`/`–` markers before applying the app's own `• ` treatment, and keeps single-line text as prose. Unit-covered for already-bulleted, mixed-style, single-line, and plain multi-line text. Pure logic in the package, per the Verification Pattern corollary.

**⚠️ The stacked-merge trap repeated.** #207 and #208 were both based on `codex/adr-0041-s2-5-nondestructive-handoff` rather than main, and merged *after* #206 had already merged — so GitHub marked them "merged" while their commits never reached main. Recovered as clean cherry-picks onto main (#209, #210). Same lesson as PR #203: **base stacked PRs on main, or confirm the merge commit is an ancestor of main before treating it as shipped** ([[verify-local-fix-reached-merge]]).

---
## ADR-0041 Slice 2.5 — non-destructive section returns + the collapsed section toolbar

**✅ Merged to main — PR [#206](https://github.com/jonphillips/yes-chef/pull/206), 2026-07-19. Verification green: `swift build`, `scripts/check-drift.sh` (SwiftLint + package tests), elevated `generic/platform=iOS` build. ✅ Jon device-passed 2026-07-22.** App + Core; **no schema / migration**. Spec: [ADR-0041 Amendment 1](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-1--a-return-never-stomps-existing-content-and-the-toolbar-collapses-into-the-overflow-2026-07-18).

**A section return can no longer silently discard hand-authored work.** S2 had paired a *regenerate-fresh* outbound prompt (which excludes the section being regenerated — correct, kept) with an inbound commit that *replaced wholesale*, so "Hand off again" on a filled section destroyed existing content. Fixed on the return side only:

1. **Serve With (list) — lossless union prefill.** The review sheet seeds with existing lines first, then returned lines, exact-deduped on the `title: note` rendering, in `YesChefPackage` with a unit test. Because `reconciledServeWithItems` matches on `title == && note ==`, surviving rows **keep their existing UUIDs** through the eventual replace-on-save; `replaceServeWithPlan` stays the only write path and stops being lossy because the box now starts out containing everything.
2. **Make-ahead / Chef It Up (blob) — explicit Replace *or* Append, no default.** `ChatApplyReviewItem` took the smallest possible widening (an optional secondary commit: title + closure) rather than a restructure — it backs every apply-action in the app. Current section content shows under *"Currently saved"* via the already-existing, previously-unused `supportingEvidenceTitle` / `supportingEvidenceRows`.
3. **Section state is captured at return-staging time**, so prompts stay fresh while the return review stays safe.
4. **The section toolbar collapsed into one header `•••` (supersedes D2 on prominence).** Every action — Hand off / again, Paste, Edit, Ask, Clear — moved into a single overflow menu right of the fill-dot, rendered only when the section is expanded. Three sections × two filled-tint buttons shouted on every view for a weekly action ([[automation-decays-near-the-stove]]).
5. **`PasteButton` retired.** It's a system-rendered `UIPasteControl` and cannot live inside a `Menu`; replaced with a plain `Button` reading `UIPasteboard.general.string`, gated on `hasStrings` (which does not prompt). The *"Allow Paste?"* alert is accepted — the grant is scoped to the current pasteboard contents, so it's ~one alert per round-trip.
6. **One wide-layout seam (`01ed188`, independently revertible).** The iPad/non-compact width rule centralized in `WideLayout`; Menu, Recipe Detail, Workbench, and Meal Calendar now share it. Behavior-preserving (the Meal Calendar site already tested `horizontalSizeClass != .compact`); retains the iPad idiom test so a landscape Pro Max doesn't acquire the wide layout, and is the intentional future macOS seam ([[macos-longterm-target]]).

**Architect review folded three fixes into the branch (`59fcaaa`).** (1) **Build break** — `ChatApplyReviewItem.commit(_:usingSecondaryCommit:)` was `nonisolated` while the closures it wraps are `@MainActor`, so every main-actor call site sent a non-Sendable `self` across isolation; both `build` and `build-for-testing` failed under Swift 6 region isolation. Isolated the method to `@MainActor`. (2) **Silent paste** — a declined paste alert left `UIPasteboard.general.string` nil and the action returned with no feedback; the empty case now goes to the transport, which surfaces the error. (3) **Replace was effectively pre-selected** — it led `.confirmationAction`, taking primary prominence and the keyboard default; now Append leads and Replace is marked destructive, so neither reads as the default (Amd1-D1).

**A second review pass pinned the blob return shape (`3cf2880`).** The Playbook hands off in `.discuss` mode, which never emits `DeliverableFormat.example`, so the blob sections' only shape signal was "plain, paste-ready review text" — ChatGPT answered with a *report* (headings, nested Markdown bullets, an assessment of what the recipe already does well), which the flat-list renderer then prefixed `• ` line by line. Serve With was spared only because its contract lives in its own section prompt. The make-ahead and Chef It Up prompts now carry the same contract — one item per line, no headings, no nesting, no preamble, no assessment, six lines max — where it holds regardless of mode, with a test so it can't quietly fall out again. (The *rendering* half of that same defect is S2.6's Core normalizer, above.) Also separated the header controls: fill-dot + chevron hug the trailing edge as one status pair, the menu sits 12pt clear with a full 44×44 target.

---
## ADR-0041 Slice 2 — the section-scoped external hand-off

**✅ Merged to main — PR [#205](https://github.com/jonphillips/yes-chef/pull/205), 2026-07-18. Architect-verified locally: `generic/platform=iOS` **TEST BUILD SUCCEEDED** (0 errors) and the touched package tests green (5/5, incl. the section-routing and prompt-scoping tests); `scripts/check-drift.sh` green per Codex. Device pass owed (Jon).** Core + app-layer; **no schema / migration** (content stays in the existing `Recipe` fields; the section meta is S3).

**Chef It Up and Serve With got their own ChatGPT round-trip.** `HandoffExportSource.recipe` became `.recipeSection(Recipe.ID, PlaybookSectionKind)`; `AIHandoffTaskType` gained `chefItUp` + `serveWith`; the private S1 view-local section enum was promoted to a Core `PlaybookSectionKind` (one enum, not two). The whole-recipe export is now explicitly Make-ahead's section hand-off (OQ5) — whole-recipe-from-Chat routes through ADR-0023 instead.

**The load-bearing fix was the router (D3).** `matches(_:)` compared only `sourceType + sourceID`, which two sections of one recipe share — so a pasted Chef-It-Up result would have routed onto Make-ahead. The section's task type is now part of the match, and `AIHandoffIntentImport` switches on it to stage a typed `AIHandoffRecipeSectionReview`. Covered at both layers: a Core test proving a Chef-It-Up token cannot stage a make-ahead review, and an app-layer `HandoffSectionRoutingTests`.

**Prompts are section-scoped and regenerate fresh.** `RecipeChatRecipeContext.serialized(includingCurrentMakeAhead:)` generalized to `serialized(excludingPlaybookSections:)`; each hand-off excludes **only the section being regenerated**, retaining siblings as recipe context ([[handoff-stateless-both-directions]]). Serve With's outbound prompt pins the `title: note` per-line format (OQ3) and the parser strips `**`/`*` emphasis from the title.

**Architect review folded three fixes into the branch.** (1) The first pass excluded *all three* sections from every prompt — a silent shrink of the shipped make-ahead prompt beyond what the ADR asked; corrected to `[section]` with a 3×3 matrix test asserting each prompt keeps its siblings. (2) `YesChefAppTests` did not compile (`RecipeScaleFormattingTests` still called the removed `ScaleText.scaledServingsSummary`), so the new app-layer routing test could never have run — retargeted to `RecipeYieldScaler.scaledText`, the path `model.scaledServingsSummary` actually delegates to. (3) Removed the now-dead `RecipeHandoffContext.makeAheadPrompt()` shim.

**Deferred out of S2 → [ADR-0041 Amendment 1](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-1--a-return-never-stomps-existing-content-and-the-toolbar-collapses-into-the-overflow-2026-07-18) (doc landed in this PR; implementation is S2.5).** Jon's device look surfaced two things S2 got wrong rather than incomplete: a return **replaces wholesale** while the prompt excludes the current section, so "Hand off again" on a filled section discards hand-authored content (worst on Serve With, where whole rows vanish); and D2's prominent per-section buttons shout on every view for a weekly action. Amendment 1 records merge-or-choose returns and the collapse of every section action into one header overflow (superseding D2 on prominence, retiring `PasteButton`).

---
## ADR-0041 Slice 1 — per-section Playbook toolbar + edit sheet · recipe Learnings loop · hand-off regenerates fresh + learning dedup

**✅ Merged to main — PRs [#199](https://github.com/jonphillips/yes-chef/pull/199), [#200](https://github.com/jonphillips/yes-chef/pull/200), [#202](https://github.com/jonphillips/yes-chef/pull/202) (+ [#201](https://github.com/jonphillips/yes-chef/pull/201) doc, [#203](https://github.com/jonphillips/yes-chef/pull/203) recovery), 2026-07-18. App-build gate green (architect local `generic/platform=iOS` → BUILD SUCCEEDED); core tests green. Device pass owed (Jon).** App-layer + Core; **no schema / migration** (reuses the existing enrichment content, the ADR-0024 review sheet, and the already-synced ADR-0038 `learnings` table). A dogfood arc off ADR-0041's acceptance — four efforts:

1. **ADR-0041 S1 — section-scoped Playbook controls (PR #199).** State-aware per-section toolbar (D2) rendered in the expanded content (collapsed = title + fill-dot + chevron only); per-section **Edit** sheet (D4) lifted off the monolithic `RecipeEditorView`; **Clear** relocated to overflow + sheet. Make-ahead's existing external hand-off moved into its section (empty → Hand off · Paste; filled → Edit · **Hand off again**); the column-top duplicate retired. Chef It Up + Serve With stay free of external controls until S2. Brand-free copy (D7). Architect review folded three fixes into the branch: Serve-With writes moved into `RecipeRepository` (out of the app layer) with an ID-preservation test; make-ahead/chef-it-up rendered as bullets when multi-line; "Redo" → "Hand off again".
2. **Recipe Learnings full loop (PR #200).** ADR-0038 Amd 1's two-part return had a write path but **no recipe display** — learnings were write-only-into-the-void. Added `LearningRepository.learnings(sourceType:sourceID:)`, `RecipeDetailData.learnings` on the observed `RecipeDetailRequest`, and a shared `LearningsSection`/`LearningRow` (generalized from the menu's `MenuLearningsSection`, now used by both). Gated off on recipes when empty so the column stays calm ([[automation-decays-near-the-stove]]).
3. **ADR-0038 Amendment 4 — Learning ingest append-only, curation deferred (PR #201, doc).** Records the dogfood finding: learnings append with no dedup/merge, and the outbound context omits existing learnings so the model re-derives them. Near-term mitigation shipped (below); the smart LLM curation pass (reconcile incoming-vs-existing, review sheet surfaces existing) is on the record as **deferred** — the exact-dedup floor "must not become the reason the smart pass never gets scheduled."
4. **Hand-off regenerates fresh + learning dedup (PR #202).** Jon's dogfood: "Hand off again" was feeding the current make-ahead back into its own prompt (a refine, not a regenerate) and learnings duplicated. Fix: `RecipeChatRecipeContext.serialized(includingCurrentMakeAhead:)` (default `true` for in-app chat; the hand-off passes `false`) so a re-hand-off regenerates **fresh** — refinement belongs in the live ChatGPT thread, not a re-export. Plus `LearningRepository.insertNew` deterministic exact-match dedup on ingest (against stored + within batch; source-agnostic, so menu/meal-plan benefit too) and an outbound "return only new learnings" instruction. See [[handoff-stateless-both-directions]].

**⚠️ Stacked-merge recovery (PR #203).** #200 and #202 were stacked PRs, each **based on the branch below rather than main** — so merging them landed their commits in the intermediate branches, not main. GitHub marked them "merged," but only #199/#201 actually reached main; the Learnings loop + fresh-regen/dedup code was absent (main still had the old `MenuLearningsSection`, no `insertNew`). PR #203 3-way-merged the full stacked branch onto main, **preserving ADR-0038 Amd 4** (the raw diff's −37 was an artifact of the branch predating #201). Lesson: **base stacked PRs on main, or confirm the merge commit is an ancestor of main before treating it as shipped** ([[verify-local-fix-reached-merge]]). Stale branches `codex/recipe-learnings-full-loop` + `codex/adr-0041-s1-playbook-section-toolbar` to be deleted.

---
## Dogfood polish batch — yield-fraction scaling · scalar→30 · grocery aisle picker · Workbench→Reference

**✅ Merged to main — yes-chef PR [#198](https://github.com/jonphillips/yes-chef/pull/198), 2026-07-17. App-build gate green (`generic/platform=iOS` → BUILD SUCCEEDED) + `check-drift` green (SwiftLint; 358 package tests). Device pass owed (Jon).** App-layer + Core; **no schema / migration** (every field/table/placement pre-existed). From Jon's 2026-07-16 device pass — four unrelated small fixes in one PR.

1. **Vulgar/mixed-fraction yield scaling (Core).** The fraction/mixed-number parse was extracted from `IngredientParser` into a shared Core helper both parsers call, and a pure `YesChefPackage` function scales the leading quantity **in place**, preserving trailing unit words and ranges ("2½ cups" → "5 cups"; "4–6 servings" → "8–12 servings"). Also kept the `ServingParser` Double fix. Fixes existing recipes with **no migration** (stored `Recipe.servings` stays nil).
2. **Scale multiplier range 10 → 30 (app).** One shared `maximumWholeMultiplier` now drives both the wheel `ForEach` and `ScaleFraction.nearestSelection`, so a >10× scale no longer snaps back on reopen; covers recipe / menu-item / meal-plan via `ScaleContext`.
3. **Grocery aisle → Picker (app).** The free-text Aisle field became a picker over `GroceryStoreArea.canonicalAreas`, preserving any existing non-canonical value as a selectable custom row.
4. **Workbench "Archive All candidates" → "Move to Reference" (Core + app).** Curated-out candidates now land as Reference (`setLibraryPlacement(.reference…)`) instead of archived; candidate links still cleared; button / case / confirmation copy renamed. Replaces Archive (Jon's call — not both). Note-only candidates skip, as before.

---
## ADR-0039 — Amendment 2 / Slice D + Amendment 3, menu adopts the Playbook column (permanent; tools slide over)

**✅ architect-approved + Jon device-confirmed + app-build-gate green (architect local `generic/platform=iOS` → BUILD SUCCEEDED) — 2026-07-16.** yes-chef PR [#197](https://github.com/jonphillips/yes-chef/pull/197). **This closes ADR-0039 Amendment 2 — all four slices (A–D) shipped — under the Amendment 3 correction.** **App-layer only — no schema / migration** (view composition + local `@AppStorage`; prep-plan/learnings/handoff data all pre-existed).

**The menu now shares the recipe's grammar.** `MenuDetailReader` splits (≥ 820pt) into **Body** = `MenuDetailHeader` + `MenuExternalProjectField` + `MenuDishList` + `MenuPlacementList` (always in view) and a **Playbook companion** = `MenuPrepPlanSection` + `MenuLearningsSection` (the ChatGPT handoff rides inside the prep-plan section). `MenuWideColumnLayout` does the 2-region width math (Body 0.30 floor + detent-driven Playbook remainder) over the *shared* `RecipePlaybookColumnDetent`/`RecipePlaybookResizeHandle`/`RecipeWideColumnMetrics` — no fork. Compact is one scroll, Body then Playbook, unchanged.

**Amendment 3 corrections (the reason this isn't a plain "Slice D").** Slice D first shipped as a toggle build (PR #197's first commit) whose device pass exposed two structural problems: two look-alike trailing-sidebar toolbar buttons (Show/Hide Playbook vs. Browse Recipes), and `.inspector` **pushing** rather than overlaying — opening Browse squeezed Body + Playbook + Browse into three cramped columns. [ADR-0039 Amendment 3](decisions/ADR-0039-playbook-column-thinking-vs-doing.md#amendment-3--2026-07-16-the-menu-playbook-is-permanent-and-transient-tools-go-over-it-not-beside-it) resolved both:

- **D6 — the menu Playbook is permanent.** No toggle, no `isPlaybookColumnVisible`; always co-visible on wide, sized only by drag + the Comfortable/Wide detents. The recipe keeps its toggle (deliberate asymmetry — the Dishes body gains nothing from full width, the recipe body can). Threshold raised 640→**820** (`MenuPlaybookColumnMetrics.twoColumnThreshold`) so a ~700pt multitasking pane falls back to compact instead of a cramped permanent two-column.
- **D6 — width persists per-menu; service date seeds only the first open.** Replaced the single global detent key with a `[menuID: detent]` JSON map in one `@AppStorage`; `currentPlaybookDetent` reads `map[menu.id] ?? (isServiceDateTodayOrPast ? .comfortable : .wide)`, so the service date sets the initial detent only until the first drag on that menu, after which the stored width wins and the heuristic never overrides it. This resolves the global-vs-per-menu sub-decision the Slice D dispatch had flagged (first-review finding #1).
- **D7 — transient tools slide *over*, not *in*.** Browse Recipes + Ask moved off `.inspector` onto a trailing `.overlay` above a stable Body + Playbook layout (`.move(edge: .trailing)` transition; `menuToolContent` builder shared by the overlay and the compact `.sheet`). The reader underneath never reflows. The recipe's Ask stays on `.inspector` for now (noted follow-up — no Browse collision there).
- VoiceOver label parameterized on the shared handle (menu reads "Dishes and Playbook split").

**Scrim removed to keep the body interactive (Jon's edit, `ac7629f`).** The overlay initially had a tap-to-dismiss scrim; Jon removed it because the whole point of the *over* presentation is to let recipes be **dragged from Browse into a meal**. Discovery during review: that pipeline is **already wired end-to-end** — `MenuDishDayList` carries `.dropDestination(for: MenuDraggedRecipe.self) { model.addRecipesToMenu(…) }` and the browser rows are `.draggable(MenuDraggedRecipe(…))` — so removing the scrim unblocks a working drag-recipe-into-a-day flow, not just a future one. Dismissal is now via the toolbar toggle (or selecting a recipe).

**Architect review (PR #197) — approve; build green; device-confirmed.** Amendment 3 landed faithfully; the per-menu detent + service-date seed resolves first-review finding #1 cleanly; the scrim removal is correct and better-motivated than "future." Three minor follow-ups Jon dispatched to Codex, **folded into this same PR**: (2) gate the trailing overlay on `usesToolOverlay` (not just `toolOverlay != nil`) so a size-class flip to compact can't strand a 380pt panel; (3) drop the redundant `.regularMaterial` under the opaque browser panel, add a leading separator/shadow so it reads as floating; (4) delete the now-unused `MenuDetailInspector.title` (only the removed scrim referenced it). Non-blocking, cosmetic/robustness only — no behavior-affecting logic. First-review findings #2 (compact prep-plan expansion) left as a device-pass knob; #3 (VoiceOver label) fixed in the Amendment 3 pass.

**Follow-on left on the board (Jon's to pick).** Drag-recipe-into-a-meal is now functional; the remaining work is confirming/polishing the E2E interaction and any meal-planner integration — queued in CURRENT_HANDOFF Ready Efforts, not inferred as Next Up.

---
## ADR-0039 — Amendment 2, Playbook Peek detent dropped (two detents)

**✅ architect-approved + app-build-gate green (architect local `generic/platform=iOS` → BUILD SUCCEEDED) + Jon device-confirmed (handle cycles Comfortable ↔ Wide, no sliver, toolbar Hide restores) — 2026-07-16.** yes-chef PR [#196](https://github.com/jonphillips/yes-chef/pull/196). A small follow-up off Slice C's device pass — **not** its own Amendment slice. **App-layer only — no schema / migration** (view + local `@AppStorage` state; **D = menu adopts the Playbook column, still parked**).

**Why Peek went.** Slice C's device pass surfaced a pre-existing Slice B detent-math gap: **Peek** = ⅓ of an already-small remaining width, with no content floor mirroring the Directions floor, so at its minimum it rendered a degenerate sliver (the Playbook header wrapped one char per line, Ask clipped). The resize handle was deliberately built *not* to hide the column (drag-to-zero is "fiddly and easy to do by accident"); the **toolbar Show/Hide button is the honest hide**, so a near-hide detent was both redundant and broken. Two detents + binary toolbar-hide is the Xcode/VS Code grammar without the broken corner.

**The change (2 lines, one file).** `case peek` removed from `RecipePlaybookColumnDetent` (`RecipePlaybookColumnLayout.swift`); the enum is now `comfortable · wide`, both `switch` bodies updated, and the resize-handle VoiceOver hint changed to "Cycles between comfortable and wide Playbook widths." No width constants touched: `playbookWidth(for:)` derives its fraction from `(index+1)/count`, so with two cases it auto-rebalances — **Comfortable → ½ max, Wide → full max** — and `next`/`previous`/`nearestDetent` keep working over `allCases`.

**No migration.** `currentPlaybookDetent`'s getter (`RecipeDetailView.swift:650`) reads through `RecipePlaybookColumnDetent(rawValue:) ?? .comfortable`, so any device with `"peek"` persisted from Slice B falls back to Comfortable on next open — confirmed intact. Grep found zero remaining `.peek` / `"peek"` references in Swift.

**Architect review (PR #196) — approve, no on-branch code changes.** Enum-count-driven math self-adjusts correctly; the persisted-`"peek"` fallback holds; VoiceOver hint updated; clean removal. Two notes: (1) **non-blocking doc nit fixed in this PR** — ADR-0039 §D4's detent example still listed "(e.g. Peek / Comfortable / Wide)"; struck to `(Comfortable / Wide)` with an Amendment 2 note. (2) **Pre-existing, not this PR** — the `accessibilityAdjustableAction` wraps around (increment from Wide → Comfortable) rather than clamping at ends; benign with two detents, left for parity with the chat-workspace precedent. **Device-pass watch (Jon):** Comfortable is now ½-max (was ⅓-max under three detents, i.e. it *grows*), so confirm it still clears the Playbook-header content floor on the smallest target; handle cycles only Comfortable ↔ Wide with no sliver reachable; toolbar Hide fully collapses and restores the last detent.

---
## ADR-0039 — Amendment 2 / Slice C, recipe header nests beside Ingredients

**✅ architect-approved + app-build-gate green (architect local `generic/platform=iOS` → BUILD SUCCEEDED) + Jon device-confirmed running (3 detents exercised on `iPad Pro 13-inch (M5)`, screenshots) — 2026-07-16.** yes-chef PR [#195](https://github.com/jonphillips/yes-chef/pull/195) (Codex branch/PR title says "A2 S3" — same slice; the doc series calls it **Slice C**).
[ADR-0039 Amendment 2](decisions/ADR-0039-playbook-column-thinking-vs-doing.md#amendment-2--2026-07-16-the-playbook-becomes-a-persistent-enrichment-column): **third of four** Amendment 2 slices — corrects Slice A's full-width header band to the real Paprika **column-scoped** composition. **App-layer only — no schema / migration** (pure view composition; Slice B's `@AppStorage` keys untouched). **D = menu adopts the column, still parked.**

**The full-width band + divider are gone.** `RecipeReaderView.body`'s two-column branch is now just the three columns filling full height (`.frame(width:height:alignment: .topLeading)`); the outer `VStack`/`header`/`metadata`/`Divider` strip that spent the whole recipe's top edge on identity is deleted. Ingredients and Playbook both rise to the top edge — the vertical reclaim the band only half-delivered.

**Header nests at the top of the Directions column only.** A new `wideColumnHeader(_:)` puts `header` + a 96 pt cover photo side-by-side, stacked above `metadata(_:showsPhoto: false)` + `directionsColumn` inside the Directions `ScrollView` — spanning Directions' width and scrolling with it. Directions-only (not Directions + Playbook) keeps identity + method together and lets the Playbook stay **top-anchored** (Ask · Make-ahead · Notes rise to the ceiling) — Jon's chosen fork. `metadata` gained a `showsPhoto` flag so the compact reader keeps its 72 pt band thumbnail (`compactThumbnailSideLength`) while the wide header owns the photo (`wideColumnPhotoSideLength` = 96, a **deliberate** grow past Paprika's stamp, recorded so it doesn't read as drift).

**Ingredients cheated narrower; the three columns still reconcile.** `RecipeWideColumnLayout` split its single `contentColumnFraction` (⅓) into `ingredientsColumnFraction` = **0.27** and `directionsMinimumFraction` = **0.30**. The narrower Ingredients widens both the Directions floor and the Playbook max; the math reconciles exactly (at Wide, Directions lands back on `0.30w`).

**Slice B review finding closed here (same region).** The Show/Hide Playbook toolbar toggle moved out of the parent's `isSplitEnabled` gate into the reader's own `proxy.size.width >= twoColumnThreshold` gate — so the button now appears **iff** the three-column layout actually renders, killing the dead-control state on a sidebar-narrowed pane. `isSplitEnabled` remains used elsewhere (not dead).

**Architect review (PR #195) — approve, no on-branch changes required.** Composition matches the ADR intent exactly (confirmed against on-device screenshots); layout math reconciles precisely; the toolbar re-gate is a genuine improvement, not just a relocation. One **non-blocking** nit: `metadata(showsPhoto: false)`'s `ViewThatFits` collapses to two near-identical candidates on the wide path (the `VStack` branch is dead there) — cosmetic, deferred. **Device-pass discovery → next slice:** the **Peek** detent renders a degenerate sliver at its minimum width ("Hand off to ChatGPT" wraps one char per line, Ask clipped) — a pre-existing Slice B detent-math gap (Peek = ⅓ of an already-small max, with no content floor mirroring the Directions floor), surfaced now, **not caused by Slice C**. Jon's call: **drop Peek to two detents** (see CURRENT_HANDOFF Next Up).

---
## ADR-0039 — Amendment 2 / Slice B, resizable recipe Playbook column

**✅ architect-approved + app-build-gate green (architect local `generic/platform=iOS` → BUILD SUCCEEDED) — 2026-07-16. Jon device-pass pending.** yes-chef PR [#194](https://github.com/jonphillips/yes-chef/pull/194).
[ADR-0039 Amendment 2](decisions/ADR-0039-playbook-column-thinking-vs-doing.md#amendment-2--2026-07-16-the-playbook-becomes-a-persistent-enrichment-column): **second of what is now four** Amendment 2 slices — the arc grew from three when the header-nesting correction was inserted. A (header band) shipped; **C = the header nests beside Ingredients (Paprika composition), next**; **D = menu adopts the column, parked** (D is the *old* "Slice C," renumbered). **App-layer only — no schema / migration** (Playbook width persists via local `@AppStorage`, not synced — it's view state).

**Wide iPad is now three co-visible columns, no mode.** `wideRecipeSection`'s Cook/Plan segmented toggle is gone; a new `wideRecipeColumns(in:)` lays out Ingredients + Directions + Playbook simultaneously. `WideSection`/`wideSection` deleted as dead. Directions never leaves the screen to plan — Amendment 1's wide toggle is reversed.

**Playbook width — show/hide + drag-snap + persist.** New `RecipePlaybookColumnLayout.swift`: a `RecipeWideColumnLayout` value type does the width math (Ingredients pinned at ⅓, a matching ⅓ Directions floor, three detents — **Peek / Comfortable / Wide** — evenly dividing only the *remaining* width, so no device-point widths are baked in), a `RecipePlaybookResizeHandle` (draggable + VoiceOver-adjustable, tap-to-cycle), and a `RecipePlaybookColumnDetent` enum. Visibility + detent persist in local `@AppStorage`; a toolbar **Show/Hide Playbook** button preserves the last detent. Structurally a faithful clone of the shipped `RecipeChatWorkspace` resize affordance (same `@GestureState` drag + `.simultaneousGesture`, `proposed…Width`/`nearestDetent`, `.snappy(0.22)`, wrapping detents) — deliberate reuse, the two resize surfaces stay consistent.

**Compact untouched** — the segmented `Ingredients · Directions · Playbook` picker stays, one region at a time. Ask + Browse remain `.inspector` slide-overs over the top.

**Architect review (PR #194) — one coherence finding, carried into Slice C (not fixed on-branch).** The Show/Hide Playbook toolbar button is gated on `isSplitEnabled` (`RecipeDetailView.swift:137` — iPad + non-compact size class) while the three-column layout is gated on `isTwoColumn` (`RecipeDetailView.swift:267` — detail-pane width ≥ 640). On an iPad whose detail pane is < 640 (sidebar showing), the button appears but the Playbook column doesn't render — toggling is a **dead control**, and that's a common everyday state, not an edge case. **Folded into Slice C's task list** (which rebuilds that exact wide-layout + toolbar region): re-gate the toggle on the real two-column width signal. Two non-blocking device-pass notes: the Directions readability floor is a pure `w/3` fraction (watch it at the narrowest Directions width on 13"); the detents wrap (Wide→Peek), consistent with the chat-workspace precedent, left for parity. Architect local build → **BUILD SUCCEEDED**.

---
## ADR-0039 — Amendment 2 / Slice A, compact recipe header + Start Cooking burial

**✅ architect-approved + app-build-gate green (architect local `generic/platform=iOS` → BUILD SUCCEEDED, run against the post-review fix tip) — 2026-07-16. Jon device-pass pending.** yes-chef PR [#193](https://github.com/jonphillips/yes-chef/pull/193).
[ADR-0039 Amendment 2](decisions/ADR-0039-playbook-column-thinking-vs-doing.md#amendment-2--2026-07-16-the-playbook-becomes-a-persistent-enrichment-column): first of **three** Amendment 2 slices (B = resizable Playbook column + recipe adoption; C = menu adopts it — both still ahead). **App-layer only — no schema / migration.**

**Recipe header compacted to a Paprika-style band.** `header(_:)` is now a tight title/subtitle/summary stack (summary `lineLimit(2)`); `metadata(_:)` is a dense stats · source · thumbnail band. The cover thumbnail dropped 112→72 pt so it no longer dictates header height (`HeaderMetrics.thumbnailSideLength`), and `SourceMetadataView` collapsed from a multi-line block to a single `lineLimit(1)` `.caption` line (displayName + one `compactDetail` field). Directions climbs up the page — the point, now that it's a co-visible column whose vertical space is precious.

**`View Original` → toolbar.** Moved out of the `metadata(_:)` stack into a `.secondaryAction` toolbar item, gated on `originalSnapshot != nil`.

**Recipe "Start Cooking" entry point removed (surgical).** Deleted `startCookingButton`, the `showsStartCookingButton` param threaded through `RecipeDetailView`/`RecipeReaderView` (and its `CookSessionView` call site), the recipe-library `cookButtonTapped` + `.cookingMode` destination, the `CookingModeView` screen, its `.sheet` in `AppDestinationPresentation`, and the `CookingModeModel`. Confirmed **zero** dangling references and the pbxproj no longer lists the deleted file. **`CookSessionView` and the Menu/Calendar "Cook these" flows are untouched** — the recipe opened that shared `TabView` with one item (the 40 pt step-by-step Jon won't use); Menu/Calendar open the *same* view with many (kept). Git is the archive ([[automation-decays-near-the-stove]]).

**Folded-in D4 fix — menu Ask toggle.** The merged D4 menu Ask already uses a toggle action for the toolbar and an ensure-open action for Regenerate, preserving a live transcript — the PR #192 finding is closed here.

**Architect review (PR #193) — two follow-ups, both fixed on-branch.** (1) The new `compactDetail` silently dropped `sourceNotes` from every reader surface (it stayed editable + searchable, so it became write-only). Restored as a capped secondary caption (`.caption`, `lineLimit(2)`) below the metadata band — a **temporary** read surface so Jon can dogfood and decide its fate; the ADR trajectory still points source notes into the Playbook ([[decompose-notes-into-typed-homes]]), not this line. (2) The metadata `ViewThatFits` narrow fallback omitted the thumbnail, which is the **sole** `isPhotoGalleryPresented` entry point — so on narrow width the recipe's photos went unreachable. Fixed by adding the 72 pt thumbnail to the fallback branch too. Architect local build (post-fix) → **BUILD SUCCEEDED**.

---
## ADR-0039 — D4 / OQ3, the Menu launcher mode

**✅ architect-approved + app-build-gate green (local `generic/platform=iOS` → BUILD SUCCEEDED; `MenuServiceDateTests` green) — 2026-07-16. Jon device approved.** yes-chef PR [#192](https://github.com/jonphillips/yes-chef/pull/192).
[ADR-0039 §D4 + OQ3](decisions/ADR-0039-playbook-column-thinking-vs-doing.md): a menu is a *thinking* artifact you don't execute (you execute its recipes), so its planning→launcher shift is **temporal, not spatial** — keyed off the **service date** ([[mode-trigger-date-vs-toggle]]). **App-layer + one Core helper — no schema / migration.**

**Date-driven mode, one pure Core helper.** New `MenuServiceDate.hasArrived(placements:now:calendar:)` (`YesChefCore`) — the earliest placement `startDate` compared to `now` at **day** granularity — is the single mode switch, unit-tested (`MenuServiceDateTests`: empty / future / later-today / mixed-past). Keeping the date logic in Core (not the App layer) is what let it be tested at all.

**Planning vs. launcher, over time.** *Far from service:* the **prep plan is foregrounded and expanded**, the dish list sits at the bottom. *On/after the service date:* the **dish list jumps to the top with all days collapsed** (`isInitiallyExpanded: false`) and the **prep plan collapses** — day-of, the job is *get me into the right recipe fast*. Both `MenuDishList` day headers and the `MenuPrepPlanSection` header gain **chevron toggles** with accessibility labels; OQ3's collapsible days land here.

**The menu's standing AI third column is deleted.** The always-on `ChatWorkspaceSplit` chat pane is removed from the menu detail; the reader is now a single pane. Ask + Browse Recipes become a **unified `.inspector`** (a private `MenuDetailInspector` enum, `recipeBrowser | chat`, with an `Optional.isPresented` binding) on wide iPad; Ask stays a `.sheet` on compact — echoing the recipe-side D3 demotion.

**Architect review (PR #192) — Ask-toggle finding fixed in Amendment 2 Slice A (PR #193)..** The menu's `chatButtonTapped` (`MenuViews.swift:317`) is a pure setter: on wide iPad, re-tapping the live **Ask** toolbar trigger rebuilds the `RecipeChatModel` and **silently discards the in-progress transcript**, with **no toolbar close path** — the *identical* defect the D3 follow-on (PR #191, entry above) just fixed on the recipe side, where `RecipeModels.swift:915` now toggles and its comment even points here ("See the Menu recipe-browser toggle for the pattern"). Fix: make the menu Ask **toggle closed** on re-tap, mirroring the sibling `recipeBrowserButtonTapped` — but `chatButtonTapped` doubles as `regeneratePrepPlan`, so split the intents (a toggling Ask path + an ensure-open path for Regenerate that doesn't rebuild an existing chat). Two minor notes, non-blocking: the menu Ask trigger lacks the recipe's active-state ring, and `dayAccessibilityTitle` duplicates `dayTitle`'s date formatting. Architect local build (pre-fix) → **BUILD SUCCEEDED**.

## ADR-0039 — D3 follow-on, the true "Ask" slide-over + Playbook-header polish

**✅ architect-approved + app-build-gate green (local `generic/platform=iOS` → BUILD SUCCEEDED) + Jon
device-pass done — 2026-07-15. Merge pending.** yes-chef PR
[#191](https://github.com/jonphillips/yes-chef/pull/191).
[ADR-0039 §D3 + Amendment 1](decisions/ADR-0039-playbook-column-thinking-vs-doing.md): delivers the *true*
slide-over Amendment 1 specified ("a true slide-over, decoupled from any resize bar") to replace D3's reused
modal sheet. **App-layer only — no schema / migration.**

**Ask is now a native trailing inspector on wide iPad**, a non-modal companion that doesn't dim/steal the
reader; it reuses the established Menu recipe-browser inspector width range (320 / 380 / 480 pt). **Compact keeps
the plain sheet** (no room for a side companion). The dual `.inspector`/`.sheet` with mirrored `.constant`
bindings migrates an open chat inspector↔sheet across size-class changes without losing `destination`.

**Architect review (PR #191) fixes — one real interaction bug + polish.** The non-modal companion left the
Playbook-header **Ask** trigger live beside the open panel, but `chatButtonTapped` was a pure setter: re-tapping
rebuilt the `RecipeChatModel` and **silently discarded the scratch transcript**, and there was **no close path**
(the panel has no dismiss control and `@Environment(\.dismiss)` can't close an inspector). Fixed by making
`chatButtonTapped` **toggle** (re-tap closes), mirroring the Menu recipe-browser toggle
(`RecipeModels.swift:915`). Both folded-in cosmetic notes landed (PasteButton `.bordered`; redundant in-view
"Playbook" title removed). Architect local build → **BUILD SUCCEEDED**.

**Jon UI request, same slice.** The Playbook header now **separates the two AI tiers**: the ChatGPT copy/paste
round-trip (Hand off + Paste) clusters at the leading edge, **Ask sits apart on the trailing edge**, out of that
workflow. While its panel is open, Ask carries a **3 pt tint-colored active ring** so the trigger reads as lit.

---
## ADR-0039 — D3, the "Ask" chat demotion + retiring the wide chat split

**✅ architect-approved + app-build-gate green (local `generic/platform=iOS` → BUILD SUCCEEDED) — 2026-07-15.
Jon device-pass done, merged.** yes-chef PR [#190](https://github.com/jonphillips/yes-chef/pull/190).
[ADR-0039 §D3 + Amendment 1](decisions/ADR-0039-playbook-column-thinking-vs-doing.md): collapses the
transitional AI-in-two-places state D1/D2 left behind. The always-on `ChatWorkspaceSplit` + draggable
`ChatWorkspaceDivider` is **removed from the recipe detail** (still live in Menu/Calendar/Workbench); the
Playbook header now **owns both tiers** — **Hand off to ChatGPT** (`.borderedProminent`, primary) and **Ask**
(`.bordered`, secondary), plus the return-paste `PasteButton`. The toolbar "Chat" entry point and the Cook/Plan
detent-toggle logic (`wideSectionChanged`, `chatWorkspaceDetentRaw`) are deleted. **App-layer only — no schema /
migration.**

**Ask reuses the existing recipe-scoped `.sheet` for now** (`model.chatButtonTapped` →
`.sheet(item: $model.destination.chat)`); the **true slide-over presentation** Amendment 1 specifies ("a true
slide-over, decoupled from any resize bar") is a **deliberate follow-on**, not a miss — see the D3-follow-on
Next Up. D3 delivers the *demotion + divider retirement*; the slide-over *styling* is the next slice.

**Architect review (PR #190) — verified clean.** No orphaned code: `ChatWorkspaceSplit`/`ChatWorkspaceDetent`
stay in use across Menu/Calendar/Workbench. The Focus toolbar button is untouched — it drives
`NavigationSplitView` column visibility (`AppMainLayout.swift`), not the retired chat split. Confining
Ask/handoff to the Playbook is **per-spec** ("the Playbook column header owns both"), not a reachability
regression. Two cosmetic notes (PasteButton styling; "Playbook" vs "Plan" heading) were **folded forward** into
the D3-follow-on slice rather than blocking merge. Architect local build → **BUILD SUCCEEDED**.

---
## ADR-0039 — D1/D2 + OQ1/OQ2, the Recipe Playbook region

**✅ architect-approved + app-build-gate green + Jon device-pass done — 2026-07-15. Merge pending.** yes-chef
PR [#189](https://github.com/jonphillips/yes-chef/pull/189).
[ADR-0039 §D1/D2, Amendment 1](decisions/ADR-0039-playbook-column-thinking-vs-doing.md): the anchor UI slice —
the recipe gains a **third peer region, Ingredients · Directions · Playbook**, and the "thinking" content leaves
the cook body. **App-layer only — no schema / migration; `Recipe.makeAhead` (`String?`) stays canonical.** New
file `YesChefApp/RecipePlaybookView.swift`.

**Both device renderings (Amendment 1).** Compact adds a **third `.segmented` case** (`Ingredients · Directions
· Playbook`). Wide iPad **pins Ingredients as a ⅓ anchor** and a **Cook / Plan toggle** swaps the other ⅔
between Directions (Cook) and Playbook (Plan), setting preset `ChatWorkspaceDetent` detents (Cook → `readerOnly`,
Plan → `balanced`).

**Full content move (OQ1 — body shows nothing).** Make-ahead, Notes (reader feedback + other `RecipeNote`),
Chef It Up, and Serve With cut from `directionsColumn` into the Playbook; each section is **collapsible** with a
**filled/empty header indicator**. Stays in Directions: Instructions, the active-variation method note, Workbench
candidate links. All existing edit/clear actions and the canonical make-ahead store preserved.

**Architect app-build gate earned its keep — four App-target compile errors that `check-drift.sh` structurally
cannot see** (it compiles only `YesChefPackage`; all four were pure SwiftUI in `YesChefApp/`). Round 1: a
`let … = nil` binding excluded from the memberwise init, and `.padding()/.frame()` chained onto a bare `switch`.
Round 2 (surfaced only by the local `generic/platform=iOS` build): a `.tint`/`.secondary` ShapeStyle ternary
needing `AnyShapeStyle`, and a non-`@escaping` `@ViewBuilder` closure captured by `DisclosureGroup`. The last two
fixed + committed by the architect (a3e5011); build → **BUILD SUCCEEDED**. Reinforces
[[codex-build-excuse-reproduce]]. Codex's cited `swiftc -parse` cannot catch any of these (parse skips
type-checking).

**Intentional intermediate state (device-confirmed).** The `ChatWorkspaceDivider` / in-app chat column is **not**
retired here — deferred to **D3**. So on wide iPad, Plan re-expands the old chat column via the `balanced` detent,
and the AI appears in two places at once (the standing column + the Playbook's Copy-Prompt handoff). That
doubling is transitional and collapses in D3.

---
## ADR-0039 — D5, prep plans emit tasks, not choreography

**✅ architect-approved + package tests green (18/18) — 2026-07-15. Jon device-pass + merge pending.** yes-chef
PR [#188](https://github.com/jonphillips/yes-chef/pull/188).
[ADR-0039 §D5](decisions/ADR-0039-playbook-column-thinking-vs-doing.md): the smallest-first opening slice of
the Playbook milestone — both prep-plan prompt contracts now emit **separable, atomic, context-free tasks** and
are explicitly forbidden from **choreography** (interleaving recipe instructions, coordinating concurrent
cooking, or turning the plan into a merged mega-recipe). "The recipes hold the cooking." **Core-only — no app /
schema / migration.**

**Both contracts constrained.** `MenuPrepPlan.instructions` (`MenuPrepPlan.swift:293`) and the sibling
`MealPlanMakeAheadStrategy.instructions` (`MealPlanMakeAheadStrategy.swift:183`) both drop the invitation to
"invent grounded sequencing" and gain the tasks-never-choreography constraint plus grounded example tasks
("Salt the chicken Wednesday", "Pull the beef to temp at 4"). Existing JSON shapes
(`session`/`task`/`serves`/`sourceDish`) and the compose-from-stored-Make-Ahead behavior are preserved; the
horizon-band session grouping (temporal bucketing, not step interleaving) stays. Realizes
[[automation-decays-near-the-stove]].

**Tested in Core.** Both package suites assert the positive constraint (`separable, atomic, context-free
tasks`, `Do not generate choreography`, `The recipes hold the cooking`) and the menu suite pins the negative
(`invent grounded sequencing` == false). `swift test` MenuPrepPlanTests + MealPlanMakeAheadStrategyTests, 18
passed. Prompt-only steer — no schema/storage change, so a phrasing that underperforms is a regeneration away
from reversible.

---
## ADR-0040 — Editable-at-the-grain, S3 (surface menu edit outcomes / lossless-or-**loud**)

**✅ architect-approved + app-build-gate green — 2026-07-15. Jon device-pass + merge pending.** yes-chef PR
[#187](https://github.com/jonphillips/yes-chef/pull/187).
[ADR-0040 S3](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md): the **silent-success** half of the
lossless-or-loud pass — every direct menu edit path now ends in a visible outcome. **App-layer only — no core /
schema / migration.**

**Direct edits confirm.** Prep-step create/edit/delete/reorder and learning edit/delete now post a transient
success toast via the shared `AppToastCenter` (threaded into `MenuLibraryModel` + `MenuDetailModel`); failures
keep the standard error surface (`MenuDetailModel+PrepPlanEditing.swift`).

**No-ops go loud.** A reorder that can't move (`PrepPlanStepRepository.reorder` → `false`) now raises "already at
the beginning/end of the plan" instead of silently accepting it; a blank learning edit raises an error instead
of silently returning; empty/whitespace handoff-result and recipe-URL pastes (`HandoffInAppTransport`,
`RecipeCaptureModel.pastedText`) become visible errors instead of `guard let … else { return }` invisibility —
the S3a device-pass failure mode where "did nothing," "worked invisibly," and "wrong build" were
indistinguishable.

**Build note.** Codex's one generic-build attempt caught a real `toastCenter` `private`-protection error, which
was fixed; the architect re-ran the generic app build locally (`generic/platform=iOS`, `BUILD SUCCEEDED`, 0
errors) as the approval gate.

---
## ADR-0038 — External-LLM handoff, S3c (in-app door) + Amendment 2

**✅ DONE — architect-approved + Jon device-passed 2026-07-15.** yes-chef PR
[#186](https://github.com/jonphillips/yes-chef/pull/186).
[ADR-0038 Amendment 2](decisions/ADR-0038-external-llm-handoff.md): Recipe + MealPlan get an in-app
**Copy-Prompt / Paste-Result** door (discuss-first) as the **primary** path; the App Intent stays the
hands-free bonus. **App-layer only — no core / schema / migration.**

**In-app transport (`HandoffInAppTransport`).** Copy emits the S3b tokenized prompt (`YC-HANDOFF:` + the
source's `DeliverableFormat`) via shared `HandoffAppOperations.export`; Paste routes through
`AIHandoffIntentImport.stageReview` → the review sheet (editable-at-grain, Learnings ride along). Menu's manual
Copy/Paste moved onto the same review-routed transport, retiring its direct-write paste path. Controls live on
a **persistent Make-ahead header** in the recipe Playbook column (a first ADR-0039 brick, fixing the
`PasteButton`-in-overflow-menu bug) and on the meal-plan day header; custom copy icon
(`sparkles.square.filled.on.square`), `PasteButton` kept for paste (privacy, no per-paste prompt).

**Unmatched-result guard.** The in-app paste checks the pasted result against the surface it was tapped on: a
missing token, a handoff not found locally (incl. cross-device, since `AIHandoff` is device-local), or a token
resolving to a **different** source each raise a **Review Anyway / Cancel** alert. Proceed stages against the
current surface via `stageReviewForKnownSource` (mints a device-local handoff + stages atomically in one
write). Restores the token-less fallback **safely** — never a direct write, always the review sheet, with an
explicit "check this" gate; also makes a cross-device return route to the same synced recipe/day.

**App Shortcuts.** Export/Import registered as `AppShortcut`s for Spotlight / Siri / Action Button discovery;
the intents refactored onto the shared `HandoffAppOperations`. Follow-up commits `a4ea289` (controls fix) +
`da07b47` (unmatched guard) landed the device-pass findings.

---
## ADR-0038 — External-LLM handoff, S3b (Recipe + Meal Plan)

**✅ DONE — architect-approved; build fix landed as `3999bf2`. Jon device pass: _pending_ — flip this line to
`+ Jon device-passed 2026-07-14` on pass.** yes-chef PR
[#185](https://github.com/jonphillips/yes-chef/pull/185).
[ADR-0038](decisions/ADR-0038-external-llm-handoff.md): the two-part return contract — proven on **Menu only**
because Menu's context serializer already existed (S3a + ADR-0040 S1/S2) — now covers **Recipe** and **Meal
Plan**. It **inherits** editable-at-grain rather than adding new BLOBs ([[editable-at-the-grain-stored]]).

**Context builders (Core, `AIHandoffContext.swift`).** `RecipeHandoffContext` and `MealPlanHandoffContext` on
the `MenuChatContext` pattern — shared frontier character budget, full recipe methods, uncapped ingredients
within budget, intro prompts tuned from `tasteProfile` / `makeAheadPrepPlan` AI settings, asking for
paste-ready **review text, not JSON**. `AIHandoffToken.DeliverableFormat` (`menuPrepPlan` / `recipeMakeAhead` /
`mealPlanMakeAheadStrategy`) shapes the export prompt per source; the export intent passes the right one
(default stays `menuPrepPlan`).

**Generalized return routing.** `AIHandoffReview` enum + `AIHandoffIntentImport.stageReview` dispatch by
`sourceType`; `AIHandoffReturn.plainText(from:)` splits deliverable/learnings for the non-Menu sources.
`HandoffReviewCoordinator` routes source-specific review items and reusable, **source-typed** `Learning` rows
off the same S3a machinery — the reason the handoff is worth doing on a source with no structured deliverable
field at all.

**Commit shape per source ([[chat-verb-commit-shapes]]).** Recipe → `Recipe.makeAhead` (verbatim prose at its
own grain), via a distinct **local-only** `recipeMakeAhead` handoff task — **no synced table or column, no
migration**. Meal Plan → a day-scoped make-ahead strategy through the existing
`MealCalendarRepository.addMakeAheadStrategyNote` (PR #91), no new synced schema either. **No additions to the
prod-schema promotion list.**

**Lossless-or-loud, at the boundary not just the UI (ADR-0040 D3).** `MealPlanMakeAheadStrategy
.parsingEditableReviewText` returns `unparsedLines`; the review sheet **surfaces** them ("Couldn't parse — fix
or remove these lines before saving") and `commitMealPlanMakeAhead` **re-parses and hard-rejects** any unparsed
line (`unparsedStrategyText`) before writing. Human edits are never silently dropped.

**Meal-plan Learnings hand-cascade** on source-item delete (`LearningRepository.deleteAll` in
`MealCalendarRepository.delete`) — no orphaned synced ghosts. (Menu already did; recipe learnings live on an
archive-not-delete source.)

**Tests.** `AIHandoffRecipeMealPlanTests` — prompts, full meal-plan context, Recipe staging, Meal Plan staging,
visible unparsed lines. Full `AIHandoffTests` suite green (15).

**Review finding, fixed post-push (`3999bf2`).** The app target **did not compile** — `HandoffIntents.swift`
used `date: .full`, invalid for `Date.FormatStyle.DateStyle` (valid: `.omitted/.numeric/.abbreviated/.long/
.complete`; `.full` is old `DateFormatter.Style` only). Codex's package `swift build` + tests were green and
its own generic app build **SIGTERM'd (exit 143, "CoreSimulator unavailable")** — the **third** PR (after #183,
#184) to slip an uncompiled app target through on that excuse. Architect-caught by running the generic build
locally (exit 65, real compile error); one-line fix `.full → .complete`.

**Process fix (real this time).** The #184 "just mandate the generic build" fix did not hold — Codex **can't
execute** that build (no working CoreSimulator subsystem / cold-build timeout → SIGTERM). The Verification
Pattern in `CURRENT_HANDOFF.md` now makes the app-target build the **architect's gate**, treats a green package
build as *not* evidence the app compiles, and adds the corollary: keep pure formatting/serialization logic in
`YesChefPackage`, not the App layer (the `.full` call belonged in `MealPlanHandoffContext` in Core, where the
package build would have caught it). See [[codex-build-excuse-reproduce]].

**Dogfood finding → [Amendment 2](decisions/ADR-0038-external-llm-handoff.md) + queued S3c.** The recipe/
meal-plan handoffs shipped **intent-only** — no in-app door — so the sole entry point is a hand-built Shortcut
running the *Immediate* autopilot, which discards the discussion that is the point of a make-ahead hand-off.
Amendment 2 makes an **in-app Copy-Prompt / Paste-Result** affordance (discuss-first, paste routed through the
review sheet) the *primary* door for these two sources; the App Intent stays the hands-free/cross-device bonus.
Filed as **S3c** (app-layer only) in the Ready Efforts queue.

**Known edges (deferred to the ADR-0040 S3 lossless pass).** In meal-plan strategy parsing the **title (first)
line is not checked for parseability** — a mangled header silently falls back to the existing title/slot rather
than surfacing in `unparsedLines`. And an import returning **only unparseable lines with no learnings** throws
`emptyPlan`, losing those lines before they reach a review sheet. Both mirror the existing Menu path, so
neither is an S3b regression — fold into the same lossless-or-loud sweep.

---
## ADR-0040 — LLM-populated content is editable at the grain it is stored, S1 + S2 (on Menu)

**✅ DONE — architect-approved + Jon device-passed 2026-07-14.** yes-chef PR
[#184](https://github.com/jonphillips/yes-chef/pull/184).
[ADR-0040](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md): the prep plan stopped being an
**all-or-nothing BLOB** the human could only regenerate through the LLM, and the `learnings` table (ADR-0038
S3a) got a reader. Two rules proven on Menu: **store LLM output at the grain the human manipulates** (a row
with an id) and **the human never authors the wire format** (structured fields, lossless-or-loud parsing).

**S1 — the Learnings surface.** A **Learnings** section on the menu detail (`MenuLearningsSection`), this
menu's learnings newest-first, read through the existing **per-menu** `MenuDetailRequest` (no whole-library
`@Fetch` — [[sqlitedata-fetch-writer-convoy]]). Inline edit (writes `dateModified`, leaves `provenance`),
swipe-to-delete a single row via `LearningRepository.delete(id:)` — `swipeActionsContainer()` on the
`ScrollView`, the iOS 27 way to swipe outside a `List`. Also exposed the **Handoff ID** as an `@Property` on
`HandoffExport` so a Shortcut can wire Export → Import directly instead of trusting ChatGPT to echo the token
UUID.

**S2 — prep plan → step rows.** `Menu.prepPlan` BLOB migrated into a synced **`prepPlanSteps`** table
(`id`, `menuID`, `sortOrder`, `session`, `task`, `serves`, `sourceDish`) — a real child of `Menu` with a
**FK + `ON DELETE CASCADE`** (no hand-cascade; multi-FK does not block sync). `PrepPlanStepRepository` does
add / edit / delete / **reorder**; the detail section edits **fields + a session picker** (six-band vocabulary
with an `.other` free-text escape), not the `session:` / `→` wire DSL. The BLOB is retained one release as a
**frozen snapshot, not a rollback mirror** (nothing writes it). Both `learnings` and `prepPlanSteps` joined the
prod-schema promotion list; the restructure landed **before the prod cut locks the record type**.

**Silent-loss paths killed (ADR-0040 D3).** `sourceDish` is no longer re-derived by matching task prose — it
rides on row identity, so a text import with no link intentionally drops the recipe chip rather than guessing
(pinned by test + documented). The parser now routes unparseable lines to `unparsedLines` instead of
`continue`-ing them away.

**Review findings, fixed in-PR** (PR #184 review + `076eb11`). (1) App target **did not compile** and the
suite was **red** as first pushed — an if-let-shorthand typo and a stale BLOB-seeded chat-context fixture
(architect-fixed, `0bf0e81`). (2) **The Flexible band went unreachable** — `isFlexible` demanded exact picker
titles, but LLM/legacy plans carry prose; fixed with a **display-only** `PrepPlanSessionBand(matching:)`
normalizer that never rewrites the stored label. (3) **"Loud" had overshot into "refuse everything"** — one
unparsed line rejected the whole return incl. learnings, even on the reviewed path; now the review sheet
**surfaces** the bad lines ("Couldn't parse — fix or remove…") for the human to fix, while the unreviewed
direct paste still hard-throws.

**Process fix that shipped with it.** The "CoreSimulator has no runtimes" excuse that let **two** uncompiled
PRs (#183, #184) through is dead: `xcodebuild -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
compiles the app target with no simulator and no signing, and the Verification Pattern in `CURRENT_HANDOFF.md`
now mandates it.

**Deferred to the [ADR-0040 S3](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) lossless-or-loud
pass:** no save confirmation on a learning/step edit (it just appears), and "Paste Prep Plan" silently no-ops
on an empty clipboard or a missed *Allow Paste* prompt.

---
## ADR-0038 Amendment 1 — External-LLM handoff, S3a (the two-part return contract, on Menu)

**✅ DONE — architect-approved 2026-07-14. Jon device pass still owed.** yes-chef PR
[#183](https://github.com/jonphillips/yes-chef/pull/183).
[ADR-0038 Amendment 1](decisions/ADR-0038-external-llm-handoff.md): the handoff return is now
**`(Deliverable?, Learnings?)`, either may be empty** — the *reasoning* of a multi-turn session no longer dies
in ChatGPT. Proven on **Menu only** (its serializer already existed; Recipe/MealPlan are S3b).

**Prompt (both modes).** After the deliverable, the model returns a **`YC-LEARNINGS:`** marker line followed by
a bullet list of durable knowledge — a **structured list of distinct bullets, never a merged blob**
([[llm-curation-not-synthesis]]). A **learning-only return is first-class**, not an error. Bundles the
**ADR-0039 D5 prompt fix**: prep-plan bullets are **separable, atomic, context-free tasks, never choreography**
— the plan must never become a merged mega-recipe ([[automation-decays-near-the-stove]]).

**Parse — split before you parse.** `isEditablePrepPlanSessionHeader` treats any non-bullet, colon-terminated
line as a **session header**, so an unsplit `YC-LEARNINGS:` would be swallowed as a prep band and every learning
would become a prep step. `AIHandoffReturn` strips the token → **splits the body on the marker** → feeds *only*
the deliverable half to `applyingEditableReviewText` and parses the learnings half as bullets. The marker match
is **tolerant of markdown decoration and case** (`## **yc-learnings:**` splits correctly) — models bold their
headings no matter what the prompt says.

**Commit — new synced `Learning` table.** `id`, `sourceType` (reuses `AIHandoffSourceType`), `sourceID`, `text`
(plain text to start), `provenance` (`.externalHandoff`/`.inApp`), `dateCreated`, `dateModified`. Registered in
`makeSyncEngine` (the `CloudSyncTests` guard derives its expectation from the live schema, so it covered this
with no test edit). `(sourceType, sourceID)` is **polymorphic → no FK → no cascade delete**, so
`MenuRepository.deleteMenu` **hand-cascades** its learnings — orphans here would be *synced* ghosts, not
harmless local ones. **`learnings` is on the standing prod-schema promotion list.**

**Review.** `HandoffReviewSheet` now passes **two** `ChatApplyReviewItem`s — Deliverable and Learnings — each
independently editable, savable, and discardable (ADR-0024/0026).

**Review findings, fixed in-PR.** The prompt change is global, but the first pass taught only the App Intents
path to keep learnings — the **in-app paste path silently discarded every learning** and hard-errored on a
learning-only paste. `AIHandoffMenuPrepPlanImport.apply` now persists both halves and its empty-guard relaxed to
"empty deliverable **and** empty learnings = error." Also: the exact-match marker was hardened (above), the
error surface no longer says "Prep Plan" for a learnings failure, and a `UUIDGenerator`-vs-`() -> UUID` compile
error in the app target was fixed at merge — **the app target does not compile in the Codex sandbox, so
package-only green is not sufficient evidence for app-layer changes.**

**Not decided here (deliberately):** *where* learnings are displayed. Nothing reads the table yet — that is
ADR-0039 (the Playbook column) and a hard prerequisite of S3b (a read/delete surface, before the corpus grows
rows nobody can see or prune).

---
## ADR-0038 — External-LLM handoff, S2 (the App Intents surface)

**✅ DONE — merged + Jon device-passed 2026-07-14.** yes-chef PR
[#180](https://github.com/jonphillips/yes-chef/pull/180) (+ [#181](https://github.com/jonphillips/yes-chef/pull/181),
docs). [ADR-0038](decisions/ADR-0038-external-llm-handoff.md) S2: the external-LLM surface over the S1 core.
**The immediate loop works end-to-end on device** — `Export Handoff Context (menu) → Ask ChatGPT →
Import Handoff Result` returns a parsed prep plan into the review sheet with no human in the middle.

**App Intents (new `YesChefApp/AppIntents/` group).** Three `AppEntity`s (Recipe/Menu/MealPlan, all
`SyncableEntity` on our stable iCloud UUIDs) + `HandoffSource` as an `@UnionValue`.
`ExportHandoffContext(source:mode:)` creates the hand-off and returns a `HandoffExport` carrying the prompt and
`Menu.externalProjectName`. `ImportHandoffResult(handoffID:result:)` routes by id (param **or** stripped
token), stages the review, and `OpensIntent`s into `RecipeCollectionReviewSheet` via
`HandoffReviewCoordinator`/`HandoffReviewSheet`. `allowedExecutionTargets = .main` (in-process; the intents
call the repositories directly).

**Prompt modes.** `HandoffPromptMode` (`AppEnum`) exposes discuss/immediate in the Shortcuts action row.
**Default is `.immediate`** (`de8108e`): the Shortcuts surface exists *for* the headless `Ask ChatGPT` chain,
and a discuss prompt sent headlessly returns conversational prose the parser cannot use, while the reverse
mispairing is harmless. **The in-app Copy Prep Prompt button stays discuss and takes no mode** — the two
surfaces map to the two modes.

**Schema.** Additive synced `Menu.externalProjectName` (+ menu-detail field, repository write, trim-to-nil).
**Added to the standing prod-schema promotion list.** Strict block-on-duplicate dedupe lives in
`AIHandoffIntentImport.stageMenuPrepPlanReview` (marks imported when the sheet *opens* — the sheet remains the
sole writer of the durable artifact; a cancelled review therefore burns the session, and re-export is the
recovery: **confirmed as intended**).

**Device-pass findings (see the [PR #180 comment](https://github.com/jonphillips/yes-chef/pull/180#issuecomment-4964739760)).**
Two architect concerns were **retired** by the device pass: the `@ComputedProperty` + empty-query pattern on
`HandoffExport` resolves fine as a Shortcuts variable, and the `assumeIsolated` / dual-coordinator wiring holds
on the foreground path. **OQ5 resolved** — `source` is required, so a bare Action-Button invocation gets the
system picker.

**OQ6 RESOLVED — pessimistic.** ChatGPT's `Start chat in project` is **fixed-pick-only**: it resolves the
project at configure time and does **not** accept a variable (and appears to take no prompt input either). So
per-menu project auto-seeding from one generic shortcut is **not achievable**. This does *not* break the
hand-off — return→resource routing rides the `YC-HANDOFF:` token and is project-independent.
**`Menu.externalProjectName` is demoted from a routing key to an advisory reminder** (helper copy reworded to
match). Fallbacks: immediate mode as the automated loop; discuss mode via the in-app Copy/Paste buttons; an
optional `Export → Copy to Clipboard → Start chat in project` hybrid.

**Deferred:** no `AppShortcutsProvider` — the intents are Shortcuts-composable only (no zero-config
Siri/Action-Button/Spotlight surface). Note it could not have shipped the multi-step chain anyway, since that
chain includes ChatGPT's own action.

**Tests.** `AIHandoffTests` — immediate-prompt format contract, review-only import staging (no menu write),
duplicate blocking, project-name trim/clear.

**What S2 provoked.** Dogfooding the loop exposed that the hand-off reduces a rich multi-turn session to a
**context-free deliverable** — the *reasoning* dies in ChatGPT. Result:
**[ADR-0038 Amendment 1](decisions/ADR-0038-external-llm-handoff.md)** (the return artifact is
`(Deliverable?, Learnings?)`; Learnings commit to the resource's synced notes; S3 re-splits into **S3a**
contract-on-Menu / **S3b** Recipe+MealPlan serializers) and a new
**[ADR-0039](decisions/ADR-0039-playbook-column-thinking-vs-doing.md)** (the Playbook column; thinking-vs-doing;
**D5 — the prep plan holds tasks, never choreography**).

---
## ADR-0038 — External-LLM handoff, S1 (session-tracked core)

**✅ DONE — merged + Jon device-passed 2026-07-13.** yes-chef PR
[#179](https://github.com/jonphillips/yes-chef/pull/179).
[ADR-0038](decisions/ADR-0038-external-llm-handoff.md) S1: the transport-agnostic, **device-local** core
that generalizes the menu Copy-Prep-Prompt / Paste-Prep-Plan round-trip
([ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md) D5) into a trackable hand-off, proven
through the existing menu paste path (no new UI beyond one info alert).

**Core (`AIHandoff.swift`).** New device-local `aiHandoffs` table
(id/sourceType/sourceID/taskType/createdAt/importedAt/status/schemaVersion/exportedPrompt; STRICT migration)
**excluded from the CloudKit `SyncEngine`** — the sync-exclusion "unknown" resolved cleanly because
`makeSyncEngine` is a table **whitelist**, so `AIHandoff` simply isn't listed and joins
`chatMessages`/`chatThreads`/`recipeActiveVariations` in `localOnlyTableNames` (guarded by `CloudSyncTests`).
`AIHandoffRepository` = create/find/markImported.

**Token round-trip.** `AIHandoffToken` (prefix `YC-HANDOFF:`, `prompt`/`header`/`stripping`). **Copy Prep
Prompt** creates a hand-off, prefixes the token, snapshots the exported prompt. **Paste Prep Plan** strips +
validates the token (matching menu + task), applies the plan and marks the hand-off imported **atomically**
(one `database.write`), and dedupes a repeat return. Missing/mangled token → self-describing fallback still
lands the plan (`.applied`). Outbound prompt now demands the Unicode `→` glyph; `editableReviewLine` hardened
to also accept ASCII `->`.

**Discuss-vs-immediate (device-pass learning).** S1's prompt is the *discuss* variant — the strict format is
emitted on "finalize" (confirmed on device: an un-finalized paste returns prose). The **immediate-mode**
prompt variant (format-on-first-response, needed for the automated App Intents chain) is deferred to S2.

**Follow-up (silent-failure fix, `48c5114`).** Device pass caught an asymmetry: a re-paste of an
already-imported hand-off returned `.duplicate` and `prepPlanPasted` discarded it (silent), while the
wrong-menu guard *throws* first (proper error). Fix: a separate `MenuDetailModel.Information` channel surfaces
`.duplicate` as an **informative, non-error** "Already imported…" alert; **non-destructive** (no re-apply → no
clobber of hand-edits). Core `apply` unchanged; strict block-on-duplicate dedupe reserved for S2's
`ImportHandoffResult`.

**Tests.** `AIHandoffTests` (token/import/dedupe/fallback), `CloudSyncTests` sync-exclusion guard,
`MenuPrepPlanTests` ASCII-arrow, `AIHandoffMenuPasteTests` (duplicate informs without replacing the plan).

**Pre-code de-risking (2026-07-13).** The whole loop was validated by hand before implementation: `Ask
ChatGPT` returns text as a Shortcuts value, and a live beach-menu round-trip came back in the exact
review-text format the parser accepts ([ADR-0038](decisions/ADR-0038-external-llm-handoff.md) D2/OQ3). **S2**
(App Intents surface + per-menu project + immediate-mode prompt) and **S3** (generalize the serializer to
Recipe/MealPlan) remain, out of this scope.

---
## ADR-0036 — promote a recipe-shaped menu note → a real recipe

**✅ DONE — merged + Jon device-passed 2026-07-13.** yes-chef PR
[#178](https://github.com/jonphillips/yes-chef/pull/178).
[ADR-0036](decisions/ADR-0036-promote-note-to-recipe.md) S1 + S2 (one batch) + a provenance-shape follow-up.
Turns a recipe-shaped **menu note-item** (`MealPlanItemKind.note`, no `recipeID`,
[[menu-item-recipe-id-invariant]]) into a real structured `Recipe`. **S1** = a **deterministic**
heading-based note→draft adapter (`MenuNoteRecipePromotion`, `RecipeParseBuilder`-family naming only — no
LLM: recognizes explicit `Ingredients`/`Instructions|Method|Directions|Preparation` sections, strips
bullets/step numbers, everything else stays as notes) → `WorkbenchDraftRecipe` → the existing ADR-0024
editable review sheet → commit to a new `Recipe`. Chose determinism over the ADR's proposed on-device LLM
parse per [[llm-vs-determinism-surface-boundary]] (reproducible, private, free, no truncation; quantity/unit
parsing still happens downstream at `RecipeRepository.save`). Entry point = a **Make Recipe** glyph on note
rows (`MenuDetailSections`). **S2** = an opt-in confirmation to swap the note row for a recipe-kind item
pointing at the new recipe (`MenuRepository.replaceNoteItemWithRecipe`), preserving day/meal/sort.
**Provenance (OQ2 resolved, follow-up commit):** original prose rides in as an **editable general
`RecipeNote`** (`From menu note "<title>":` + blank-line-collapsed prose), **not** a `RecipeSource` — the
source-card version was a pinned, non-deletable header crowding both the recipe and the menu row (caught on
device). On replacement the note row's `notes` is cleared (`item.notes = nil`) so the promoted row collapses
to its title; blank machine FK dropped (live back-link is the item's `recipeID`). No schema change → the
standing prod-schema follow-up is unaffected. Free-rider: `.lineLimit(3)` on the menu-row note text
(`MenuDetailSections.swift:276`) **closes the queued "Menu note-item truncation" effort**. New
`MenuNoteRecipePromotionTests` (parse + provenance-as-note + replacement-clears-row). `RecipeNote`-on-recipe
promotion remains a future **S3**, out of this scope.

---
## ADR-0037 — grocery seed-coverage diagnostic

**⏳ PENDING — architect-reviewed 2026-07-13; awaiting merge + Jon device pass before this entry is final
(fill the PR # and device-pass date on merge).** yes-chef PR
[#177](https://github.com/jonphillips/yes-chef/pull/177).
[ADR-0037](decisions/ADR-0037-grocery-seed-coverage-diagnostic.md) S1 + S2 (one batch). Closes ADR-0035 OQ1's
curation loop — a read-only, dev-facing review queue for canonical grocery names that miss
`GroceryStoreArea.seed(for:)`. **S1** = pure `SeedCoverageReport` + `make(from:)` in `YesChefCore` (seed hits
excluded via `seed(for:)` not raw `seedAreas`; uncovered vs covered-elsewhere split on any stored aisle;
most-common aisle → `suggestedArea`; count-desc/name-asc sort; deterministic tie-break) + a
`GroceryStoreAreaCache.seedCoverage(in:)` DB adapter over `IngredientLine ∪ GroceryItem` + a tested
Swift-literal export (`.other` placeholder for uncovered). **S2** = `SeedCoverageView` + an always-on
**Developer** section in `SettingsView` (two grouped lists, counts in headers, copy-per-row + copy-per-group via
`UIPasteboard`, reload on appear + `DatabaseChangeBeacon.didChange`). No schema change, no sync surface — purely
derived from existing durable columns ([[grocery-area-no-learned-cache]], [[llm-vs-determinism-surface-boundary]]).
Review fold: adapter switched to the `canonicalIngredientName` accessor (not the raw `canonicalName` column) so
rows with an unpopulated column aren't silently dropped from the queue. New `SeedCoverageReportTests`.

---
## Grocery quantity scaling fix

**Architect-reviewed 2026-07-12, Jon device-passed 2026-07-13 — yes-chef PRs
[#167](https://github.com/jonphillips/yes-chef/pull/167)–[#170](https://github.com/jonphillips/yes-chef/pull/170).**
Scaling a recipe / menu item / meal-plan item never scaled the quantities added to the grocery list —
generation and the source-removal recompute both read raw `line.quantity`. Fixed in `GroceryCore.swift` with one
source-provenance-keyed `groceryScale` helper (priority `menuItem.scale → mealPlanItem.scale → recipe.viewScale`),
applied in both `GroceryGeneratedItemDraft` (scale 1 preserves fraction text byte-for-byte) and `generatedMeasure`;
free-text quantities left unscaled. New + updated tests in `GroceryTests`/`GroceryPlanningTests` (293 pass).

---
## ADR-0035 S2 — on-device grocery store-area classifier

**Architect-reviewed 2026-07-13, Jon device-passed 2026-07-13 — yes-chef PR
[#174](https://github.com/jonphillips/yes-chef/pull/174).**
[ADR-0035](decisions/ADR-0035-grocery-store-area-grouping.md) S2 — the first `.onDevice`-by-design verb. A new
`GroceryCategorizationClient` (mirrors `MenuDepositClient`) classifies the *new, uncached* canonical names
(`aisle == nil`) once, folds output through `GroceryStoreArea.normalized`, and writes `aisle` via
`GroceryStoreAreaCache.applyClassified` — **never** overwriting user/seed/prior (the stability contract),
**never** on the writer, degrading silently to "Other" on `onDeviceUnavailable`. Runs on **both** triggers
(after each generation path AND once on grocery-detail appearance, guarded by uncached-names non-empty) so
existing lists fill without a regen. No schema change; categorization only *places* items, never invents or
merges list data ([[llm-vs-determinism-surface-boundary]]). Touches `GroceryModels.swift` / `GroceryViews.swift`
+ new `GroceryCategorization.swift` / `GroceryStoreArea.swift`; new `GroceryCategorizationTests.swift`. **Closes
ADR-0035.**

---
## ADR-0035 S1 — grocery store-area grouping

**Architect-reviewed & approved 2026-07-13, Jon device-passed 2026-07-13 — yes-chef PR
[#172](https://github.com/jonphillips/yes-chef/pull/172).**
[ADR-0035](decisions/ADR-0035-grocery-store-area-grouping.md), Accepted. The existing synced
`GroceryItem.aisle` column receives a deterministic seed and the flat "To Buy" list groups by store area (no
migration; a fresh migration runs the backfill). Store-walk order fixed to Jon's 13 areas (perishables last,
OQ1 resolved 2026-07-12); a hand-set aisle survives regeneration; Purchased stays a flat crossed-off tail. S2
(on-device long-tail classifier) landed in #174 above.

---
## ADR-0034 S3c — enrich the exported dish context (Amendment 1)

**Architect-reviewed 2026-07-12 — yes-chef PR
[#166](https://github.com/jonphillips/yes-chef/pull/166).**
[ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md) Amendment 1. The menu "Copy Dish Context"
button became a self-contained **frontier** prompt (renamed **"Copy Prep Prompt"**): serializes at `.frontier`
budget, threads full recipe **method** into `MenuChatItemContext` (with `InstructionSection` sub-headers, a
method-first trim rung on the on-device path), **uncaps ingredients** on the frontier path (8 stays the on-device
starting ceiling only), and **prepends a real intro prompt** (adapted `MenuPrepPlanClient.instructions` +
`tasteProfile`/`makeAheadPrepPlanPreference` via `aiPromptPreferences`) asking for **review-text** output so
ChatGPT's answer pastes back cleanly. The meal-calendar per-day make-ahead-strategy verb was left untouched.

---
## Meal-planner (Calendar) row affordance swap

**Architect-reviewed 2026-07-12 — yes-chef PR [#154](https://github.com/jonphillips/yes-chef/pull/154)
(branch `codex/meal-planner-affordances`).** Closes the effort in
[`efforts/meal-planner-affordances.md`](efforts/meal-planner-affordances.md) (Jon's 2026-07-11 dogfood batch,
effort #1). Reworks the meal-calendar row so a **row tap opens the recipe reader** (recipe rows) and the
**Edit-Meal sheet moves off the row tap** onto a dedicated right-hand affordance; note rows (no reader) tap
straight to Edit-Meal. App-layer only (`MealCalendarViews.swift`), no schema. Package tests + `git diff --check`
passed; app build blocked on an unavailable CoreSimulator service (per lean-verification policy, no retry — Jon's
device pass). **Miscommunication caught and resolved:** the brief named an "existing target/grocery row icon" to
sit beside the new calendar icon, but no such control exists in the code — Codex's first pass papered over the gap
and left **Edit-Meal reachable via three redundant controls** (row tap, the Meal-Actions ellipsis "Edit", and the
new calendar button). The architect review flagged the multiple edit paths; that surfaced the miscommunication,
Jon and Codex re-aligned on the intended single affordance model, and the effort was confirmed good. Parked
follow-ons still live in the effort doc: **drag-and-drop retest on Beta 3** and **cell images**.

---
## Workbench dogfood polish (Jon's 2026-07-11 two-device pass)

**Architect-approved 2026-07-11 — rides in the slice commit; app build + device pass are Jon's.** Effort
[`efforts/workbench-dogfood-polish.md`](efforts/workbench-dogfood-polish.md), all six slices shipped in the
working tree: candidate rows show thumbnail + source; draft rationale renders candidates by **title/source not
object ID** (chat context + synthesis prompt both hardened); the apply/review sheet is **scrollable**;
**archive-all-candidates** archives the candidate recipes *out of the library* + clears them from the workbench
(Jon-confirmed intent: the workbench distills the one true recipe and removes the noise; menu/meal-plan cascade
accepted); **pick a candidate photo** for the working recipe (copies BLOBs to a new hero + sets cover, validated
to a candidate → sync-safe); and **"Drafted From" provenance links** on the promoted recipe (degrade to title
snapshot on delete/archive). App-layer + two core files; package builds + 4 new tests pass. **Device note:**
archive-all deletes the candidate rows, so the "Drafted From" links clear with them — transient provenance by
design (a persistent-provenance variant is a separable follow-up if wanted).

---
## Chrome & navigation polish (Jon's 2026-07-11 two-device pass)

**Architect-approved 2026-07-11 — rides in the slice commit; app build + device pass are Jon's.** Effort
[`efforts/dogfood-fixes-2026-07-11-chrome.md`](efforts/dogfood-fixes-2026-07-11-chrome.md), all five slices
shipped in the working tree: side-menu order/naming (Recipes · Groceries · Calendar · Menus · Browser · Workbench
· Settings); AI-widget cleanup (dropped the on-/off-device disclaimer + static provider label + de-mangled a11y
hint, chat input two lines); recipe-detail toolbar reorder (Edit · Grocery · Add Meal · AI toggle · Workbench);
delete-a-recipe-image-without-replacing (new `removesHeroPhoto` draft flag, cover clears, sync-safe); and the AI
apply-action relabel + per-verb SF Symbols (Save to Notes / Suggest Dishes / Chef It Up / Create Prep Plan /
Revise Recipe, suffixes dropped). App-layer, no schema. Package builds + 29 touched tests pass.

---
## 🎉 iCloud sync working end-to-end across two devices (M4 milestone confirmed)

**Jon device-confirmed 2026-07-11:** recipes, images, menus, and the whole synced library round-trip
**end-to-end across two physical devices** (`iPad Pro 13-inch (M5)` ↔ `iPhone 17 Pro`). This is the M4
iCloud-sync milestone ([`milestones/M4-icloud-sync.md`](milestones/M4-icloud-sync.md), ADR-0002/ADR-0010)
**landing in practice** — the one-way gate everything preceded is crossed and holding. The earlier
"missing content on iPhone" scare was diagnosed (ADR-0028) as a throttled bulk *initial* sync that simply
needed to finish downloading, **not** data loss; once caught up, convergence is clean. We remain in the
CloudKit **Development** environment by design (schema still evolving) — the production-schema promotion is
the deliberately-held ops step in `CURRENT_HANDOFF.md`, not a blocker on dogfooding sync. Prior sync round-trip
milestone: the extension-sync fix ([[extension-sync-construct-not-run]], PR #49).

---
## ADR-0028 — Sync status indicator accuracy (throttled-initial-sync honesty)

**Accepted (scope corrected) 2026-07-10; fix on main, Jon device-passed via the two-device sync run above.**
Implements [ADR-0028](decisions/ADR-0028-multi-foreign-key-sync-loss.md). The dogfood "missing content on
iPhone" turned out to be **CloudKit rate-limiting a ~44k-row + 2.5k-asset first pull** (`CKError 7/2062`), not
multi-FK content loss — the debug "Local record counts" sheet showed the child tables **climbing, not zero**,
so the proposed schema/zone rebuild was **disproven and withdrawn** (holds [[sqlitedata-single-fk-sync-limit]]).
Two real bugs fixed instead: **(1)** the "Up to date" indicator lied — it flipped green mid-download; `SyncHealth`
gained an `isFetchingChanges` input + a `SyncDisplayStatus.downloading` case (gated after upload-pending) so the
row stays "Downloading changes from iCloud" until the pull completes (lives in **CloudSyncKit**, shared with
galavant; reducer-tested). **(2)** the demo-seed gate — deterministic `00000000-…` keys were polluting the zone.
The debug count-row sheet stays (it caught the misdiagnosis). Accepted limitation: no public throttle/backoff
signal exists (SQLiteData swallows the `CKError`), so the row can't say "paused by iCloud" and may briefly flash
"Up to date" between throttled batches — recorded in the ADR.

---
## ADR-0029 — Main-thread DB writes + over-heavy list/grocery fetch (the UI-stall pass)

**Accepted / Resolved 2026-07-11 — PRs [#148](https://github.com/jonphillips/yes-chef/pull/148) (S1) +
[#149](https://github.com/jonphillips/yes-chef/pull/149) (S2/S4/S5b + the S5a→S6c diagnostics + the S7 fix,
`ba9d7bd`). Jon device-confirmed.** Implements [ADR-0029](decisions/ADR-0029-main-thread-write-and-fetch-cost.md).
The dogfood symptom — archive ≈ 1 s, variation switch janky, then measured at **5.6–6.8 s** — resisted four
successive theories (writer convoy, image decode, COMMIT envelope, main-actor delivery), each retired by a
timestamped capture. **Finding 8 (the real root cause):** `GroceryIngredientChoiceRequest`, an **always-on
whole-library `@Fetch` re-running synchronously on the writer inside every affected commit** — so every quick
mutation paid ~5 s of self-inflicted writer occupancy ([[sqlitedata-fetch-writer-convoy]]). **S7 fix:** remove
the two always-on grocery `@Fetch`es from `GroceryLibraryModel`, add a **scoped** `YesChefCore` fetch (choices
for an explicit `Set<Recipe.ID>`), and load them **on-demand at presentation time** via `database.read` (pool
readers, never the writer) when the ingredient-selection sheet opens. Also shipped as correct hygiene: S1 async
off-main writes for the six tap handlers, S2 thumbnails-only list fetch (no full-res BLOBs), S4 off-main
downsampled+cached detail-photo decode, S5b. **Result: writer-api-return dropped from ~5000 ms to tens of ms on
every mutation; no schema change, no sync change, no image change.** New invariant recorded in the ADR: *no
always-on `@Fetch` may perform O(library) work or read full rows of tables with large inline BLOBs.* S3
memoization + fetch-animation narrowing closed as unnecessary (render work measured sub-millisecond throughout).
Residuals parked (not scoped): `RecipeListRequest` ×4 (post-S2 thumbnails-only, bounded — watch, don't rebuild).
The S7 behavioral test (`GroceryIngredientChoiceTests.swift`) is authored but still untracked — Jon commits it.

---
## ADR-0027 — "Capture to menu" harvest verb (S1)

**Architect-reviewed & approved 2026-07-10 — yes-chef PR [#141](https://github.com/jonphillips/yes-chef/pull/141)
(branch `codex/adr-0027-capture-to-menu`).** Implements
[ADR-0027](decisions/ADR-0027-harvest-chat-into-notes.md) (Accepted 2026-07-10), S1. A new **extraction**
menu chat verb — the inverse of the generative complement family — that takes content **already in the chat**
and captures it as one or more `.note`-kind `MenuItem`s. The model **segments and reshapes** rambling chat
prose into clean recipe-looking notes (title + body) and **never invents**; output is a JSON array of
`{title, body}`, one per distinct note ([[llm-curation-not-synthesis]]). Rode the already-merged ADR-0026
collection sheet ([#138](https://github.com/jonphillips/yes-chef/pull/138)). **Additive `aiSettings`
`captureToNotePreference` column only** (non-null, nonempty default), otherwise sync-safe by construction —
captured rows are always `.note` with no `recipeID` ([[menu-item-recipe-id-invariant]] sidestepped for free).

- **Payload + client (`YesChefCore/MenuNoteHarvest.swift`).** `MenuNoteHarvestPlan { notes: [HarvestedNote] }`
  / `HarvestedNote { title, body }` (Equatable/Sendable) with the ADR-0024 `editableReviewText()` /
  `applyingEditableReviewText(_:)` round-trip, mirroring `MenuComplement.swift`. The `@Dependency`-injected
  `MenuNoteHarvestClient` deliberately takes **no `context:` argument** — the menu is **not** sent (D2, the fix
  for Jon's "it sent the whole menu" surprise). Two prompt modes, one client: non-empty selection → the
  selection alone; empty → the assistant transcript. **LLM always runs** even for an exact selection (OQ2).
  Static `parse(_:)` tolerates ```json fences and drops empty-title elements. `maxTokens: 1536`,
  `reasoningEffort: .medium` (matches complement).
- **Wiring (`MenuModels.applyActionCatalog`).** A `ChatApplyAction<MenuNoteHarvestPlan>` titled "Capture to
  menu", mapping `plan.notes` → one `ChatApplyReviewItem` per note, each committing its own `.note` `MenuItem`
  via `commitCapturedNote` → `MenuRepository.addNoteItem`. **Placement (OQ1): deterministic Day 1 / Dinner** —
  menu detail renders all days in one scroll with no selected-day state, so captured notes land in a fixed slot
  the user moves afterward (flagged in the PR).
- **Selection plumbing fix.** The apply-menu tap resigns the assistant bubble's first responder before its
  action runs, which previously wiped the shared selection — so selection-scoping never survived to *any* verb.
  `ChatAssistantSelection.relinquish` now **retains** the text on resign (releasing only bubble ownership) and
  the action clears it via `clear(ifMatching:)` after consuming it. Latent bug the ADR assumed absent; fixes
  every selection-scoped verb, not just harvest.
- **Task preference.** New `AIPromptPreferenceKind.captureToNote` + a "Capture to Note" Settings editor with a
  recipe-formatting default prompt, shared through the existing model-boundary preference injection (ADR-0018).
- **Architect fix during review ([#141](https://github.com/jonphillips/yes-chef/pull/141), commit `05c481b`).**
  The harvest `AnyChatApplyAction` inherited the default `requiresSubject: true`, so the no-selection case fell
  back to the latest-reply subject and `run()` fed that reply in as `selection` — keeping the client in
  explicit-selection mode and making the ADR-0027 D2 **transcript-scan branch unreachable in production** (the
  existing unit test called the client directly, bypassing the wiring). Set `requiresSubject: false` so an
  empty selection reaches the client and the transcript branch runs; added a wiring-level guard test that
  builds the real catalog and asserts the flag.
- **Verification.** `swift test` (package) green — 278 tests; app + test targets compile clean
  (`build-for-testing`, generic iOS Simulator destination) so the wiring change and new tests build;
  `scripts/check-drift.sh` green. A device-bound build (iPad Pro 13-inch M5) could not run in this environment
  — no iOS 27 simulator present — consistent with the lean-verification stance. **Device pass complete
  (Jon, 2026-07-12):** selection path (highlight survives the apply-menu tap), transcript path (N notes), and
  Day 1/Dinner placement all confirmed on `iPad Pro 13-inch (M5)` + `iPhone 17 Pro`.

## ADR-0027 S2 — "Capture to notes" (the recipe sibling of the menu harvest verb)

**Merged to main — yes-chef PR [#147](https://github.com/jonphillips/yes-chef/pull/147) (branch `adr27s2`);
architect-confirmed in code + Jon device-passed 2026-07-12.** Implements
[ADR-0027](decisions/ADR-0027-harvest-chat-into-notes.md) D6/S2 — the recipe instance of the same harvest verb,
the sibling ADR-0027 S1 deferred until its shape proved out. Adds a **"Capture to notes"** extraction verb to the
recipe chat catalog (`RecipeDetailModel+Enrichment.swift`): captures a chat selection (or, absent one, the
assistant transcript) into one or more `RecipeNote`s on the recipe, reusing the same `MenuNoteHarvestPlan` /
`HarvestedNote` payload and client as the menu verb. Wired `requiresSubject: false` so the no-selection
transcript-scan branch stays live in production ([[harvest-verb-requires-subject-false]]); list commit shape, one
review item per note through the ADR-0026 collection sheet. Commits via the shared
`RecipeRepository.appendRecipeNote` primitive (`YesChefCore/RecipeCapturedNote.swift`) writing a `.general`
`RecipeNote` — the canonical recipe body is never touched. Schema-free / sync-safe (`.general` is an existing
`RecipeNoteType`). Package tests green; app build + device pass are Jon's (now done).

## ADR-0027 Amendment 1 — the tap-to-target "deposit" verbs (S1 recipe-append · S2 note-revise)

**Merged to main — yes-chef PR [#146](https://github.com/jonphillips/yes-chef/pull/146) (branch `adr27s1`) +
the Amd-1 S2 commit `4df9fc2`; architect-confirmed in code + Jon device-passed 2026-07-12.** Implements
[ADR-0027 Amendment 1](decisions/ADR-0027-harvest-chat-into-notes.md#amendment-1--deposit-chat-intelligence-onto-the-item-you-point-at-recipe-append--note-revise)
— write chat *intelligence* (a Compare verdict, a "here's how I'd change this" riff) onto the **existing menu
item you point at**, adaptively by canonical-ness:

- **A5 — tap-to-target binding (the one genuinely new UI piece).** `MenuModels` gains a device-local, unsynced
  `depositTargetItemID` + a "Deposit target" toggle row in `MenuDetailSections.swift` (target icon, a11y label,
  tinted highlight); tapping the active target clears it. The deposit verbs only appear when a target is set.
- **A2 — recipe target → append (S1, "Add to recipe notes").** `depositToRecipeActions` reshapes the
  intelligence into one note and appends it via `RecipeRepository.appendRecipeNote` with the **`.adaptation`**
  note type (a new, additive `RecipeNoteType` case — sync-safe, no migration); the recipe body is never
  rewritten (protect the canonical recipe).
- **A3 — note target → revise via a compose surface (S2, "Revise this note").** `reviseNoteActions` runs the
  `MenuDepositClient` revise mode (weaves intelligence into the note's current body) and surfaces the woven draft
  as the editable review text **beside the "Original note" as supporting evidence** (OQ-Amd-2 resolved: neither
  pure replace nor merge — a compose surface, the original stays salvageable), committing over `menuItems.notes`.
  `requiresSubject: false`.

Payload `DepositNotePlan { note: DepositedNote { text } }` + `MenuDepositClient` (extract + revise modes) in
`YesChefCore/DepositNote.swift`; `DepositNoteTests` cover it. **No queue / no auto-Workbench / no graduation**
(A4 — the recorded reversal): a deposit touches **only** the item pointed at. Schema-free; both writes are
additive/in-place on already-synced tables. **Still deferred by the ADR (separate future efforts, not Amd-1
follow-through):** OQ4 taste preference and A6/D5 promote-a-note → real recipe.

## Logging for Frontier LLM Interaction

**Architect-reviewed & approved 2026-07-10 — yes-chef PR [#139](https://github.com/jonphillips/yes-chef/pull/139)

- Jon just put this here. Claude may want more details -- feel free to rewrite. We can now view logs in the Xcode console.

## ADR-0026 — the LLM-review collection becomes the universal slide-up sheet (S1 + S2)

**Architect-reviewed & approved 2026-07-10 — yes-chef PR [#138](https://github.com/jonphillips/yes-chef/pull/138)
(branch `codex/adr-0026-review-collection-sheet`, commit `f135d25`; core check-drift green — 270 tests, 0 lint;
app layer device-passed by Jon).** **✅ The two carried interaction risks cleared on device 2026-07-22** — the
adjust launch row's Compare-diff is not swallowed by the collection sheet dismissing from `RecipeChatPanel` in
the same runloop, and the N=1 auto-drill's stacked child-over-collection sheet reads cleanly (incl. iPad
split-chat). Implements [ADR-0026](decisions/ADR-0026-review-collection-sheet.md)
(Accepted 2026-07-10), S1 + S2 in one PR. **Schema-free, sync-safe by construction** — an in-memory
review-surface refactor over the existing `ChatApplyReviewItem` collection, no table/column. Dispatch 2 (and
last) of the 2026-07-09 menu-planner pass; held apart from Dispatch 1's low-risk quick-fixes because it
re-touches the shared `RecipeChatWorkspace` apply-action presentation state. Extends
[ADR-0024](decisions/ADR-0024-editable-proposal-preview.md) (the per-item editable sheet — the layer below);
serves [ADR-0025](decisions/ADR-0025-reader-comment-ingestion.md) curation. [[chat-verb-commit-shapes]],
[[llm-curation-not-synthesis]].

- **S1 — collection sheet (D1–D3).** New host-agnostic `RecipeCollectionReviewSheet` (`YesChefApp`),
  parameterized by `[ChatApplyReviewItem]` + `commit`/`discard`/`discardAll`/`onEmpty` closures — **not** baked
  into `RecipeChatPanel`'s `@State`, which is what let S2 reuse it. It lists the staged set (title + summary +
  per-item Discard) and drills into the ADR-0024 editable review; per-item commit/discard removes the item and
  keeps the sheet open on the remainder; discard-all is one confirmed gesture. The cramped inline
  `ChatApplyReviewList` band is **removed** from `RecipeChatPanel`, along with its now-dead `ChatApplyReviewCard`,
  `ChatActionSummary`, and `ChatCommittedActionSummary`; the panel's `presentedReviewItem`/`actionSummary`
  `@State` collapses to a single `isReviewSheetPresented` bool. `ChatApplyReviewRow` was promoted from `private`
  so the new sheet can host it.
- **OQ behaviors preserved.** N=1 skips the list and auto-drills into its editable review (`reconcilePresentedItem`
  on appear/count-change); the N→1 transition (committing/discarding to the last item) re-drills cleanly; a
  lightweight per-item green commit confirmation lives in the sheet (OQ4 — replacing the removed panel-level
  `ChatActionSummary`); the per-item `supportingEvidenceRows` disclosure survives the hoist unchanged (OQ3).
- **D4 adjust verb — launch-only row.** The sole `.inline`-presentation consumer ("Adjust this recipe",
  ADR-0023) renders as a launch row inside the collection sheet whose primary action delegates to the item's
  commit, which opens the Compare-diff `RecipeAdjustmentReviewView` exactly as before — the sheet lists
  *everything the LLM proposed* while Compare-diff still **owns** the adjust review. No apply-action's commit
  contract changed; the router picks the row affordance from `presentation`.
- **S2 — reader-feedback curation adopts it.** `RecipeCaptureView`'s hand-rolled `Section("Reader Feedback")`
  proposal rows (each opening a one-off `ChatApplyReviewSheet`) are replaced by a single "Review N proposals"
  button that presents the same `RecipeCollectionReviewSheet`, hosted directly in the capture Form (no chat
  panel). The `ReaderFeedbackSheet.review` enum case dropped its per-tip associated value. Commit removes the
  tip from `readerFeedbackProposals` via the existing `acceptReaderFeedbackTip` → `discardReaderFeedbackTip`
  path; discard matches the tip by text (safe because proposals are deduped by lowercased text at stage time).
- **Verification.** `xcodegen generate` + `scripts/check-drift.sh` green; one app build attempt was blocked
  before compilation by an unavailable Xcode-beta simulator service (`simdiskimaged`) and not retried per repo
  rules. **Device pass owed (Jon):** the architect review flagged two interaction risks — (1) the adjust launch
  row presents Compare-diff from `RecipeDetailView` while the collection sheet dismisses from `RecipeChatPanel`
  in the same runloop (present-while-dismiss across two anchors — confirm Compare-diff isn't swallowed); (2) N=1
  auto-drill stacks the child review sheet over the collection sheet (functionally fine; confirm it reads
  cleanly, incl. iPad split-chat, OQ2).

---

## ADR-0025 D6 + D7 — curation-prompt preference + curated notes into chat (effort closed)

**Merged to main 2026-07-09 — yes-chef PR [#134](https://github.com/jonphillips/yes-chef/pull/134)
(branch `adr-0025-d6-d7-and-reader-feedback-editing`, commit `50b3965`; core carries unit tests, app layer
device-passed by Jon).** Closes the [ADR-0025](decisions/ADR-0025-reader-comment-ingestion.md) reader-comment
ingestion effort (Amendment 2026-07-09). Additive schema only — sync-safe.

- **D6 — DB-backed curation-prompt preference (ADR-0018).** Added `AIPromptPreferenceKind.readerFeedback`, an
  additive `aiSettings.readerFeedbackPreference` column, wired the curation request's `promptPreferenceKey`
  (previously `nil`) through `ReaderFeedbackCurationClient`, and exposed the editor in AI settings — the
  established prompt-preference pattern, no new storage.
- **D7 — curated notes feed the chat (read-only).** `RecipeChatRecipeContext` gained a **distinct
  `readerFeedback` bucket** fed from accepted `RecipeNote(.readerFeedback)` rows — context injection, not an
  actionable verb; no writes, no synthesis ([[llm-curation-not-synthesis]]).
- **Bundled with the effort (same PR).** A **capture review-sheet fix** (lifted the reader-feedback `.sheet`
  off the Form-embedded subview onto the parent `RecipeCaptureView` Form so tapping Review no longer collapses
  the presentation), **inline reader-feedback editing** (per-tip Edit/Done + Delete in the recipe's Reader
  Feedback section, backed by scoped/tested `RecipeRepository.updateReaderFeedbackNote` /
  `deleteReaderFeedbackNote` that only touch `.readerFeedback` notes), and a latent `MenuModels` build fix
  (explicit `return` in a multi-statement complement `.map` closure).
- **S6** — Jon's end-to-end device test on a real NYT recipe (Load Comments → curate → review/promote → accept
  → notes appear in Reader Feedback, drop out of cooking mode, reach the chat context). **Production-deploy
  note:** the additive `aiSettings.readerFeedbackPreference` column joins the held prod-schema checklist in
  `CURRENT_HANDOFF.md`.

**ADR-0025 effort arc (full lineage, all merged to main):** D1/D2 harvest + curation **scaffolding**
([#129](https://github.com/jonphillips/yes-chef/pull/129)), the **curation revision**
([#131](https://github.com/jonphillips/yes-chef/pull/131)) with its same-day companion **"Quick fixes"**
([#132](https://github.com/jonphillips/yes-chef/pull/132) — the bulk was `ReaderFeedbackCuration` +
`RecipeCaptureView` curation work, not the "meal-planner build fix" the earlier one-liner implied; carries
`ReaderFeedbackCurationTests`), and **D6/D7 + S6** ([#134], this entry) — NYT "Most Helpful" harvest →
LLM-curate distinct tips → reviewable `RecipeNote(.readerFeedback)` + curation-prompt preference + read-only
chat-context feed. Additive enum + `aiSettings` column, no new table; sync-safe. Effort closed.

---

## Menu-planner dogfood 2026-07-09 — quick-fixes bundle

**Merged to main 2026-07-09 — yes-chef PR [#136](https://github.com/jonphillips/yes-chef/pull/136).** The
one-PR, no-schema quick-fixes bundle from the 2026-07-09 menu-planner dogfood pass (brief
[`efforts/dogfood-fixes-menu-planner-2026-07-09.md`](efforts/dogfood-fixes-menu-planner-2026-07-09.md)): the
**chat selection-clear bug + a clear affordance**, the **complement note-body** write (ADR-0012 Amendment 2 —
complement suggestions land their body onto the `.note` `MenuItem`), the **prep-plan "explain better"** revision
(compose from the stored Make-Ahead strategy, just describe it more legibly — [[menu-planner-dogfood-2026-07-09]]),
and **variation rename**. App-layer, no schema; nothing left.

---

## ADR-0024 Slice 2 — list / structured verbs get editable review

**Architect-reviewed & approved 2026-07-09 — yes-chef PR [#128](https://github.com/jonphillips/yes-chef/pull/128)
(branch `codex/adr-0024-s2-editable-list-verbs`; built on device by Jon; core round-trip + fidelity carry unit
tests).** S2 of
[ADR-0024](decisions/ADR-0024-editable-proposal-preview.md) (Accepted 2026-07-09). **Schema-free, app-wide.**
Completes the ADR: every list / structured verb the S1 sheet showed read-only is now **editable while keeping
its commit shape intact** (D4) — no list flattened into an opaque string ([[chat-verb-commit-shapes]],
[[llm-curation-not-synthesis]]).

- **Per-shape parse round-trip (D4/OQ2 lean).** Each verb gained an `editableReviewText()` /
  `applyingEditableReviewText()` pair in `YesChefCore`: `ServeWithPlan`, `MenuComplementSuggestion`,
  `MealPlanComplementSuggestion`, `MealPlanMakeAheadStrategy`, `MenuPrepPlan`, and `WorkbenchDraftRecipe`
  (its **prose fields** — rationale/title/subtitle/summary/servings/yield/cuisine/course/ingredient-section/
  notes — beyond S1's rationale-only edit; ingredient/instruction lines stay structured, untouched). The edited
  text re-parses to the typed payload on commit; latent provenance (`sourceItem`/`sourceDish`) is preserved for
  lines the user left unchanged via a group-and-drain pop.
- **Unchanged-payload fidelity guard (the review fix, commit `Preserve unchanged editable review payloads`).**
  The commit path always re-parsed, even with zero edits — and the flat `"title: note"` format can't losslessly
  round-trip a colon-in-title Serve-With item (`"2:1 rice"` → `title "2" / note "1 rice"`), a regression from
  S1's faithful original-payload commit. Fixed by short-circuiting: when the committed text is byte-identical to
  the presented `editableText`, commit the **original payload** untouched (`action.commit(payload)` at the
  `AnyChatApplyAction` layer; `edited == original ? original : applying(edited)` at the four inline
  `ChatApplyReviewItem` sites). Invariant is now uniform: **un-edited commit → faithful original; edited commit
  → re-parse.** Two regression tests document the parser ambiguity and prove the guard commits the original.
- **D5 scope.** The ADR-0023 "Adjust this recipe" compare verb stays `.inline`, untouched.

---

## ADR-0024 Slice 1 — editable proposal preview (single-string verbs)

**Architect-reviewed & approved 2026-07-09 — yes-chef PR [#127](https://github.com/jonphillips/yes-chef/pull/127)
(confirm the number when cutting); merges after Jon's device pass** (the app layer — the presented sheet and its
iPad split-chat host — is verified only in Jon's Xcode build; the core D3 contract change carries a unit test).
S1 of [ADR-0024](decisions/ADR-0024-editable-proposal-preview.md) (Accepted 2026-07-09). **Schema-free,
app-wide.** The two-step S1 plan collapsed to one: the planned shared capture-sheet dismiss hardening (step 1)
was already landed by batch 5's "Harden capture review dismissal" commit — `RecipeCaptureView` and
`ShareViewController` both already carry `interactiveDismissDisabled` + `isModalInPresentation` + discard-confirm
— so S1 delivered the remaining editable-chat-sheet step.

- **D3 contract change (the risk) — additive.** `ChatApplyReviewItem` gains `presentation`
  (`.inline`/`.sheet`), `editableTitle`, `editableText`, and `commit` now takes an `approvedText` argument.
  Backward compatible: the legacy zero-arg `commit` init is preserved (wrapped `{ _ in }`), and a new
  `AnyChatApplyAction(editableSummary:commitEditedSummary:)` init sits beside the existing
  `renderedSummary`/`reviewItems` inits. Every prior call site keeps working; only the default presentation
  flips to `.sheet`.
- **D2 authorship.** Commit persists the edited string verbatim — Make-ahead / Chef-It-Up route through the
  newly-public `RecipeRepository.updateMakeAhead` / `updateChefItUp` (these sections are prose blobs stored as
  `String`, so editing the rendered text and writing it back is lossless); the committed-action summary reflects
  the approved text.
- **D4 per-shape.** Make-ahead / Chef-It-Up / workbench-rationale edit as prose (the workbench sheet edits only
  `rationale`, keeps the structured draft intact, and shows the full review in a "Full proposal" disclosure).
  List verbs (Serve-With, complements, prep-plan) inherit the roomy **read-only** scrollable sheet now; their
  editing is S2 — no list is flattened into an editable string.
- **D5 scope + OQ1.** `.sheet` is the app-wide default; the ADR-0023 "Adjust this recipe" compare verb stays
  `.inline` (verified the only compare verb). OQ1 dismiss-hardening built into the sheet:
  `interactiveDismissDisabled(hasUnsavedEdits)` + Discard-with-confirm-when-edited + commit disabled on empty.
- **Tests** — new `ChatApplyReviewItemTests.editableReviewItemCommitsApprovedText` proves the edited string
  reaches commit; the existing apply-action tests updated to the new `commit(_:)` signature. Core package builds
  and tests pass.

**Device-pass follow-ups (non-blocking, from the review):** OQ3 — confirm the sheet presents over the detail
view (not cramped inside the chat column) and doesn't fight the `ChatWorkspaceDetent` drag on iPad split-chat;
eyeball that the auto-presented sheet + its staged "Review" row behind it don't read as a duplicate.

---

## Dogfood fixes — batch 5 (mechanical polish)

**Architect-reviewed 2026-07-09 — yes-chef PR [#126](https://github.com/jonphillips/yes-chef/pull/126);
merges after Jon's device pass** (the app target never compiled in CI — its `PreferenceKey` concurrency
error and the whole app layer are verified only in Jon's Xcode build). Four mechanical dogfood fixes from
the 2026-07-08 pass, one PR; `efforts/dogfood-fixes-batch-5-mechanical-polish.md`. **Schema-free.**

- **Recipe-detail layout/toolbar** — "Chef It Up" now renders below Notes (both idioms); the Focus control
  became highlighted leading chevrons with the Edit button moved leading; the Chat button *toggles* the
  iPad split (balanced ↔ reader-only) instead of only opening.
- **Recipe editor** — multiline fields auto-grow to fit content (fixes the instruction-scroll truncation;
  also Summary/Notes/Source), via a measured-height `StackedTextEditor`; **Make-Ahead + Chef-It-Up are now
  editable** with a no-clobber guard (`RecipeEditorDraft.editsMakeAheadAndChefItUp` — a save that doesn't
  touch them preserves existing values); async save + spinner (`isSaving`), Save/Cancel disabled while
  saving, no double-save.
- **Recipe search** — a shared tokenized, case/diacritic-insensitive `RecipeSearchMatcher` (all query
  tokens must match, across the fields each picker already searched) replaces `localizedCaseInsensitiveContains`
  in the Menu, Meal-Calendar, Workbench, and string-filter pickers ("Sous Vide pork" → "Sous Vide indoor
  pulled pork").
- **Web/share capture review** — title / summary / servings / total-time are editable before import on both
  hosts (in-app `RecipeCaptureView` + share extension); provenance/dedup URLs strip tracking params and the
  fragment, preferring the page's canonical `og:url`. The first cut removed the *entire* query (a dedup
  collision on query-param sites); corrected in follow-up commit `5fd2934` to a tracking-key **denylist**
  (`URLProvenanceNormalization.strippingTrackingParametersAndFragment`) that keeps meaningful params — the
  new test asserts `?id=123` ≠ `?id=456` stay distinct. Known accepted asymmetry: the parsed canonical is
  preferred verbatim, not re-stripped (trusting the site's declared canonical).

New core tests cover the matcher, the Make-Ahead/Chef-It-Up round-trip + clear, the URL strip/dedup, and
review-edits-persist-on-import. The `PreferenceKey` concurrency fix (computed `defaultValue`) is folded in.

---

## Recipe edit proposals — S2 (the "keep as a variation" commit destination — ADR-0021's build)

**Merged — yes-chef PR [#123](https://github.com/jonphillips/yes-chef/pull/123)** (backfilled into this log
2026-07-09 from the ratified ADRs; confirm detail against #123). Implements
[ADR-0023](decisions/ADR-0023-recipe-edit-proposals.md) S2, which **is** ADR-0021's build
([ADR-0021](decisions/ADR-0021-recipe-variations.md)); `efforts/recipe-edit-proposals.md`. Adds **"keep as
a variation"** as the second commit path on the *same* proposal surface built in S1 — the structured delta
the S1 extractor already produces *is* the ADR-0021 variation payload (no separate extraction; resolves
ADR-0021 OQ1/OQ2).

- **Schema (synced):** introduces the `recipeVariations` table + BLOB + migration — a synced-schema change,
  so it is on the standing production-deploy list in CURRENT_HANDOFF.
- The **reader fold** — a selected variation renders highlighted-in-place over the base recipe (add / change
  / remove).
- The **grocery fold** — deterministic, per [[llm-vs-determinism-surface-boundary]] (the variation delta
  folds into the grocery list without an LLM).
- Resolves **ADR-0023 OQ3**: overwriting a recipe that already carries variations must re-validate/rebase or
  warn, since the delta anchors on base-ingredient identity (the conservative overwrite-block).

---

## Recipe edit proposals — S1 (the "Adjust this recipe" verb + section-aware overwrite/undo)

**Architect-reviewed + Jon device-passed 2026-07-07** — yes-chef PR #122 (this slice). Implements
[ADR-0023](decisions/ADR-0023-recipe-edit-proposals.md) S1 (which extends
[ADR-0021](decisions/ADR-0021-recipe-variations.md)); `efforts/recipe-edit-proposals.md`. **Schema-free** —
no migration, no synced column. The **first chat verb that edits a recipe's canonical ingredients/method**
(Make-ahead/Chef-It-Up/Serve-With only ever wrote additive sidecar sections; the workbench draft only
*creates*). Made safe by construction: the model writes only to a transient preview, never to a stored
recipe, until a human tap.

Landed as two passes on branch `codex/adjust-recipe-s1`. **Pass 1** built the primitive: a `.adjustRecipe`
apply-action on `RecipeDetailModel.applyActionCatalog` (so it lands on **every recipe and the workbench
working recipe** at once, ADR-0023 D1); a **delta extractor** (`RecipeAdjustment.swift`) mirroring
`WorkbenchDraftRecipeClient` that emits a **structured delta** in ADR-0021 D2's closed op vocabulary
(`add`/`remove`/`substitute`/`scale` + prose method note / whole-step replacement — never a re-blended
recipe, [[llm-curation-not-synthesis]]), `high` effort with a `maxTokens: 16_384` budget that covers
reasoning **and** output and throws on truncation ([[reasoning-budget-starves-output]]); a **side-by-side
review** (`RecipeAdjustmentReviewView.swift`) reusing `WorkbenchCompare` canonical-name alignment (full-screen
cover on iPad, sheet on iPhone); and **overwrite-in-place** guarded by a **device-local, in-memory,
sync-excluded** one-level undo restore point (`RecipeBundleCoding` snapshot — the pristine `originalSnapshot`
provenance column is left untouched, ADR-0023 D5).

**Pass 2 (section-aware revision)** fixed the pass-1 limitation that only the *first* ingredient/instruction
section was edited (it round-tripped through a single `ingredientText`). It now mutates the detail's
`[IngredientLine]`/`[InstructionStep]` arrays **in place across all sections**, preserving each line's
`id`/`sectionID`/`sortOrder` (the ID-preservation S2 variation-anchoring wants); adds an optional `sectionName`
to the `add` op (case-insensitive match, else first section); a private `replaceEditableChildren` multi-section
overwrite/restore writer (atomic delete+insert of the recipe's own children — general notes only, so
provenance/photos/tags/categories/source/adaptation notes stay untouched); and a **latent-bug fix** to
`restoreRecipeAdjustment` so undo restores the **full multi-section** recipe instead of collapsing it to one
section. Core-tested (`RecipeAdjustmentTests` — cross-section apply, two-section overwrite, and the
two-section undo that broke before). **OQ4 held**: the plain-recipe and workbench-working-recipe paths are the
same `Recipe`+delta code, no fork. Review caught + fixed a `file_length` overflow (structs/methods split into
`RecipeDetailModel+Adjustment.swift`) and a `.first`-without-fallback build regression before merge.

---

## LLM-aligned Compare matrix (ADR-0022) — shipped S1–S4 + Compare→chat affordance

**Architect-reviewed + merged 2026-07-07** — yes-chef PRs [#116](https://github.com/jonphillips/yes-chef/pull/116)–[#120](https://github.com/jonphillips/yes-chef/pull/120).
Implements [ADR-0022](decisions/ADR-0022-llm-aligned-compare-matrix.md) (now **Accepted**), the semantic
upgrade to the Workbench Compare matrix; `efforts/compare-alignment.md`. **S1** ([#116](https://github.com/jonphillips/yes-chef/pull/116))
was a no-LLM **parse/key fix** that stands alone and improved the deterministic fallback: fixed the
singularizer `chilies → chily` bug and a dual-unit quantity leak. **S2–S4** ([#117](https://github.com/jonphillips/yes-chef/pull/117)/[#118](https://github.com/jonphillips/yes-chef/pull/118)/[#119](https://github.com/jonphillips/yes-chef/pull/119))
built the **LLM aligner**: clusters ingredient rows by culinary role (chicken breast ≡ thigh;
`chile`/`chiles`/`chilies` collapse to one row; `morita` ≈ `chipotle`) and orders by role ("protein at
top"), structured-out with verbatim cells, cached per candidate-set, with the deterministic `comparisonKey`
as the fallback when the LLM is unavailable. The **boundary** held: the LLM drives *presentational*
alignment on the read-only, self-correcting Compare surface only — grocery consolidation stays deterministic
([[llm-vs-determinism-surface-boundary]]). [#120](https://github.com/jonphillips/yes-chef/pull/120) added a
**Compare→chat affordance** (jump from the matrix into workbench chat) and extracted a shared
`ModelResponse.wasTruncated` (`ModelResponse+Truncation.swift`) used by both the aligner and the draft verb.
The prior-session review's two open questions (content-hash vs. identity for the cache; keep-or-split the
chat rework) were both resolved — the chat rework was split into its own PR (#120).

---

## Compare-key granularity — coarser matrix key, grocery key untouched

**Merged 2026-07-07** — yes-chef [PR #114](https://github.com/jonphillips/yes-chef/pull/114);
`efforts/comparison-key-granularity.md`. A second, coarser `CanonicalIngredient.comparisonKey` that the
Workbench Compare matrix aligns on so `fresh`/`frozen`/`dried` variants share one base row with the form
shown in the cells. The grocery canonical key is **untouched** (determinism-at-merge preserved); no schema.
Core-only. This became the *fallback* that ADR-0022's LLM aligner sits on top of.

---

## Recipe Workbench — S4 (Compare: ingredient-diff matrix + Full flip-through)

**Merged 2026-07-07** — yes-chef [PR #113](https://github.com/jonphillips/yes-chef/pull/113);
`efforts/recipe-workbench.md`. Completes the Workbench build arc **S1–S4**. App-layer only — no migration,
no new fetch, no sync touch. A pure `WorkbenchCompare.ingredientComparison` read (`WorkbenchCompareCore.swift`)
with unit tests, rendered by a responsive `WorkbenchCompareView` (full-screen cover on iPad via the
`.detailOnly` focus pattern, sheet on iPhone), reached from a **Compare** button in the Candidates header
(enabled at ≥2 comparable recipes). Two segments behind one entry point: the **Ingredients** aligned matrix
(canonical-name rows, working recipe pinned as a frozen first column, blank cell = ingredient absent) and the
**Full** whole-recipe flip-through (ingredients + directions, one recipe at a time — the parked tabbed
quick-view folded in here). Alignment is exact `canonicalName` match only; anything ambiguous drops to a
per-column "other" tail rather than force-merging (a wrong alignment is worse than an honest blank).

---

## Recipe Workbench — S3 (durable workbench log)

**Architect-approved + Jon device-passed 2026-07-06** — yes-chef
[PR #110](https://github.com/jonphillips/yes-chef/pull/110). The durable-history primitive (ADR-0019 Amdt 1):
a synced **`WorkbenchLogEntry`** table (`workbenchLog`) with an extensible
`kind: rationale | experiment | fork | observation | note`, `body`, `outcome?`, soft `relatedRecipeID?`,
`sortOrder`, `dateCreated`, cascade-owned under its workbench. Repository CRUD (add/update/delete, empty-body
guard, whitespace normalization, `dateModified` bump, `max+1` ordering) mirrors the candidate operations; a
Workbench Log section on the detail screen renders dated typed rows (edit-on-tap, swipe-to-delete) with a
manual add/edit editor; the log is grounded into `WorkbenchChatContext`; and a chat **"Save to Workbench Log"**
apply-action distills selected/latest assistant text into the log through the existing review-before-commit
surface. Ships the **store + manual/curate path first** — AI-*generated* experiment/fork entries layer on later
(new `kind` / compose path = no migration). Sync-safe (additive-nullable table, UUID PK, no unique index,
cascade FK matching `workbenchCandidates`, soft `relatedRecipeID`). 208 package tests + drift green; app-target
`xcodebuild` couldn't complete in CI (simdiskimaged crash) so the SwiftUI was closed by Jon's device pass.
Three non-blocking review notes parked in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md): the log
isn't self-trimmed against the chat-context budget (fold into on-device overflow work); `relatedRecipeID` is
plumbed but has no UI/title-snapshot yet; the chat-save path is a raw copy, not yet a distillation.

---

## Recipe Workbench — S2 (draft verb) + dogfood-hardening batch

**Architect-approved + build-green 2026-07-06** — yes-chef
[PR #107](https://github.com/jonphillips/yes-chef/pull/107). Pending Jon's device pass. **S2 draft verb**
turns a workbench into a real working recipe (the first commit surface): a synthesis apply-action + review
card writes a **new `Recipe`**, links it via `Workbench.draftRecipeID`, captures the pristine
`originalSnapshot`, and opens it in `RecipeDetailView`. New working recipes land at
`libraryPlacement: .reference` (out of default browse) with a one-tap **"Promote to library"** flip to
`.main`. The workbench task-framing string is defined **once** on `RecipeChatContext` and reused as the
spine of the draft-verb prompt so free chat and the commit path can't drift; `high` effort (ADR-0017),
curation-not-average guardrail ([[llm-curation-not-synthesis]]) enforced in the prompt.

**Dogfood-hardening rode the same branch** (206 package tests + drift green, app-target build green). Two
repos: **jon-platform** — LLMClientKit frontier `URLSession` request/resource timeouts raised (300s/600s)
so a `high`-effort synthesis isn't clipped mid-reason. **yes-chef** — draft-verb budget raised to 16k with
truncation surfaced as a real retryable error (not a silent empty draft); a persistent chat **error banner**
+ explicit timeout/offline messages; and a **remove / re-draft** affordance on the working recipe (deletes
an unpromoted `.reference` scratch draft, only unlinks a promoted `.main` recipe, always clears the soft-FK
link so drafting re-enables). Effort locked at **`high`** — dogfood-validated as a clear quality step over
`medium`. Sync-safe (UUID PKs, soft FKs + denormalized snapshots, additive migrations). Dogfood-surfaced
follow-ons parked in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md): synthesis-shaped draft
action (not gated on the last reply), AI effort/tier as a user-facing setting (ADR-0017/0018), tabbed
candidate/working-recipe quick-view. Design in
[ADR-0019](decisions/ADR-0019-recipe-design-studies.md) (whole, incl. both amendments).

---

## Recipe Workbench — chat controls (persisted tier · clear · stop)

**Architect-approved + Jon device-passed 2026-07-06** — yes-chef
[PR #105](https://github.com/jonphillips/yes-chef/pull/105). All three affordances landed in the **shared
panel** (`RecipeChatPanel`), so every chat surface inherited them at once: persisted `useFrontier` tier (new
`RecipeChatTierPreference`, mirrors `RecipeChatProviderPreference`; one global key ⇒ "remember the last model
I used anywhere"), `clear()` + confirm button (disposable scratch, no undo), and `stop()`/interrupt
(send↔stop off `isResponding`, cancellation checked on both tiers). Seam discipline held (ADR-0020) — generic
model methods + shared-panel controls, no domain pattern-match, no lift yet.

---

## Recipe Workbench — S1 + grounding fix + S1 polish

**Architect-approved + build-green 2026-07-06** — yes-chef
[PR #101](https://github.com/jonphillips/yes-chef/pull/101) (S1) +
[PR #103](https://github.com/jonphillips/yes-chef/pull/103) (grounding fix + polish). Pending Jon's device
pass. Slice 1 landed the workbench shell; the grounding fix + polish made it dogfoodable: the shared
`ChatWorkspaceSplit` now refreshes the chat model's context `onChange` (recipe/menu benefit too), editable
title, candidate-picker search, full-screen focus. Docs: `efforts/recipe-workbench.md`, ADR-0019, ADR-0020
(chat UI harvest).

---

## Menu planning overhaul (ADR-0012 Amendment 1)

**Build-green 2026-07-06** — yes-chef [PR #98](https://github.com/jonphillips/yes-chef/pull/98). Pending
Jon's device pass. All five slices shipped: tier-aware AI context + prep-plan-in-context + living-artifact
refinement · swipe-delete/move · inline meal-slot pill · full-screen focus · toolbar reorg. Drag-drop
reorder of dishes stays parked as the named follow-on (swipe-move is the interim). Effort doc
[`efforts/menu-planning-ux.md`](efforts/menu-planning-ux.md).

---

## AI configuration & transparency — ADR-0017 (model + effort) + ADR-0018 (taste profile)

**Architect-approved 2026-07-05** — cross-repo: yes-chef
[PR #96](https://github.com/jonphillips/yes-chef/pull/96) + jon-platform
[PR #23](https://github.com/jonphillips/jon-platform/pull/23) (`LLMClientKit`). **Synced-schema touch**
(new `aiSettings` table; ships to the prod schema at the next cut). Separated the two knobs that were
conflated — **model = capability floor, `reasoning_effort` = the per-task depth/cost dial** — then:

- **Model (ADR-0017 S1):** frontier OpenAI default → **`gpt-5.5`**, `gpt-5.2-chat-latest` retired. Added a
  provider-agnostic **`ReasoningEffort`** enum + `ModelRequest.reasoningEffort`; `OpenAIWire` emits a
  top-level **`reasoning_effort`** string when set and **omits it when `nil`** (Chat Completions shape).
  Anthropic/on-device ignore it. Wire test covers present-when-set / absent-when-nil.
- **Effort per feature (S2, D3 table):** assigned on **all 9 frontier call sites** — live/streaming recipe
  chat `medium` (extract-ready, Jon's call), Chef It Up / Serve With / make-ahead / prep-plan `high`,
  menu/meal complements `medium`. (The D3 table's `substitution`/`capture-parse` = `low` rows have no live
  call site — substitution was removed in PR #88; capture parse isn't a frontier `ModelRequest` — so
  9-site coverage is complete.)
- **Active model shown (S3, D4):** read-only "Active models" rows in `AISettingsView`, one per provider.
- **Taste profile at the boundary (ADR-0018 S4, D1):** promoted the lone device-local
  `recipeChatCustomInstructions` field to a **synced** taste profile stitched into `system` at the
  **`TieredModelClient`** boundary (in both `complete` and `stream`), so it reaches **every** generative
  call — closing the recipe-chat-only gap. Legacy `@AppStorage` value migrated on launch.
- **Per-task preferences (S5, D2/D3):** ~4 optional free-text fields (Chef It Up, Serve With, make-ahead /
  prep plan, complements) threaded via an opaque `promptPreferenceKey` on the request that the app maps to
  its synced settings; append **behind** the engineering prompt. Lookup tasks get no field. **No raw task
  prompts exposed** (D-rule: app owns contracts, user owns preferences).
- **Sync/schema:** new synced `aiSettings` table wired into `makeSyncEngine` **and** the schema, clearing
  the `CloudSyncTests` live-schema audit ([[extension-sync-construct-not-run]]); migration lives in the
  shared bootstrap so the share extension's DB gets it too.

Design in [ADR-0017](decisions/ADR-0017-llm-model-and-reasoning-effort.md) +
[ADR-0018](decisions/ADR-0018-prompt-customization-taste-profile.md). Non-blocking watch-items: singleton
settings row is row-level last-writer-wins across devices (fine for settings); `ReasoningEffort.none/.xhigh`
are unused and unverified against the live OpenAI wire (deferred to Jon's build, per ADR).

---

## Multi-recipe cook session — ADR-0016 (Reader-hosted, not Cooking Mode)

**Architect-approved + merged 2026-07-05** — yes-chef [PR #93](https://github.com/jonphillips/yes-chef/pull/93).
**Zero schema.** Ships a **cook session**: an ordered `[(Recipe.ID, ScaleContext)]` drawn from a planner day
*or* a menu, each recipe rendered in the **existing Reader**, with a pinned **chip-strip switcher**, a
**keep-alive** paged host (all per-recipe Readers stay mounted so switching doesn't reset scroll/scale, D4),
**session-only "done"** that shrinks the strip, keep-awake through the cook, and **per-placement `ScaleContext`
threaded** so a placement's pre-set scale flows straight through (D5). Recipe-kind items only; `.note`/
reservation rows filtered ([[menu-item-recipe-id-invariant]], D6). Entered via **"Cook these"** on a planner
day and on a Menu. Not Cooking Mode (left untouched), no voice (D7). Design + D1–D7 in
[ADR-0016](decisions/ADR-0016-multi-recipe-cook-session.md).

- **Layout fold-in** (same PR, per review): "Cook these" gave `MealCalendarDayHeader` three labeled buttons
  that overflowed the fixed-width agenda rail; wrapped in `ViewThatFits(in: .horizontal)` with a
  title-over-buttons stacked fallback, `titleBlock`/`actionButtons` extracted, `cookSession` made an optional
  closure, and the `CookSessionPresentation` build deduped into one computed prop.
- **Codex follow-up PR #94 was a wasted effort — rejected by Jon**, not merged.

---

## Cooking reader + planner follow-ons — independent reader columns + day-scoped make-ahead verb

**Architect-approved 2026-07-05** — yes-chef [PR #91](https://github.com/jonphillips/yes-chef/pull/91).
The cooking-workspace effort's queued dogfood follow-ons, two cohesive slices in one dispatch, **zero
schema**. **Slice 1 — independently-scrollable dense-reader columns:** the two-column iPad reader now pins a
fixed masthead (`header` + `metadata` above a `Divider`) over an `HStack` of two independent `ScrollView`s,
so a long ingredient list and long directions scroll separately instead of sharing one scroll. The refactor
split `recipeBody(isTwoColumn:)` into `compactRecipeBody` (picker/segmented) + a shared `directionsColumn`,
so the directions content is defined once and reused by both layouts; the narrow/segmented path is behaviorally
unchanged. Pure UI. **Slice 2 — day-scoped planner make-ahead verb:** a "Build make-ahead strategy" chat verb
over the selected planner day synthesizes a sequenced prep strategy across the day's recipes, leaning on saved
`makeAhead` notes. **Commit shape** ([[chat-verb-commit-shapes]]) = a `.note` `MealPlanItem` via the existing
`addNoteItem` — **no schema field** (ADR-0013's no-planner-container holds), `recipeID == nil` per
[[menu-item-recipe-id-invariant]]. Mirrors `complementAction`: empty `ChatApplyAction.commit`, real write in
the `ChatApplyReviewItem.commit`; parse failure degrades to empty steps → no review item → nothing written.
Structured steps (not a flattened blob) per [[llm-curation-not-synthesis]]. New `MealPlanMakeAheadStrategy`
model + `MealPlanMakeAheadStrategyClient` + parser + `MealCalendarRepository.addMakeAheadStrategyNote`, with
parse / tier-and-context-plumbing / staged-write-only-on-commit / day-ordering tests.

- **Non-blocking review note** (architect, folded forward, not filed as a bug): `MealPlanMakeAheadStep.sourceItem`
  is plumbed end to end (system prompt → JSON schema → parse → struct → test) but not yet rendered — kept as
  latent provenance for a future reconcile-against-day-items pass; a one-line comment on the field records the
  intent so raw item IDs never leak into note text. Decide keep-vs-drop when the broader Meal-Planner chat-verbs
  effort lands.
- **iPad device pass** (Jon): confirm the fixed masthead + independent column scroll feels right in both
  orientations (a tall header now permanently occupies vertical room above the columns).

---

## Chat persistence (ADR-0015) — local-only, per-subject, 1-month prune

**Architect-approved 2026-07-05** — yes-chef [PR #89](https://github.com/jonphillips/yes-chef/pull/89).
Chat is no longer ephemeral: a new local-only `chatMessages` SQLite table persists a thread **per subject**
— recipe id / menu id / planner day — so a conversation survives navigation, dismiss, and relaunch, and the
"same" subject opened from a different surface (reader vs. meal-planner) reopens the *same* thread (fixes
both "gone the minute I look away" and blank-on-surface-switch). **Local-only** — the table is deliberately
excluded from `YesChefCloudSync.makeSyncEngine`; the CloudSync live-schema audit test was amended to treat
`chatMessages` as the declared local-only exception (so the "new @Table silently stays local" tripwire stays
intact). **1-month time-based prune** — messages older than ~30 days are dropped on bootstrap and on every
chat write. Subject identity added to the recipe/menu/planner chat contexts (optional ids → graceful
"don't persist" when absent; all app call sites use the `detail:` initializers, so ids are populated).
`RecipeChatModel` loads the persisted thread on init and re-saves the whole thread in `send`'s `defer` after
the assistant text completes (empty placeholders are skipped). `RecipeChatMessage.Role` gained
`String`/`Codable`/`QueryBindable` conformances for storage. Design + resolved opens (SQLite-table-the-
SyncEngine-ignores; distill-into-the-recipe guardrail untouched — pure storage, no new nudge) in
[`docs/decisions/ADR-0015-chat-persistence.md`](decisions/ADR-0015-chat-persistence.md).

- **Non-blocking review notes** (architect, folded forward, not filed as bugs): prune uses a Swift-side
  `fetchAll().filter` rather than a SQL `where createdAt < cutoff`, so the `createdAt` index it creates is
  currently ornamental; `loadPersistedThread` runs a synchronous main-actor DB write (the prune) on every
  chat open. Both imperceptible at dogfood scale — fold into a later chat slice if chat volume grows.

---

## Reader photo affordances — set-as-cover + full-screen zoom

**Shipped 2026-07-04** — yes-chef [PR #87](https://github.com/jonphillips/yes-chef/pull/87). The cooking-
workspace effort's reader follow-on, two cohesive slices in one dispatch. **Slice 1 — manual "set as
cover":** a new nullable `Recipe.coverPhotoID TEXT REFERENCES "recipePhotos"("id") ON DELETE SET NULL`
(deleting the photo auto-nulls the cover → the `displaySortKey` heuristic resumes), resolved by a pure
`YesChefCore` cover function (override wins → else heuristic fallback for nil **and** dangling/unsynced ids),
unit-tested for the three cases; both the reader thumbnail and gallery default point at the one resolver;
"Set as Cover" / "Use Automatic" affordance. **The effort's first schema touch** — additive, nullable,
CloudKit-safe; added to the standing prod-schema promotion follow-up in `CURRENT_HANDOFF.md`. **Slice 2 —
pinch-to-zoom + pan** in `RecipePhotoFullScreenView` (`MagnifyGesture` + clamped drag, double-tap reset),
no schema. Design record in [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) §
"Reader photo affordances". (Handoff bump did not ride in #87; repaired in the batch-4 PR.)

---

## Menu actionable chat (ADR-0012) — Slice 3: complement verb → inserts a `MenuItem`

**Architect-approved 2026-07-04** — yes-chef [PR #83](https://github.com/jonphillips/yes-chef/pull/83).
The **effort's last slice — ADR-0012 is now fully complete** (S1 grounded chat #81, S2 prep-plan #82, S3
complement #83). The "what would complement…" verb: the model proposes dishes, and the tap inserts a
`MenuItem` onto the menu via the existing review card (Decision #2). Serve-With motion at menu scale; the
tap-writes invariant holds — no chat turn mutates the menu. **No schema change** — committed `MenuItem`s are
ordinary rows, already sync-safe. Design + five resolved decisions in
[`docs/decisions/ADR-0012-menu-actionable-chat.md`](decisions/ADR-0012-menu-actionable-chat.md).

- **Per-item insert commit shape** ([[chat-verb-commit-shapes]]) — one extracted payload emits **multiple**
  review cards, one per proposed dish, each committing independently. Added a second
  `AnyChatApplyAction(_:reviewItems:)` erasure initializer (the existing `renderedSummary:` single-card path
  refactored to route through it); rides the host's existing `ChatApplyReviewList` `ForEach` with **no host
  changes**. `MenuComplementClient` + `MenuComplementPlan`/`MenuComplementSuggestion`; `parse` reuses the shared
  `jsonObjectSlice ?? jsonArraySlice` idiom.
- **`MenuRepository.addComplementItem`** — a faithful analog of `addNoteItem` (requireMenu → validateDayOffset →
  `nonEmptyMenuText` → `nextSortOrder`), inserting an ordinary `MenuItem`. Wired into
  `MenuDetailModel.applyActionCatalog(for:)` alongside the S2 prep-plan action.
- **Review-feedback fix** (commit `56bc1ac`, folded before merge): the parser now **coerces every suggestion to
  `.note`** — a `.recipe`-kind row with no `recipeID` would violate the recipe⟹`recipeID` invariant the manual
  editor enforces (Save disabled without a selected recipe), rendering a book-icon row that is non-navigable and
  non-draggable. This write path can't attach a `recipeID`, so `.recipe`/`.reservation` both collapse to `.note`.
  Also removed the **dead batch-commit path** (`commitComplementPlan` / `MenuDetailError.emptyComplementSuggestion`)
  — the `reviewItems:` erasure never calls `action.commit`; each card commits via `commitComplementSuggestion`.
- **Tests:** parse (whitespace-trim, `.recipe`→`.note` coercion, slot/title drops), model-tier + menu context
  plumbing, staged no-write-until-committed-card, repository ordering + `invalidDayOffset` validation. Lean verify
  (swift test 163 green + one iPad build + check-drift).

**Non-blocking follow-up** (not a merge blocker): out-of-range `dayOffset` is only rejected at commit
(`validateDayOffset` throws on tap) — the parser can't range-check without menu context, and the review card
surfaces the error, so it's acceptable. Left as-is.

---

## Menu actionable chat (ADR-0012) — Slice 2: prep-plan verb → `Menu.prepPlan`

**Architect-approved 2026-07-04** — yes-chef [PR #82](https://github.com/jonphillips/yes-chef/pull/82).
The flagship commit verb of the Menu-scope effort and its **first schema touch**. Composes the S1 composite
grounding into a stored, staged pre-prep plan across all the menu's dishes. The tap-writes invariant holds —
extract → review card → commit, no chat turn mutates the menu. Design + five resolved decisions in
[`docs/decisions/ADR-0012-menu-actionable-chat.md`](decisions/ADR-0012-menu-actionable-chat.md).

- **Additive `Menu.prepPlan: Data?`** (Decision #1) — a Codable BLOB of
  `PrepPlanStep { when: String; task: String; sourceDish: MenuItem.ID? }`. `when` is a free-text relative-day
  label ("morning of day 2"); `sourceDish` is a **nullable** `MenuItem.ID` back-pointer. Added via `ALTER TABLE
  "menus" ADD COLUMN "prepPlan" BLOB` — byte-for-byte the `serveWith` migration pattern. Additive-nullable,
  sync-safe; BLOB→CKAsset unconditional ([[sqlitedata-blob-cloudkit-asset]]). No reserved cols, no unique index.
- **`MenuPrepPlanClient` + apply-action/review card** (Decision #4): the system prompt **composes and
  sequences the existing per-recipe `makeAhead` notes** from the S1 context and is explicit — *do not invent or
  rewrite per-dish make-ahead prose*. Vocabulary hygiene held (ADR-0006): "prep plan" ≠ "make-ahead" in copy and
  identifiers. `MenuItem.ID` now seeded into the menu chat context so the model can return `sourceDish`
  back-pointers. `parse` reuses the shared `jsonObjectSlice ?? jsonArraySlice` idiom (mirrors `MakeAheadPlan`).
- **`MenuDetailModel.applyActionCatalog(for:)`** — a faithful analog of `RecipeDetailModel+Enrichment`
  (same `[weak self]` commit, tier/context plumbing). S1 left the menu catalog empty; S2 fills it. Menu **prep-plan
  section**: timeline/checklist render, source-dish labels, **regenerate** + **clear** affordances. **Passive
  snapshot** — no auto-recompute on menu edits; `sourceDish` only makes staleness *detectable* (ADR-0010 posture).
- **Tests:** parse (nullable + malformed-drop), encode/decode round-trip, `encode([]) → nil`, model-tier + menu
  context plumbing, staged no-write-until-commit, apply/clear persistence with `dateModified`. Lean verify
  (swift test 159 green + one iPad build + check-drift).

**Non-blocking follow-ups** (not merge blockers): `MenuDetailError.emptyPrepPlan` is effectively unreachable
(`AnyChatApplyAction` already filters empty rendered summaries) — harmless defensive guard. The prep-plan
**section is hidden while empty**, so the initial build entry is the chat workspace only (Regenerate reopens
chat); a "Build a prep plan" empty-state affordance is a possible later nicety — Jon's device-pass call.
**Standing schema follow-up:** promote the `Menu.prepPlan` BLOB to the production schema before any TestFlight
cut (folded into the standing Phase E prod-schema promotion in `CURRENT_HANDOFF.md`).

---

## Menu actionable chat (ADR-0012) — Slice 1: `.menu` context + grounded chat

**Architect-approved 2026-07-04** — yes-chef [PR #81](https://github.com/jonphillips/yes-chef/pull/81).
The Menu-scope instance of actionable chat (parent ADR-0011). **S1 proves composite grounding cheaply**:
one chat context over N dishes at once, seeded and conversational, **no commit verb and no schema change**.
Critique ("what's conceptually wrong with this menu") works immediately as grounded chat — S1's payoff
(Decision #5). Design + five resolved decisions in
[`docs/decisions/ADR-0012-menu-actionable-chat.md`](decisions/ADR-0012-menu-actionable-chat.md).

- **Additive `case menu(MenuChatContext)`** on `RecipeChatContext` (`RecipeChat.swift`), mirroring
  `case recipe(...)`; every enum switch updated, no default-case shortcuts. Menu-specific prompt/header/
  provider-warning copy alongside.
- **Composite grounding serialization (Decision #4):** one structured summary per `MenuItem` — title,
  capped key ingredients, prep/cook/total times, `dayOffset` + `mealSlot`, and each recipe's **existing
  `makeAhead` note verbatim** (the only field not newline-stripped, labelled "verbatim" for the model — it
  *composes* per-recipe make-aheads, does not re-derive them). Chat order == on-screen order.
- **Budget guardrail (Decision #4):** shrink ingredient caps 8→0 across all dishes first, then drop dishes
  from the tail (sorted ascending by day/slot/sortOrder, so lowest-`sortOrder`/earliest dishes are preserved
  longest). Any truncation is **always noted in the seeded context**, never silent.
- **Wired the existing context-general split** (`ChatWorkspaceSplit`) into the Menu screen with an
  **empty apply-action catalog** + compact chat-sheet fallback — a faithful mirror of `RecipeDetailView`'s
  wiring. `recipeIngredientLines` added to the `MenuItemRowData` **read-model only** (no `@Table`, no
  migration → sync-safe by construction). Shared system-prompt copy generalized "…edited or saved the recipe
  yourself" → "…anything yourself" for the composite subject.
- **Tests:** menu-chat serialization (dish summaries + verbatim multi-line make-ahead), budget-truncation
  notes (both notes fire; earliest dish survives, latest dropped), and menu-ingredient read-model plumbing.
  Lean verify (swift test + one iPad build + check-drift).

**Non-blocking follow-ups** (not merge blockers): `MenuDetailRequest` loads the full `IngredientLine` table
then filters in memory — consistent with the pre-existing `Recipe.fetchAll` in the same function, but a `.where`
candidate to fold into the parked `m1-s3-deferred-review-nits` fetch cleanup. Sort comparator is duplicated
across `MenuItemRowData` and `MenuChatItemContext` (distinct types; a shared helper is optional). Device pass
(iPad regular-width split reveal + Chat button + compact sheet) is Jon's.

---

## Phase E — grocery/pantry, Slice 4: `PantrySuppression` + grocery-list review section

**Architect-approved 2026-07-03** — yes-chef [PR #80](https://github.com/jonphillips/yes-chef/pull/80).
The milestone's **payoff and final slice** — no schema change, consumes the Slice 3 columns. **This
completes the grocery/pantry milestone** (last box ticked in
[`docs/milestones/grocery-consolidation-and-pantry.md`](milestones/grocery-consolidation-and-pantry.md)).
Design rationale = [[grocery-pantry-threshold-design]].

- **Pure `PantrySuppression.evaluate(list:policies:)`** over the consolidated list → `{ shown,
  assumedInPantry, needsReview }`. Unlimited → `assumedInPantry`; threshold total **over/incomparable** →
  `needsReview`; threshold **under** → `assumedInPantry`; `alwaysConfirm` → `shown`. Runs on the cross-recipe
  consolidated total; incomparable units **fail safe to surfacing**; no model call on the path. Both sides key
  through the one `CanonicalIngredient.canonicalName` normalizer.
- **Add-back is one-shot, per-list, in-memory** — `pantryAddBackItemIDsByListID` moves a row to `shown` for
  that list only and never edits the pantry item's policy (Decision #7). Cleared when the item is deleted.
- **UI:** promoted **"You may need more"** review Section + a quiet **"Assumed in pantry"** `DisclosureGroup`
  with one-tap add-back. `isPurchased` never written (assumed is a distinct derived state). Share/plain-text
  excludes assumed rows. Empty-section guard moved into `GroceryItemsSection` — no stray headers.
- **Tests (pure, no UI/model):** unlimited never shown; threshold under hidden / over surfaced; cross-recipe
  total over threshold; incomparable units surface; add-back moves one row to `shown` and leaves policy
  untouched. CI green (153 tests + SwiftLint).

**Non-blocking follow-ups** (fold into a later grocery slice, not merge blockers): review headline uses a
hyphen vs the spec's em-dash `— X (total)`; `thresholdUsesCrossRecipeConsolidatedTotal` hardcodes the total
rather than deriving it from its sources (it exercises threshold-on-total, the right unit for this function,
not the consolidation summation itself). Standing Slice-3 release follow-up still applies: promote the pantry
+ `canonicalName` CloudKit fields to the **production** schema before any prod/TestFlight cut.

---

## Phase E — grocery/pantry, Slice 3: pantry policy model + `canonicalName` cache migration

**Architect-approved 2026-07-03** — yes-chef [PR #79](https://github.com/jonphillips/yes-chef/pull/79).
The milestone's **single synced-schema change**, carrying both the pantry policy columns and the
`canonicalName` cache deferred out of Slice 1. Milestone build order:
[`docs/milestones/grocery-consolidation-and-pantry.md`](milestones/grocery-consolidation-and-pantry.md).

- **Pantry policy on `PantryItem`.** New `PantryPolicy` enum (`unlimited` / `threshold(qty,unit)` /
  `alwaysConfirm`) over three columns: `isUnlimited: Bool` (default **true**), `thresholdQuantity: Double?`,
  `thresholdUnit: String?`. `storageValues`/`normalized` re-validate on both write and read, so threshold 0
  or a non-measure unit collapses to `alwaysConfirm`. Threshold offered only for volume/weight units
  (`canUseThreshold`, enforced in core **and** the editor UI). Static rule only — no depletion/inventory.
- **The `canonicalName` cache.** Added to `IngredientLine` / `GroceryItem`, populated at parse/generation
  and backfilled by `GroceryCanonicalNameCache.backfill`; `canConsolidate` / `isPantryStaple` re-pointed at
  the cached column with a `canonicalName ?? compute` fallback so nil rows still resolve.
- **Editor UI:** new `PantryViews.swift` — segmented *Always have it / Remind me / Always confirm*; quantity
  field hidden for count units; row summary shows the policy.
- **Sync-safe:** additive columns, UUID PKs untouched, no unique index. The one non-null column uses
  `NOT NULL ON CONFLICT REPLACE DEFAULT 1` so an older-schema peer's record backfills to `unlimited` instead
  of aborting the insert ([[sqlitedata-blob-cloudkit-asset]]).

**Two device-pass / release follow-ups** (flagged in the PR, not merge blockers): (1) the app target
(`PantryViews.swift` + `GroceryViews.swift`) was not compiled in this environment — Jon's build/device pass
covers it; (2) promote the new CloudKit fields to the **production** schema before any prod/TestFlight cut.

---

## Phase E — grocery/pantry, first dispatch: Slice 1 + Slice 2 (canonical key + `Measure`)

**Architect-approved 2026-07-03** — yes-chef [PR #77](https://github.com/jonphillips/yes-chef/pull/77).
Both pure-core `YesChefCore` slices in one PR, no UI, no schema migration (the `canonicalName` cache
column stays deferred to Slice 3 per the 2026-07-03 architect amendment). Milestone build order:
[`docs/milestones/grocery-consolidation-and-pantry.md`](milestones/grocery-consolidation-and-pantry.md).

- **Slice 1 — one canonical key + data alias table.** New `CanonicalIngredient.canonicalName(_:)` is the
  single normalizer (case/diacritic fold, hyphen-collapse, leading-descriptor strip, light
  singularization) with a **data** alias table (anchovy variants → `anchovies`, scallion/green onion,
  tomato pair). `canConsolidate` and `isPantryStaple` re-pointed at it; the `anchovy` `switch`,
  `groceryConsolidationKey`, and `normalizedPantryText` all deleted (zero dangling refs). Computed on read.
- **Slice 2 — bounded `Measure` compare/merge.** Known units → dimension (volume/weight/count) with
  conversion factors; `merged` combines same-dimension known units (`8 oz + 1 lb → 24 oz`) and, after
  review, **same-string units even when unknown to the table** (`splash + splash`); `compare → .over /
  .underOrEqual / .incomparable`. Cross-dimension pairs stay separate, no invented factors.

Review caught one regression before merge: the first cut required both units be in the dimension table,
so identical-but-unknown units (head/sprig/stalk/splash) stopped consolidating — a behavior the
`keep-incompatible-separate` test had locked in. Codex fixed it (859576f "Fix same-unit grocery measure
merging") to merge equal normalized unit strings and flip the wine assertion to a single merged row.
Codex authored; architect reviewed. Verified: `swift build`/`swift test` green, check-drift clean.

---

## Dogfood fixes — batch 3 (ingredient structure · Chef It Up + Serve With · substitution · keep-awake)

**Architect-approved 2026-07-03** — yes-chef [PR #75](https://github.com/jonphillips/yes-chef/pull/75).
Four cohesive slices in one PR, all from Jon's 2026-07-03 dogfooding. Effort doc:
[`docs/efforts/dogfood-fixes-batch-3.md`](efforts/dogfood-fixes-batch-3.md).

- **Slice 1 — ingredient list honors headers/sections/spacing.** `ingredientLineList` stopped
  hardcoding `"• "` on every line: `IngredientLine.isHeader` renders as a bold, bullet-less heading;
  `IngredientSection.name` renders as a subsection heading with spacing (`ingredientGroups`). The editor
  exposes the first section's title plus a per-line Header toggle; out-of-scope sections round-trip
  untouched. No schema change — the model already carried it.
- **Slice 2 — AI verbs Chef It Up + Serve With, verb buttons collapsed to an "Apply…" `Menu`.** Both
  mirror the make-ahead pattern end-to-end (additive-nullable `Recipe.chefItUp: String?` /
  `Recipe.serveWith: Data?`, structured extract client + pure commit op + catalog entry + own reader
  section with clear-as-undo). Serve With is a `{title, note}` accompaniment **list** with identity
  (`ServeWithItem.id`), each independently removable — *not* a Recipe row (promote-later seam left open).
- **Slice 3 — ingredient substitution, per-line, reveal-on-tap.** Additive-nullable
  `IngredientLine.substitution: String?`; a subtle swap glyph reveals the sub inline so the list stays
  scannable. Entry is from the ingredient row ("Find Substitute"), model proposes → explicit review sheet
  → tap writes `line.substitution`; manual set/clear via the editor. Clear = undo.
- **Slice 4 — keep the screen awake in the cook/reader presentation only.** New
  `keepsScreenAwakeWhilePresented()` modifier disables the idle timer while `.active`, restores it on
  background (`scenePhase`) and disappear; applied to `RecipeReaderView` + `CookingModeView`, not global.

New sync-safe columns (all additive-nullable, no unique index, UUID PKs; `serveWith` BLOB syncs as a
CKAsset like `originalSnapshot`, [[sqlitedata-blob-cloudkit-asset]]). Codex authored; architect reviewed.
Verified: `swift build` clean, `swift test` 135 pass (new enrichment-parse, commit/independent-undo,
substitution-write, and editor-structure round-trip tests), check-drift clean. Non-blocking notes handed
to Jon's device pass: keep-awake re-assert when backing out of cooking into the still-present reader;
read-only substitution review sheet; editing a line's text drops its metadata; incidental `viewScale`
preservation on edit. Menu/Meal-Planner chat verbs and reader photo affordances remain later efforts.

---

## Cooking workspace — Slice B (selection-scoped apply-actions + review card)

**Architect-approved 2026-07-03** — yes-chef [PR #74](https://github.com/jonphillips/yes-chef/pull/74).
Second/final slice of the cooking-workspace effort; realizes
[ADR-0011](decisions/ADR-0011-actionable-chat-make-ahead.md) Amendment 1. Makes *what the model writes*
precise and human-chosen: a selected span (or the whole last reply as fallback) drives extraction, and
nothing lands in the reader until a review card is committed.

- **Type change** (`RecipeChat.swift`): `ChatApplyAction.extract` / `AnyChatApplyAction.run` go from
  `(_ messages: [RecipeChatMessage])` to `(_ selection: String, _ context: [RecipeChatMessage])`; `run`
  now returns `[ChatApplyReviewItem]` and **no longer commits** — commit is deferred to the review card.
  The make-ahead extractor takes `selection` as the primary subject, conversation as background
  (per-verb context scope, Amendment 1).
- **Selection arms the action bar** (`RecipeChatWorkspace.swift`): assistant messages render in a
  selectable text view; a selection targets that span, **empty selection falls back to the whole last
  assistant reply** (precision override, never a dead-button gate). The bar shows what it will act on.
- **Review-before-commit card**, inspector-resident: tapping an action runs `extract`, stages the decoded
  result as a Commit / Discard card; Commit lands in the reader in place, no chat turn writes on its own.
  Staged as a **list** (N=1 for make-ahead today) so Menu's multi-card motion slots in later without a
  rewrite — multi-card UI itself not built.
- **Action-verb strings folded off the action** (`extractingTitle` / `committingTitle` /
  `committedTitle`), retiring Slice A's hardcoded `"Saving make-ahead…"` / `"Saved to Make-ahead"`.
- **Architect-review fix folded into the PR:** selection was resolved against the raw markdown string
  while the text view displays the parsed string, garbling selections over any formatted reply and
  resetting in-progress selections on re-render; now read from the displayed text and compared
  rendered-to-rendered.

Codex authored the implementation; ran out of credits before the PR, so the architect reviewed, fixed,
and opened it. Verified: `swift build` clean, `swift test` 131 pass (incl. new
`stagedMakeAheadReviewItemWritesOnlyWhenCommitted` proving `run` stages nothing to the DB — only
`item.commit()` writes), check-drift clean. App target build + device UI pass are Jon's.

Effort doc: [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) § Slice B — **effort now
complete** (Menu/Planner chat verbs + reader photo affordances named there as later efforts).

---

## Cooking workspace — Slice A (the split + dense reader)

**Architect-approved 2026-07-03** — yes-chef [PR #73](https://github.com/jonphillips/yes-chef/pull/73).
First of two slices; implements [ADR-0011](decisions/ADR-0011-actionable-chat-make-ahead.md). Re-presents
`RecipeDetailView` from a photo-forward reader + chat `.sheet` into a **detented draggable split**.

- **Split host, context-general.** New `RecipeChatWorkspace.swift`: a `ChatWorkspaceSplit` that takes a
  `RecipeChatContext` + a `(RecipeChatModel) -> [AnyChatApplyAction]` catalog closure (not welded to
  `RecipeDetailView`), a visible grabber that snaps to three detents (reader-only / balanced / chat-dive)
  with per-device `@AppStorage` persistence and a VoiceOver adjustable cycler. `RecipeChatModel` re-hosted
  from the sheet into the inspector pane; chat behavior unchanged. iPad-only split; iPhone keeps the sheet.
- **Width-responsive reader.** `RecipeReaderView` renders off its own width, not device class: dense
  two-column (ingredients | directions) ≥ 640pt, segmented ingredients/directions toggle below — so the
  chat-dive detent reuses the narrow layout instead of a third design. Scale control lives in the toolbar.
- **Polish pass (Jon's device feedback, same PR):** thumbnail → reused `RecipePhotoGallery` sheet →
  full-screen enlarge (reference-document scans now included in `displayablePhotos`); chat host wording
  driven off `RecipeChatContext` (subject / prompt / context-header copy); duplicate AI-tier selector
  removed from the split (embedded-header only); **Focus toggle** collapses the recipe-list column to
  `.detailOnly` via `NavigationSplitViewVisibility`.
- **Deferred to Slice B / roadmap:** action-verb strings still hardcoded (`"Saving make-ahead…"` — Slice B
  reshapes that surface); reader photo affordances (manual set-as-cover, pinch-zoom) → effort doc roadmap.

Effort doc: [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) § Slice A.

---

## Dogfood fixes — batch 2 (multiplier clip + AI provider picker)

**Merged 2026-07-03** — yes-chef [PR #71](https://github.com/jonphillips/yes-chef/pull/71). Two
design-free slices; ran in parallel with the cooking-workspace design.

- **Slice 1 — full-screen scale-multiplier clip fix:** the scale control no longer clips off the bottom
  in the full-screen recipe presentation (tactical fix; the cooking-workspace effort relocates the
  control to the toolbar structurally).
- **Slice 2 — AI provider picker:** `AISettingsView` now holds both a Claude and a ChatGPT (OpenAI) key
  against the multi-provider `APIKeyStore`; a stored `RecipeChatProviderPreference`
  (`recipeChatFrontierProviderKey`) lets the recipe chat pick its frontier provider
  (`RecipeChatModel.selectedProvider` / `availableProviders` / `activeTier`). No new backend — surfaced
  LLMClientKit's existing `OpenAIModelClient`; mirrors Galavant's provider-picker shape.

Effort doc: [`docs/efforts/dogfood-fixes-batch-2.md`](efforts/dogfood-fixes-batch-2.md).

---

## Recipe-multiplier rework — Slice C (per-placement persisted scale)

**Architect-approved 2026-07-03** — yes-chef [PR #70](https://github.com/jonphillips/yes-chef/pull/70).
Final slice of the dogfood-driven multiplier rework; closes the effort.

- Additive, sync-safe scale columns via one migration (`Schema.swift`): `viewScale` on `recipes`,
  `scale` on `menuItems` and `mealPlanItems` (all default `1.0`). New `RecipeScaleCore` +
  `RecipeScaleFormatting` seam and a small injected `ScaleContext` (`.recipe`/`.menuItem`/
  `.mealPlanItem`) so `RecipeDetailModel` reads the initial factor from — and writes changes back to —
  the storage site the context names (one read/write seam, not a branch per screen). Bare-recipe scale
  round-trips through iCloud. `RecipeScaleTests` added.
- Investigation confirmed the menu/planner navigation into recipe detail; all three `RecipeDetailView(`
  constructions were routed through the `ScaleContext` seam (`RecipeLibraryView`/`MenuViews`/
  `MealCalendarViews`).

Effort doc: [`docs/efforts/recipe-multiplier-rework.md`](efforts/recipe-multiplier-rework.md) — **complete**.

---

## Recipe-multiplier rework — Slices A+B (parse fix + dial-as-multiplier)

**Architect-approved 2026-07-03** — yes-chef [PR #69](https://github.com/jonphillips/yes-chef/pull/69).
First two slices of the dogfood-driven multiplier rework; Slice C (per-placement persisted scale) remains
Next Up.

- **Slice A (unicode-fraction parse, pure `YesChefCore`):** `IngredientParser` now maps vulgar-fraction
  glyphs (¼ ½ ¾ ⅓ ⅔ ⅛ … ⅕/⅙ family) to decimals and handles spaced (`1 ¼`), unspaced (`1¼`), and
  glyph-only (`⅓`) mixed numbers via a new `mixedNumberValue` branch. `IngredientScaler.format` renders
  scaled results back as mixed-number fractions (`2 ½`) with a 0–2-decimal fallback. Focused parser/scaler
  regression tests added.
- **Slice B (dials become the multiplier):** `scalePickerChanged` sets `scaleFactor` directly;
  `setScaledServings` / target-servings math removed. Whole-number range and `nearestSelection` start at 0
  so sub-1× steps (⅓×/½×/¾×) are reachable, clamped to `minimumScale` (⅓) to block 0×. Servings became a
  read-only derived "Makes ~N" line (hidden when unparseable); picker relabeled around the multiplier and
  the 1×/2×/3× quick buttons retired.

**Review:** approved; two minor findings Jon fixed himself before merge — dead `multiplierButtonTapped(_:)`
left orphaned after the quick buttons were removed, and an inert `.disabled()` on the `.wheel` picker rows
(the real clamp lives in `scalePickerChanged`). Duplicated fraction tables across the module boundary
(`IngredientScaler.commonFractions` vs `ScaleText`/`ScaleFraction`) noted as acceptable, not a change request.

Effort doc: [`docs/efforts/recipe-multiplier-rework.md`](efforts/recipe-multiplier-rework.md).

---

## Actionable chat (ADR-0011) — Slice 2: the abstraction + make-ahead

**Slice 2 (the final slice of the actionable-chat effort), architect-approved 2026-07-02** —
yes-chef [PR #68](https://github.com/jonphillips/yes-chef/pull/68). First cross-app instance of the
actionable-chat pattern landed end-to-end in yes-chef.

- Additive `Recipe.makeAhead` TEXT column + migration (additive, sync-safe); editor-save preserves it.
- `MakeAheadPlan` + `MakeAheadPlanClient` (defensive JSON extraction, mirrors `PlaceDiscoveryClient`);
  tested `RecipeRepository.applyMakeAheadPlan` / `clearMakeAhead`.
- General `(extract → commit)` apply-action **catalog** (`ChatApplyAction` / `AnyChatApplyAction`) —
  make-ahead is verb #1, not hardcoded. Invariant held: model proposes/structures, the **tap** is the
  only write.
- `RecipeChatContext` + `RecipeChatModel` (seeded from the on-screen recipe), chat panel + "Chat"
  button + dedicated "Make-ahead" section + clear affordance in `RecipeDetailView`; editable chat
  pre-prompt in AI settings.

**Review (3 findings, all fixed on the branch before approval):** (1) HIGH — `send()` built the model
request *after* appending the empty assistant placeholder, so the frontier path put an empty-content
assistant message on the Anthropic wire (400 every turn); fixed by capturing `history()` before the
placeholder. (2) MEDIUM — apply action hardcoded `.frontier(.anthropic)` instead of the chat's tier;
fixed by threading `tier` through `MakeAheadPlanClient`, with a regression test. (3) LOW — apply errors
dumped raw enum values; fixed by extracting the shared `RecipeChatErrorText.describe`.

Effort doc: [`docs/efforts/actionable-chat-make-ahead.md`](efforts/actionable-chat-make-ahead.md).
Remaining named-but-deferred work (Galavant adoption = ADR-0031 Slice 3; jon-platform cross-app ADR =
Slice 4) lives in other repos, "after the shape holds here."

---

## Actionable chat (ADR-0011) — Slice 1: the lift

**Slice 1 of the actionable-chat lift, architect-approved 2026-07-02** (3 PRs; merge jon-platform
first). Moved the shared model-client stack out of galavant into a new home package and adopted it in
both apps — a *move*, not a copy.

- **jon-platform PR #17** — new `packages/LLMClientKit` (source of truth): `ModelClient` /
  `TieredModelClient`, Anthropic/OpenAI/on-device clients, wires, `JSONValue`, `ModelTool`, keychain
  `APIKeyStore`, full tests, EXTRACTION-NOTES row. Review verified a faithful lift: every non-`APIKeyStore`
  diff vs the `GalavantAI` originals is doc-reference retargeting only (ADR-0014→`ai-model-access.md`,
  ADR-0017/0018→`actionable-chat.md`, both present at `docs/ios/`).
- **galavant PR #48** — retire in-repo `GalavantAI`, path-dep on LLMClientKit, repoint imports
  (−1,900 net). No leftover `import GalavantAI`.
- **yes-chef PR #67** — delete minimal `ModelClient` / `ClaudeAPIClient` / `ClaudeAPIKeyStorage`, adopt
  the package's `APIKeyStore`, wire `TieredModelClient.live` (−511 net). No dangling refs.

Adopters use a relative path dep (`../../../jon-platform/packages/LLMClientKit`) — harvest-now/
converge-later (ADR-0007); converging to a versioned dependency is a later follow-up.

**Known one-time cost (accepted, not fixed):** LLMClientKit's `APIKeyStore` migrates galavant's legacy
keychain service but not yes-chef's old one (service `com.jon.yeschef.ai.anthropic` / account
`claude-api-key` → now `com.jonphillips.llmclientkit.apikeys` / account `anthropic`). Existing yes-chef
installs must re-enter the Claude key once per device. Accepted — private app, recoverable, not worth code.

---

## Dogfood fixes — batch 1

**Slice 6 (PR #62), architect-approved 2026-07-02.** A **Share List** action in the grocery
detail actions menu (`GroceryViews.swift`) via native `ShareLink`, backed by a pure
`GroceryListPlainTextRenderer` (`YesChefCore`, subject = list title). Grouping/order come from
the same `selectedItemRows` the detail view sections use, so shared text mirrors the on-screen
To Buy / Purchased split exactly; quantity+unit, then title, with aisle/notes in parens.
Sync-safe (no persistence/schema change), fixture-tested (grouping + empty cases); package + 2
new tests green. Review found no blockers. Authored by Jon directly (Codex out of tokens).
*Non-blocking:* the `selectedListShareText` nil-list fallback is dead code (menu only renders
inside `if let selectedList`; `selectedListRow` is nil only with zero lists). When Phase E
store-section grouping lands, extend the renderer to reflect sections.

**Slice 5 (PR #61), architect-approved 2026-07-02.** Pinned the recipe-list search drawer via
`.searchable(placement: .navigationBarDrawer(displayMode: .always))` on the shared
`RecipeListView` so search no longer scrolls away with the list. One-line, idiomatic view change
— reuses the existing `.searchable` binding, no new state/scroll-tracking/custom control; applies
to both `.navigation` and `.selection` hosts and doesn't conflict with the top `safeAreaInset`
status bar. Both iPad/iPhone sim builds + `check-drift.sh` (111 core tests) green; no blockers.

**Slice 4 (jon-platform PR #16), architect-approved 2026-07-02.** Trailing `xmark.circle.fill`
clear button on the shared `WebExtractorKit` `WebBrowserView` address bar
(`packages/WebExtractorKit/Sources/WebExtractorKit/WebBrowserView.swift`). Shipped in
**jon-platform** (shared browser chrome), not this repo. Visibility: `!addressText.isEmpty` while
editing, `page.url != nil` when not; `clearAddress()` empties the field and focuses it, and the
predicate then flips so the button hides itself right after clearing. No blockers — clean, minimal
view chrome. No new test (pure view logic; rides the manual sim verification). Non-blocking: when
a page is loaded the X is a persistent "start a new navigation" affordance, not an edit-clear —
matches the dogfood ask.

**Slice 3 (PR #60), architect-approved 2026-07-02.** Archive-means-gone: archiving a recipe
deletes its meal-plan and menu-dish placements in the same sync-safe write, guards the
calendar/menu/detail resolution paths against archived references, renames the destructive action
to **"Archive"**, and adds a **Settings ▸ Archived Recipes** view to restore (recipe only) or
permanently purge (FK-cascading delete). Also folded in the two Slice 2 review items: the
`presentationBinding` helpers deduped into shared `gatedBinding` free functions, and the modal
"OK" add-confirmations became a root-level `@Observable` **toast** (haptic + VoiceOver +
Reduce-Motion). **Review found two blockers, both fixed on-branch:** (1) the toast was occluded by
the full-screen recipe cover — resolved by also rendering the shared toast overlay inside
`RecipeFullScreenCover`; (2) `xcodegen` had swept a bundle-ID flip
(`com.jonphillips`→`com.jon`) + scheme churn into the pbxproj — resolved by realigning
`project.yml` back to `com.jonphillips.yeschef` (preserving app identity + the
`iCloud.com.jonphillips.yeschef` container) and adding a `check-drift.sh` guard. 111 core tests
green. **Non-blocking watch item:** two `.sensoryFeedback` modifiers now observe the same toast
trigger, so adds from a full-screen recipe may double-buzz — eyeball during dogfooding and gate one
if noticeable. *(This slice is a good example of batching working: it did multiple cohesive things
in one clean dispatch.)*

**Slice 2 (PR #59), architect-approved 2026-07-02.** The meal editor locks to the viewed recipe
when launched from recipe detail (`MealPlanItemDraftContext.locksRecipeSelection`), and
add-to-meal / add-to-grocery fire in-context confirmations via the Slice 1 gated presenters.
Correct and consistent with Slice 1; no blockers. One UI-pass watch item: the confirmation is a
sheet→alert handoff on the same host (the app already proves this works via the capture-summary
alert), and Slice 3 retires it entirely by moving to a root-level toast.

**Slice 1 (PR #58), architect-approved and merged 2026-07-02.** Add sheets + all six
full-screen-recipe toolbar affordances (Add-to-Grocery, Add-to-Plan, Edit, Start Cooking, View
Original, Delete) present in-context via the shared gated-presenter pattern in
`AppDestinationPresentation.swift` (root presenters gated on `presentedRecipeID == nil`,
re-attached ungated inside `RecipeFullScreenCover`). Also updated the active-simulator target to
`iPad Pro 13-inch (M5) (16GB)`.

---

## Reader Feedback

**Slice 4 — Claude API client + Keychain key storage (PR #57), architect-approved 2026-07-02.**
The app's first LLM integration: a domain-free `ModelClient` boundary + minimal Claude Messages
API wire client in `YesChefCore` (injectable `Transport`, no network in tests, 114 tests green)
plus app-side `ClaudeAPIKeyStorage` (synchronizable iCloud-Keychain generic-password item,
`kSecAttrAccessibleAfterFirstUnlock`, never logged), a **Settings ▸ AI** pane with save/clear, and
`modelClient` wired to read the Keychain key at call time. **Architect review changed the default
model `claude-fable-5` → `claude-opus-4-8`** (commit `8b3b817`): Fable 5 returns 400 under
zero-data-retention orgs, costs 2×, and runs bio/cyber refusal classifiers — none of which fit a
personal-key recipe app; Opus 4.8 is the standard default and per-request override via
`ModelRequest.model` is unchanged. **Non-blocking, deferred to Slice 5:**
`ClaudeAPIClient.complete` branches only on HTTP status, so a 200 response with
`stop_reason: "refusal"` (or `max_tokens`) yields silent empty text — guard or document when the
extractor consumes it. Keychain iCloud sync is intentional (multi-device dogfooding).

**Slice 3 — NYT comment capture playbook + host-keyed extractor (PR #56), architect-approved
2026-07-02.** Host-keyed **"Load Comments"** action in `BrowserWorkspaceView` (separate from
Capture) driving a bounded NYT playbook (`BrowserCommentLoadingPlaybook` in `RecipeModels.swift` —
clicks Most Helpful, then "Show more comments" ≤4×, keyed on `cooking.nytimes.com`), plus a pure,
fixture-tested `RecipeReaderCommentExtractor` (`YesChefCore`, SwiftSoup, no WebKit) producing
`[RawComment { text, helpfulCount }]`. Architect verified the fixture math (76 cards/bodies/count
spans 1:1, full-integer counts, distinct-class reply not double-counted) and that anonymization is
structural (reads only `note_noteBody__ > p`, never the owner span). Keys on stable structure, not
hash suffixes. Extractor is intentionally dormant (test-only) until Slice 5 wires it into review.
**Non-blocking follow-ups deferred to Slice 5:** (a) strengthen the anonymization test (`contains`
a placeholder substring, not whole-text `==`); (b) comment the `helpfulCount` digit-filter
assumption that counts render as full integers, not abbreviated `"6.3K"`.

**Slice 2 — harvest the real NYT comment-thread fixture — DONE (architect sanitization step, not a
PR/Codex slice; 2026-07-01).** Jon captured the authenticated "Most Helpful, fully loaded" DOM for
Lemony White Bean Soup off-device; the architect sanitized it into
`Tests/YesChefCoreTests/Fixtures/WebRecipeCapture/SanitizedSites/nyt-comments.html` (recipe JSON-LD
+ verbatim `<section id="notes_section">`, 76 cards, synthetic commenter names, JSON-LD `review`
PII array dropped, no auth material present).

**Slice 1 — review-sheet dismiss-fragility hardening (PR #55), architect-approved and merged
2026-07-01.** Destructive-confirmation `confirmationDialog` on Cancel plus
`interactiveDismissDisabled` (in-app) / `isModalInPresentation` (share extension) while a draft is
under review, driven by a new `hasUnsavedReviewChanges` on `RecipeCaptureModel`/`ShareCaptureModel`.
Architect review found `hasUnsavedReviewChanges` excluded `isCommitting`, leaving swipe-to-dismiss
enabled during the async save (and, in the share extension, through the
`waitForPendingRecordZoneChanges` sync wait) — a mid-save swipe could dismiss while the import
completed in the background and later popped an unexpected `.captureSummary` sheet. Fixed by
dropping the redundant `!isCommitting` clause (it can only be `true` while `draft != nil`, so it
added no protection, only the gap) — landed as `51cfed1` directly on `main`. 108 tests pass,
swiftlint clean.

---

## Web capture (Milk Street, cleanup, DOM export)

**Web-capture cleanup slice (PR #54), architect-approved and merged 2026-07-01.**
`WebRecipeCaptureClient.fetchImageData` now streams the hero-image download via
`URLSession.bytes(for:)`, rejecting on a declared-oversized `Content-Length` before reading the
body and enforcing the 12 MB cap against actual bytes received.
`RecipeMilkStreetExtractor.extractPrintIngredients`/`extractBodyIngredients` collapsed into one
`extractIngredients` helper parameterized by an `IngredientExtractionSelectors` struct;
heading/item lines are buffered and only committed once a real item is found in that pass, closing
the orphan-heading-leaks-into-body-fallback gap from the PR #53 review. Also picked up the
`RecipePrintTemplate_ingredientRow__*` print-row markup fallback. Non-blocking: the hero-image
download iterates `URLSession.AsyncBytes` one byte at a time (slower than a chunked read) — revisit
if hero-image hydration is ever visibly slow.

**Milk Street print-template ingredient headings (PR #53), architect-approved and merged
2026-07-01.** The print-template ingredient path now recognizes
`RecipePrintTemplate_ingredientHeading__*` rows interleaved with `ingredientItem__*` rows, walking
heading/item elements in DOM order so section names attach before their items.
`milk-street-chicken-peanut.html` extended with real-shape print-template markup. Two non-blocking
nits (orphan-heading fallback gap, extract-print/extract-body duplication) folded into the cleanup
slice above.

**Milk Street sections/Tip/summary/time (PR #52), architect-approved 2026-07-01, merged.** Real
per-recipe summary (`RecipeSummaryContent_body__*`) outranking site-boilerplate meta description,
Tip callout captured as an editorial block (`[role=note][aria-label=Tip]`), servings/prep/cook/total
time from `ItemLabelList_item__*`, and a `RecipeDurationParser` unicode-vulgar-fraction normalizer
(`"1½ hours"` → 90 min) — all fixture-tested against a sanitized `milk-street-chicken-peanut.html`.
The fourth gap (ingredient subsection headings) was a branch-selection bug, not missing markup —
fixed in PR #53.

**Revive DEBUG DOM export (PR #51), architect-approved 2026-07-01, merged.**
`preserveRawImportHTML: true` gated `#if DEBUG` at both production capture call sites; Release stays
lean (PR #45 intent preserved).

**Milk Street parser hardening (PR #50), architect-approved 2026-07-01, merged.** Meta-tag JSON-LD
reading gated on truncation-sentinel detection, a `RecipePrintTemplate_*`/`RecipeBodyContent_*` DOM
fallback extractor (`RecipeMilkStreetExtractor`, amount+description join, empty-amount tolerant), the
new `truncatedStructuredData` warning, and sanitized recovered/truncated-only fixtures. Scoped to the
original gochujang reference capture; NYT teaser regression stays green.

---

## M4 — iCloud sync

**Share-extension iCloud sync — producer wait + consumer re-drain + enablement persistence (PR #49),
architect-approved 2026-07-01, round-trip confirmed on device.** Three defects, one landable unit:
  1. **Producer race (Codex):** stopped extension engine defers the `PendingRecordZoneChange` insert
     to a fire-and-forget `Task` that `completeRequest` killed → row lost.
     `ShareCaptureModel.saveButtonTapped` now bounded-polls `pendingRecordZoneChangeCount` until the
     row lands before completing. No `start()`/networking/`aps-environment` in the extension.
  2. **Consumer drain (Codex):** the pending table only drains inside `start()`
     (`enqueueLocallyPendingChanges`, `SyncEngine.swift:645`), which no-ops when already `isRunning`.
     Added a scene-`.active` foreground re-drain that cycles `stop()`+`start()` when pending rows
     exist.
  3. **Enablement gate (folded in directly, 2026-07-01):** `isManuallyEnabled` was set only by the
     volatile Xcode launch-arg, so an icon-tap / extension-handoff launch had sync OFF and neither the
     cold-launch `start()` nor the re-drain ever ran. Proven by reading the sim metadatabase: 81
     undrained rows == 81 metadata rows with NULL `lastKnownServerRecord`.
     `persistManualEnablementFromLaunchEnvironment()` mirrors the dev flag into persistent
     `UserDefaults`. See [[extension-sync-construct-not-run]].
  Follow-ups deferred: file upstream SQLiteData issues — (a) persist the pending change in the trigger
  synchronously (`// TODO` at `SyncEngine.swift:823-838`), (b) expose a public "drain persisted pending
  changes into a running engine" entrypoint. Before the S4 Production flip, replace the dev launch-arg
  gate with a real persisted opt-in.

**Share-extension iCloud entitlement hotfix (PR #48 merged, `5e8be14`).** Added the iCloud container +
CloudKit-service entitlements to `YesChefShareExtension` (app group preserved; no `aps-environment` /
background modes). Fixes the launch crash: `SyncEngine.init` eagerly builds `CKContainer(identifier:)`
even with `startImmediately: false`, and an unentitled container threw an uncatchable ObjC exception.
Entitlement-only. Crash fixed, but round-trip still broken (see PR #49).

**Slice 3 — logical-uniqueness hardening (upsert + dedup-on-read) (PR #47), architect-approved.**
Source-backed `recipeImportRef` duplicates converge on read: pick the earliest ref deterministically
(`dateCreated` → `id` → `recipeID`), delete duplicate imported recipes, and repoint
`MealPlanItem`/`MenuItem` (`ON DELETE SET NULL`) + `GroceryItemSource` (no FK) references to the
survivor before deleting losers. Title-only collisions stay data-preserving. Same converge-on-read
pattern for duplicate default `GroceryList`, `PantryItem` titles, `Tag` names, and sibling `Category`
names. Preview path is non-mutating. 100 tests green. Non-blocking follow-ups: default-list convergence
only self-heals via `ensureDefaultList`; the merge relies on GRDB's default `foreign_keys = ON`; the
`default:` branch in `importBundle` is now dead for source-backed keys.

**Slice 2 — CloudKit `SyncEngine` wiring (started OFF) (PR #46), architect-approved.** Additive CloudKit
**dev** entitlements (iCloud container `iCloud.com.jonphillips.yeschef`, CloudKit service,
`aps-environment`, `UIBackgroundModes = remote-notification`) via XcodeGen. `attachMetadatabase()` +
`SyncEngine(startImmediately: false)` in `bootstrapDatabase` enumerating all 23 synced `@Table`s;
iCloud account-status launch gate; sync opt-in defaults **OFF**. Share extension **constructs a stopped
engine** purely to install triggers / write `SyncMetadata` — it never starts or networks (**construct ≠
run**). `categories.parentCategoryID` loosened from a self-referential FK to a plain UUID column.
On-device dev round-trip partially confirmed (in-app browser capture round-trips; synced rows live in
the Private DB custom zone `co.pointfree.SQLiteData.defaultZone`).

**Slice 1 — lean original-provenance (PR #45 merged).** `RecipeBundleCoding.snapshotData` strips
`originalImportText` and photo `displayData`/`thumbnailData` from the snapshot blob (metadata +
`imageDataReference` retained); import/capture defaults `originalImportText == nil` via a test-only
`preserveRawImportHTML` seam. Snapshot is passive provenance — no production consumer of
`decodeSnapshot`.

---

## M3 — authenticated browser capture

**M3 authenticated browser capture (PR #44 merged, `2f5b588`).**
- **Capture editorial prose blocks** ("Why This Recipe Works" / "Before You Begin") — scoped DOM scrape
  (`RecipeEditorialProseExtractor`) mapping the blocks to labeled recipe notes, schema-first parser
  untouched; `WebRecipeEditorialProseTests`.
- **Show & curate notes + hero image in the review UIs** — notes shown with inline edit + per-block
  delete, plus a read-only hero preview, in **both** the share-extension review (`ShareViewController`)
  and the in-app browser capture review (`RecipeCaptureView`). Emptied notes drop at save/bundle time.

**Fork resolved (2026-06-30):** M3 capture is done and the pivot to the **iCloud sync gate** was made.
The full build order was authored (S1 lean provenance → S2 CloudKit setup + `SyncEngine` wiring, off →
S3 dedup-on-read hardening → S4 clean cutover/flip → S5 two-device verification). Modeling stays
sync-safe and deferred (no canonical-ingredient work before the flip). Ratified by
[ADR-0010](decisions/ADR-0010-cloudkit-sync-enablement.md); M3 recorded in
[ADR-0009](decisions/ADR-0009-in-app-authenticated-browser-capture.md).

---

## Implemented-behavior checkpoint (planning/grocery slice)

Snapshot of behavior implemented as of the meal-planning / menus / grocery slice. Background context,
not a dispatch target; much of this is derivable from code.

- A durable `mealPlanItems` SQLite table and `MealPlanItem` core model; items support recipes and
  freeform notes, with a reserved `reservation` kind and optional start/end time fields.
- A month-first Meal Calendar workspace with month, week, and day display modes; add recipe/add note
  flows from the calendar, plus a `Plan` toolbar button on recipe detail.
- Durable menu schema (`menus`, `menuItems`, `menuPlacements`). Menus can contain recipe dishes and
  freeform notes, be placed on the calendar, shifted, and removed without deleting the menu. Calendar
  rows projected from a menu preserve provenance and show as menu-derived.
- Menu detail: single navigation title, slide-in recipe browser inspector with search/filter,
  day-header add buttons, recipe drops onto a day, drag-to-move between days.
- Full-screen recipe presentation from menus and meal-calendar agenda rows.
- The meal calendar optimistically reflects item date edits/deletes while SQLiteData observation catches
  up. Week calendar cells are taller on wide layouts.
- Durable grocery schema (`groceryLists`, `groceryItems`, `groceryItemSources`). Sources preserve
  recipe, menu, menu placement, calendar item, and custom origins, including source titles/subtitles and
  original ingredient text.
- A minimal Groceries section: list creation, custom items, purchased state, add-from-calendar-range,
  add-menu, add-recipe. Recipe detail groups `Plan`/`Groceries` in the toolbar; groceries opens a
  shoppable-ingredient review sheet before adding.
- `Start Cooking` flame action lives in the recipe body near servings/time.
- Generated grocery ingredients consolidate conservatively when title, unit, aisle, notes, and quantity
  shape are compatible; compatible numeric quantities add together while each origin remains its own
  `GroceryItemSource` row. Purchased items and prep/comment-sensitive rows stay separate.
- Grocery rows expose their source breakdown; each source has an actions menu that removes only that
  source (row deleted when its last source is removed; consolidated numeric quantities recalculated).
- Ingredient-selection sheet before generation for `Shop`, add-from-calendar-day, and add-menu flows; all
  shoppable lines start selected; generation can be restricted to selected `IngredientLine` IDs.
- Conservative pantry assumptions: staples (salt, pepper, water, ice, common oils, cooking spray) shown
  in a "Skipped Pantry Staples" section, deselected by default, addable with a tap. Settings exposes an
  editable Pantry list (one item per line); pantry items sort alphabetically. Quantity tracking is
  explicitly out of scope.
- The meal-calendar recipe picker supports adding multiple recipes in one save.
- Ingredient parsing avoids treating food words (red/celery/anchovy) as units, splits comma preparations
  into notes, and normalizes anchovy fillets into "anchovies".
- Core tests cover meal calendar, menus, grocery source provenance, generated grocery
  consolidation/source-removal/ingredient-selection/pantry-assumption/ingredient-parsing, menu item
  moves, and alphabetical pantry sorting.

**Deferred from that slice:** drag/drop inside the calendar grid; restaurant reservation UI;
iCal import/export/sync; rich menu editing (editing existing dishes, duplicating menus, fine-grained
ordering within a day); higher-level source-aware grocery removal; quantity-based pantry inventory;
App Intents/Shortcuts; Reminders/Siri; store/category learning; importing Paprika menus/grocery lists.

---

## Strategic context (background, not a dispatch target)

Direction for the larger work so the architect can curate Next Up; never instructs the agent.

- The storage model can represent multiple origins for one grocery row, and the UI has a first review
  step before generation. The next pressure point is making source-aware removal and skipped pantry
  staples equally legible.
- Paprika allows recipe ingredients to be chosen before adding and recipes to be removed from the
  grocery list later; Yes Chef has the ingredient-selection affordance and still needs the broader
  removal/review affordances while keeping richer provenance intact.
- Source-aware removal is the next pressure test for consolidation (a single row may contain quantities
  from several recipes, menu placements, and calendar items).
- Pantry value comes first from making skipped known staples reviewable and easy to add back, not from
  tracking exact on-hand quantities.
- Treat Grocy as inspiration for shopping locations/assortments and product/barcode workflows, but keep
  Yes Chef recipe/planning-first rather than inventory-first.
- Menu drag/drop is implemented but still needs Jon's hands-on UI pass across iPad and iPhone before
  it's treated as settled.
