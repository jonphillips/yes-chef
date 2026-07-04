# Done Log

Archive of completed efforts, the implemented-behavior checkpoint, and strategic
background. **Read-rarely, append-on-approval.** No dispatch instruction should ever
point the coding agent (or the architect during a dispatch) at this file — it is a
human-reference archive, not a working-context source. `docs/CURRENT_HANDOFF.md` stays
lean precisely because this history lives here instead.

Newest first.

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
