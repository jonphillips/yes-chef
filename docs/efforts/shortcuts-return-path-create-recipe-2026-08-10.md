# Effort: a Shortcuts / App Intent return path — clipboard text → Create Recipe review (2026-08-10)

**Type:** ADR-0053 **Amendment 2 / S3** — a headless transport (Shortcuts → App Intent) door into the existing
Create Recipe destination. **One dispatch.** No schema — the Create Recipe session is D4-transient, so nothing is
added to any table or the promotion list. A new App Intent, a small foreground coordinator, one entry in the
existing `AppShortcutsProvider`, a non-destructive seed seam, focused tests, and one operator-doc section.
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Designed.** Ships against the shipped Create Recipe destination (ADR-0053 Amd 1). Independent of any
in-flight branch.
**Source:** [ADR-0053 Amendment 2](../decisions/ADR-0053-create-recipe-destination.md#amendment-2--a-headless-transport-shortcuts--app-intent-into-create-recipe-2026-08-10)
and the architect review of Jon's ChatGPT-suggested prompt (2026-08-10).
**Summary:** Jon does most ChatGPT work on iPhone/iPad and copies the response. Today the return path is
copy → open the app → Create Recipe → paste → Extract → review → Save. This slice collapses the middle: a
`Send to Yes Chef` Shortcut runs `Get Clipboard → CaptureRecipeFromText`, the app foregrounds directly into the
Create Recipe review with the text already extracted, and the cook reviews and Saves. The transport is
**producer-agnostic** (ChatGPT is one text source among pastes, Notes, a Files hand-off) and **app-owned**: the
Shortcut only moves the clipboard string; every recipe-domain decision stays in the app, reusing the shipped
extraction engine.

**Required invariant:**

> A recipe reaches canonical state **only** through the cook's explicit Save in the Create Recipe review — never
> from the Shortcut or the App Intent. The transport stages exact text into the **transient, in-memory** Create
> Recipe session (no durable/synced row), preserves that text verbatim, and **never destroys unsaved material**
> already in an open session. The intent reuses `CreateRecipeExtraction.extract`; it introduces no second parser,
> no second "text → recipe" model call, and no URL scheme.

---

## Read before starting

- **[ADR-0053 Amendment 2](../decisions/ADR-0053-create-recipe-destination.md#amendment-2--a-headless-transport-shortcuts--app-intent-into-create-recipe-2026-08-10)** — the six decisions this dispatch implements. Amd2-D2 (right path)
  and Amd2-D4 (non-clobber) are the load-bearing ones.
- **[`YesChefApp/AppIntents/HandoffIntents.swift`](../../YesChefApp/AppIntents/HandoffIntents.swift)** — the
  pattern to **mirror, not reuse**. Note `ImportHandoffResult` (line 68), `OpenHandoffReviewIntent`
  (`openAppWhenRun == true`, line 837), and `HandoffAppShortcuts: AppShortcutsProvider` (line 116). The new intent
  is a **sibling** of these, on a different coordinator.
- **[`YesChefApp/HandoffReviewCoordinator.swift`](../../YesChefApp/HandoffReviewCoordinator.swift)** — the
  coordinator shape to mirror: a `@MainActor @Observable` final class, a `DependencyKey` `liveValue`, a
  `present(...)` entry the intent calls, consumed by the app root. The new `CreateRecipeCoordinator` is the
  Create-Recipe analog.
- **[`YesChefApp/CreateRecipeModel.swift`](../../YesChefApp/CreateRecipeModel.swift)** — the seam. `pastedTextReceived(_:)`
  (line 130) is how a paste enters the session; `extractButtonTapped()` (line 142) runs the two-tier engine;
  `isEmpty` (line ~54) and `reset()` are the state the non-clobber logic keys off. **`pastedTextReceived` overwrites
  `composeText`** — that is the clobber this dispatch must not trigger on an in-progress session.
- **[`CreateRecipeSource.swift`](../../YesChefPackage/Sources/YesChefCore/CreateRecipeSource.swift)** — the shipped
  app-owned operation `CreateRecipeExtraction.extract(text:)` (deterministic JSON-LD first, faithful LLM otherwise).
  **Reuse verbatim.** `CreateRecipeSourceItem.content` is where exact text is preserved (Amd2-D5).
- **How Create Recipe is reached today:** `AppSection.createRecipe`
  ([AppNavigationModels.swift:49](../../YesChefApp/AppNavigationModels.swift)), rendered in
  [AppMainLayout.swift:110](../../YesChefApp/AppMainLayout.swift) from a `createRecipeModel` held in
  [RecipeLibraryView.swift:16](../../YesChefApp/RecipeLibraryView.swift). The coordinator must reach *this*
  resident model and select *this* section — trace where the model and the selected `AppSection` live so the
  intent seeds the live session, not a throwaway instance.
- `CURRENT_HANDOFF.md` Verification Pattern.

---

## The context (by reading — no device repro needed)

There are two return paths in the app, and the whole risk is choosing the wrong one.

1. **Routed handoff importer** — `ImportHandoffResult` → `stageReview` → `HandoffReviewCoordinator`. It returns
   **already-decided content to an existing subject** (adjust *this* recipe, prep-plan *this* menu day), matched by
   a `handoffID` token and reconciled against that subject. Mature, with its own App Intent, shortcuts provider,
   opener intent, and coordinator.
2. **Create Recipe** — admits **a brand-new recipe with no prior identity**, on `save(draft:)`, in a transient
   in-memory session (ADR-0053).

A ChatGPT-authored recipe on the clipboard has no `handoffID` and no subject. **It is path 2.** The maturity of
path 1 is the trap: do **not** reuse `ImportHandoffResult` or route through `HandoffReviewCoordinator`. Build a
sibling intent on a new Create-Recipe coordinator.

The friction win is real and small: the operation (`CreateRecipeExtraction.extract`), the sink (`RecipeEditorDraft`),
the review, and the save all already exist and ship. This dispatch adds only the **door** (an App Intent) and the
**foreground mechanism** (a coordinator + `openAppWhenRun` opener) — copied from the handoff pattern, pointed at
Create Recipe.

---

## The findings

### Finding 1 — the intent is a sibling of `ImportHandoffResult`, on a new coordinator (Amd2-D2)

Add `CaptureRecipeFromText: AppIntent` with a single `@Parameter var text: String`. `perform()`:

1. Trim; **empty → throw** a clear `CaptureRecipeError.emptyText` (surfaced by Shortcuts). No session opened.
2. Stage the exact text into the resident Create Recipe session via the coordinator (Finding 2).
3. Return `.result(opensIntent: OpenCreateRecipeIntent())` — a sibling of `OpenHandoffReviewIntent`
   (`openAppWhenRun == true`, `allowedExecutionTargets == .main`) — so the app foregrounds on the Create Recipe
   section.

Naming: **`CaptureRecipeFromText`**, never `ImportRecipeFromChatGPT` (Amd2-D1). The App Intent `title` /
`IntentDescription` are producer-agnostic ("Capture a recipe from text").

Add it to the existing `HandoffAppShortcuts` provider (or a sibling `AppShortcutsProvider` if that reads cleaner —
one provider is fine), phrase e.g. `"Capture a recipe from text in \(.applicationName)"`, so Jon can build the
Shortcut against a discoverable intent.

### Finding 2 — `CreateRecipeCoordinator`: seed the **resident** session, non-destructively (Amd2-D4)

Mirror `HandoffReviewCoordinator`: `@MainActor @Observable final class CreateRecipeCoordinator`, a `DependencyKey`
with a `liveValue`, and a `stage(text:)` (or `receive(text:)`) entry the intent calls. The app root observes it
and, on a staged payload, **selects `AppSection.createRecipe`** and hands the text to the live `createRecipeModel`.

The non-clobber rule is the point of this finding:

- **Open session is empty** (`createRecipeModel.isEmpty`) → seed it: this is the `pastedTextReceived(text)` path,
  and **auto-run extraction** (`extractButtonTapped()`) so the app foregrounds on the reviewed structured draft,
  not a raw compose box (OQ6 lean).
- **Open session is non-empty** → **do not overwrite.** `pastedTextReceived` clobbers `composeText`, which would
  wipe the cook's in-progress material — the one thing D4 forbids. Surface the incoming text as a **new pasted
  source the cook can accept or discard** (a lightweight prompt/affordance), or park the current draft; never a
  silent replace, and never auto-extract over existing unsaved work.

Because the section's `createRecipeModel` currently lives inside `RecipeLibraryView`, wiring the coordinator to it
is the fiddly part — trace the ownership (Read-before list) and lift/observe as needed so the intent reaches the
**live** session. If the model must be hoisted to be reachable from the coordinator, that hoist is in scope; keep
it minimal.

### Finding 3 — reuse the engine and the foreground pattern; add no parser, no URL scheme (Amd2-D3)

- Extraction is `CreateRecipeExtraction.extract(text:)`, invoked through `extractButtonTapped()`. **Do not** parse
  JSON-LD, strip fences, or make a second model call inside the intent — that is the ADR-0051 D7 review block.
- Foreground via the `openAppWhenRun` opener intent + coordinator, exactly as the handoff path does. **Do not add a
  `yeschef://` URL scheme** — none exists, and the coordinator already does the job (Amd2-D3).

### Finding 4 — preserve exact text; stay menu-unaware (Amd2-D5)

The staged text lands verbatim in `CreateRecipeSourceItem.content`. Do not normalize or re-encode it, so a future
`YC-HANDOFF`/menu-day marker survives for later provenance work. This intent picks **no** menu and **no** day and
adds no provenance schema; menu/day association, when built, rides the *handoff* path (which already carries
`sourceID`/`dayOffset`), not this door.

---

## The dispatch

One PR. New files under `YesChefApp/AppIntents/` and a coordinator beside `HandoffReviewCoordinator.swift`.

1. **`CaptureRecipeFromText: AppIntent`** (+ `OpenCreateRecipeIntent`, + a `CaptureRecipeError`) — sibling to
   `ImportHandoffResult`/`OpenHandoffReviewIntent`.
2. **`CreateRecipeCoordinator`** — `@MainActor @Observable`, `DependencyKey` liveValue, `stage(text:)`, observed by
   the app root to select `AppSection.createRecipe` and seed the live `createRecipeModel` per Finding 2.
3. **App-root wiring** — observe the coordinator, select the section, apply the non-clobber seed. Hoist
   `createRecipeModel` to a reachable owner if required (minimal).
4. **Shortcuts provider entry** for the new intent.
5. **Operator doc** — the "Faster return path with Shortcuts" section (below).

### Tests (app target — `YesChefTests`; the intent + coordinator seeding are the core)

1. **Empty text throws.** `CaptureRecipeFromText(text: "   ")`.`perform()` throws `emptyText`; no session staged.
2. **Fresh session seeds and extracts.** Coordinator `stage(text:)` on an empty model → the text is the pasted
   source (`sources` holds one `.pastedText` with the **exact** content), extraction ran, structured draft present.
   Assert **no** canonical `Recipe` row was written (D4) — staging and extraction do not save.
3. **Exact text preserved** (Amd2-D5). Stage text containing a code fence and a `YC-HANDOFF`-style marker →
   `CreateRecipeSourceItem.content` equals the input byte-for-byte (not the fence-stripped extraction).
4. **Non-empty session is not clobbered** (Amd2-D4 — the point). Model with unsaved compose text / a partial draft
   → `stage(text:)` does **not** overwrite `composeText` and does **not** discard the draft; the incoming text is
   offered as a new source (assert the existing material survives).
5. **Deterministic-JSON-LD text extracts without a model** — stage a schema.org `Recipe` JSON-LD block (optionally
   fence-wrapped) → the deterministic tier produces the draft (reuse an existing capture fixture; this asserts the
   engine is reused, not re-implemented).
6. **Non-recipe text** stages and attempts extraction but writes nothing canonical and surfaces the extractor's
   existing empty/failed result — no silent `Recipe` (D4/Amd2-D6).

Do **not** unit-test the Shortcuts app itself.

---

## Guardrails a dispatch must not undo

- **Do not reuse `ImportHandoffResult` or `HandoffReviewCoordinator`.** New recipe, no `handoffID` → Create Recipe,
  its own sibling intent + coordinator (Amd2-D2). This is the whole risk.
- **Do not add a parser or a second "text → recipe" model call in the intent.** Reuse
  `CreateRecipeExtraction.extract` (ADR-0051 D7).
- **Do not add a `yeschef://` URL scheme.** Foreground via `openAppWhenRun` + coordinator (Amd2-D3).
- **Do not add a durable or synced pending-import table.** The session is D4-transient; staging is in-memory only.
- **Do not clobber an in-progress session.** `pastedTextReceived` overwrites `composeText`; the non-empty path must
  append/offer, never replace (Amd2-D4). Never auto-extract over existing unsaved work.
- **Do not normalize or strip the staged text**, and **do not** make the intent menu/day-aware (Amd2-D5).
- **No canonical write without the cook's Save.** Staging + extraction are pre-Save; nothing hits the library on
  the intent's own authority (D4).

---

## Documentation — "Faster return path with Shortcuts"

Add to the ChatGPT operator/setup doc a short section (link the canonical App Intents doc if one exists rather than
duplicating internals):

- Create a Shortcut named **Send to Yes Chef**: `Get Clipboard` → **Capture a recipe from text** (Yes Chef) →
  (if a foreground step is needed on the device's iOS) `Open App` / the intent's `openAppWhenRun` handles it.
- Expected flow: copy the ChatGPT recipe response → run the Shortcut → Yes Chef opens on Create Recipe with the
  text extracted → review and Save.
- **Fallback unchanged:** ordinary copy → open Yes Chef → Create Recipe → paste still works; the Shortcut is a
  convenience, not a dependency.
- Note the invocation surfaces that fall out for free from App Intent support (Shortcuts app, Home Screen,
  Action Button, Control Center) — but build **no** bespoke UI for those in this slice.

---

## Verification

- `swift build` the package; the **generic app build is required evidence** (Verification Pattern);
  `scripts/check-drift.sh`; SwiftLint clean.
- **`YesChefTests`** carries correctness — the six tests above; the non-clobber and exact-text ones are the point
  ([[app-test-target-in-verification]]).
- **No new table** — nothing owed to the promotion list (D4-transient session).
- **Device pass (Jon):** build a `Send to Yes Chef` Shortcut; copy a real ChatGPT recipe response; run it from the
  Shortcuts app **and** the Action Button; confirm Yes Chef foregrounds on Create Recipe with the recipe extracted,
  from both **cold launch and already-running**. Confirm: empty clipboard fails cleanly; non-recipe text opens the
  session without a canonical write; a Shortcut fired **while a different Create Recipe draft is in progress** does
  not wipe that draft (resolves OQ6). Confirm exact-text is preserved (a fenced/marked response still Saves a clean
  recipe).
