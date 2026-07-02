# Effort: Actionable chat — the lift + make-ahead (ADR-0011)

**Type:** New architecture (cross-app). First real instance of the actionable-chat pattern.
**Owner:** Codex (implement, per slice) · Claude (architect/review) · Jon (product/review)
**Status:** Approved + **dispatched** 2026-07-02. Decision: [ADR-0011](../decisions/ADR-0011-actionable-chat-make-ahead.md).
Driving force: jon-platform `docs/ios/actionable-chat.md`; boundary law: `docs/ios/ai-model-access.md`;
Galavant home: galavant `docs/decisions/0031-actionable-chat.md`.

**Do the slices in order.** Slice 1 is a prerequisite for Slice 2. Slices 1a/1b/1c are separate
commits/PRs across three repos. If you run the galavant change in parallel, use a **git worktree**
(jon-platform note: `parallel-agent-worktree-isolation`) so it doesn't collide with yes-chef work.

**Read before starting:** ADR-0011 (whole), galavant ADR-0031 (whole), `ai-model-access.md`,
`actionable-chat.md`, and the reference sources under
`~/code/galavant/galavant/GalavantLibrary/Sources/GalavantAI/` +
`.../GalavantChat/` + `.../GalavantPlaces/PlaceDiscoveryClient.swift`. **Mirror, don't blind-copy.**

**Test/build reality (house constraint):** FoundationModels-linked test bundles can't run under
`swift test` here — use `swift build` for the package; build the app with `-skipMacroValidation`.
Anything Apple-Intelligence-gated (the on-device tier) verifies **on device**, not the simulator.
Run `xcodegen generate` after adding Swift files; then the Verification Pattern in `CURRENT_HANDOFF.md`.

---

## SLICE 1 — The prerequisite lift: `GalavantAI` → shared `LLMClientKit`

Repeats the `WebExtractorKit` playbook (jon-platform ADR-0002; yes-chef ADR-0007/0009; galavant
ADR-0027). A **move, not a copy**: source leaves galavant, both apps depend by local path. The
module is domain-free already (imports only Dependencies / Foundation / FoundationModels / Security /
Synchronization), so symbols move **unchanged** — only the module name changes (`GalavantAI` →
`LLMClientKit`) and consumers update their `import`.

### Slice 1a — create the package (jon-platform repo)

- New SPM package `~/code/jon-platform/packages/LLMClientKit/` with its own `Package.swift`, mirroring
  `packages/WebExtractorKit/`'s manifest shape (platforms, Dependencies dep, a library product
  `LLMClientKit`, and a test target).
- **Move** every file from `~/code/galavant/galavant/GalavantLibrary/Sources/GalavantAI/` into
  `Sources/LLMClientKit/`: `ModelClient.swift`, `TieredModelClient.swift`, `AnthropicModelClient.swift`,
  `AnthropicWire.swift`, `OpenAIModelClient.swift`, `OpenAIWire.swift`, `OnDeviceModelClient.swift`,
  `APIKeyStore.swift`, `ModelTool.swift`, `JSONValue.swift`. **Symbols unchanged** (`ModelClient`,
  `TieredModelClient`, `FrontierProvider`, `APIKeyStore`, …). Fix any `GalavantAI`-scoped doc
  comments/ADR refs to be app-neutral (they cite galavant ADR-0014/0017/0018 — reword to reference
  `ai-model-access.md` / `actionable-chat.md`, keeping the intent).
- Move the matching tests from `GalavantLibrary/Tests/GalavantAITests/` (if present) into the package's
  test target. `swift build` the package clean.
- Add the lift row to `~/code/jon-platform/EXTRACTION-NOTES.md` under "Shared code lifts", modeled on the
  `WebExtractorKit` row: source = `GalavantAI` module (galavant ADR-0014); → `packages/LLMClientKit/`;
  note "Moved not copied (2026-07-02); domain-free tiered ModelClient boundary; renamed module
  `GalavantAI` → `LLMClientKit`, symbols unchanged; triggered by yes-chef as second consumer
  (actionable chat, ADR-0011)."

### Slice 1b — galavant adopts by path + delete (galavant repo, PR)

- Delete the `GalavantAI` target from `GalavantLibrary/Package.swift`; add a **local path dependency**
  on `../../jon-platform/packages/LLMClientKit` (match how `WebExtractorKit` is referenced) and re-point
  the targets that used `GalavantAI` (`GalavantChat`, `GalavantPlaces`, any others — grep
  `import GalavantAI`) to `import LLMClientKit` + the package product in their target deps.
- Delete `Sources/GalavantAI/`. `swift build` GalavantLibrary clean; app builds.
- PR title e.g. "Lift GalavantAI → shared LLMClientKit (path dep)". This is galavant's ADR-0031 Slice 1.

### Slice 1c — yes-chef migrates onto the package (yes-chef repo, PR)

This is a **migration**, not clean adoption — yes-chef has a divergent minimal AI stack. Nothing
consumes `modelClient` yet (only the app wires it), so the swap is low-risk.

- Add local path dependency on `LLMClientKit` to `YesChefPackage/Package.swift`; add the product to the
  `YesChefCore` target deps.
- **Delete** `YesChefPackage/Sources/YesChefCore/ModelClient.swift` and `.../ClaudeAPIClient.swift`
  (superseded by the package's `ModelClient` protocol + `AnthropicModelClient`/`AnthropicWire`).
- **Migrate the app-side key/settings** to the package:
  - `YesChefApp/ClaudeAPIKeyStorage.swift` → replace usage with the package's `APIKeyStore`
    (multi-provider, Keychain-per-provider). Delete the bespoke storage if fully subsumed; keep only if
    it holds something `APIKeyStore` doesn't (unlikely — confirm by reading both).
  - `YesChefApp/AISettingsView.swift` → re-point at `APIKeyStore`; single-Anthropic entry is fine for
    now, but use the multi-provider store so a later provider is a UI addition, not a rewrite.
  - App wiring in `YesChefApp/YesChefApp.swift` (~line 21, currently `$0.modelClient = ClaudeAPIClient(...)`)
    → the live tiered client from the package (`TieredModelClient.live`, which reads `APIKeyStore` and
    assembles on-device + frontier). yes-chef gains the **on-device floor + streaming + tool loop** it
    lacked.
- `xcodegen generate`; app builds with `-skipMacroValidation`; the Verification Pattern.
- PR title e.g. "Adopt shared LLMClientKit; retire minimal ModelClient/ClaudeAPIClient".

**Slice 1 acceptance:** one AI boundary in yes-chef (the package's `ModelClient`); no `GalavantAI`
module anywhere; both apps + the package build; EXTRACTION-NOTES row present; `AISettingsView` still
saves/loads an Anthropic key (verify a completion still round-trips on device).

---

## SLICE 2 — The abstraction + make-ahead (yes-chef repo)

Build the **general apply-action catalog** (galavant ADR-0031 §Consequences), verb-and-context-general,
and land **make-ahead as verb #1**. Do **not** hardcode make-ahead into the surface — a later verb
(Chef It Up; menu side-dishes) must slot in without reworking the panel. **Invariant: the model
proposes and structures; the user's tap is the only write.**

### 2a — schema: the commit target

- Add `public var makeAhead: String?` to `Recipe` (`YesChefPackage/Sources/YesChefCore/Models.swift:5`,
  and its `init`). Add the column via an **additive migration** in
  `YesChefPackage/Sources/YesChefCore/Schema.swift` (nullable TEXT on `recipes`). Additive nullable
  columns are **sync-safe** — no schema-version dance, no reserved name, no new unique index (ADR-0010,
  [[sqlitedata-blob-cloudkit-asset]]). Confirm import/editor/round-trip paths tolerate the new optional.

### 2b — the extract client (domain-side, model stays domain-free)

- `MakeAheadPlan` value type in `YesChefCore` (make-impossible-states-unrepresentable): e.g.
  `struct MakeAheadPlan { var steps: [MakeAheadStep] }`, `struct MakeAheadStep { var when: String;
  var task: String; var why: String? }` + a `rendered() -> String` that flattens to the text stored in
  `Recipe.makeAhead` (a later slice can graduate to a structured section without touching extraction).
- `MakeAheadPlanClient` — **mirror `PlaceDiscoveryClient`** (grounded/structured `complete()` → decode).
  A single focused `ModelClient.complete` over *the conversation-so-far + the serialized recipe*, `system`
  instructed to return **only** strict JSON for `MakeAheadPlan`; parse **defensively** (drop a bad
  element, not the whole plan). **No `Recipe` crosses the model layer** — pass a serialized string in,
  decode `MakeAheadPlan` out. Default tier: `.frontier(.anthropic)` for reliable structured output
  (make-ahead needs **no web search**); it degrades to on-device when no key (structured decode may be
  weaker — acceptable). Injectable `@Dependency`; `testValue` returns a fixed plan / `[]` so the parser
  is the tested default with no network.

### 2c — the commit op (pure, tested)

- `applyMakeAheadPlan(_ plan: MakeAheadPlan, to recipeID: Recipe.ID)` in `YesChefCore` — a pure domain op
  that writes `plan.rendered()` into `Recipe.makeAhead`, **replace-on-commit** (one canonical result per
  recipe), touching `dateModified`. **Undo = clear the field.** In-memory-DB tests (the abstraction's real
  guarantee; `swift build` since the FM-linked bundle can't run here).

### 2d — the catalog + chat surface

- A generic, testable apply-action type in `YesChefCore`, e.g.
  `struct ChatApplyAction<T> { var title: String; var extract: ([ChatMessage]) async throws -> T;
  var commit: (T) async throws -> Void }` (or an enum-of-verbs if that models better — your call, keep it
  general). A screen supplies a **catalog** `[ChatApplyAction]`; the panel renders each as a button and
  runs `extract → commit` on tap. Make-ahead is the first entry:
  title "Summarize make-ahead → Make-ahead section", `extract = MakeAheadPlanClient` over the
  conversation, `commit = applyMakeAheadPlan`.
- **`RecipeChatContext`** (mirror galavant `ChatContext`) — built by the presenting screen from
  already-fetched read-model values (title, servings/yield, times, ingredient sections + lines,
  instruction sections + steps, existing notes); `serialized()` into the system prompt. Pure/testable.
  **Design `ChatContext` so it is not recipe-only** (a `.recipe(...)` case now; a `.menu(...)` case is a
  later verb's job) — the menu side-dish example must be addable without reshaping this.
- **`RecipeChatModel`** (`@MainActor @Observable`, mirror galavant `ChatModel`) — ephemeral messages
  (never persisted, never CloudKit-synced), per-conversation tier choice (on-device default; frontier
  opt-in when a key exists, surfaced as "leaves the device"), streaming on-device / tool loop on frontier.
  In `YesChefCore` so dispatch + serialization are stub-testable (the app target stays untestable).
- **Parity built in (ADR-0031 §6 — table stakes):** render assistant text as **inline markdown**
  (`LocalizedStringKey`, so `**bold**` and `[label](url)` render, not raw `**`/`###`); an **editable
  pre-prompt** in Settings spliced into `systemPrompt()` (mirror galavant's `ChatInstructions`
  dependency). Web search stays unwired (not needed for make-ahead).

### 2e — UI

- A chat panel in `YesChefApp/RecipeDetailView.swift` (a sheet/inspector). The catalog's buttons render
  under the conversation; tapping "Summarize make-ahead" runs extract, shows the decoded plan briefly,
  commits on the tap.
- Render `recipe.makeAhead` as **its own "Make-ahead" section** in the detail view (satisfying
  FUTURE_INTELLIGENCE §7.2 "its own make-ahead section rather than a generic note"). A clear affordance
  removes it (the field-clear undo).
- `swiftui-specialist`/`swiftui-pro` checkpoint on the panel + section; Verification Pattern; Jon does
  the primary UI pass on device (on-device tier + the frontier round-trip both need a real device).

**Slice 2 acceptance:** on a recipe, open chat (seeded — no re-describing the recipe), converse, tap
"Summarize make-ahead → Make-ahead section", and a distilled plan lands in `recipe.makeAhead`, rendered
as its own section, syncing like any field; clearing it is the undo. No chat turn ever writes on its own.
The catalog/context are general enough that Chef It Up (a second field) and menu side-dishes (cards, menu
context) are additive, not rewrites.

---

## Out of scope (named, deferred — keep the design honest, don't build)

- **Chef It Up** verb (`Recipe.chefItUp` section) — second post-hoc-distill verb; after make-ahead proves.
- **Menu side-dishes** — inline-structured cards in a menu context; the other motion, validates
  context-generality; later.
- **Galavant adoption** (ADR-0031 Slice 3) + **jon-platform cross-app ADR** (Slice 4) — after the shape
  holds here. Galavant's **Slice 0 parity** is independent and may proceed in galavant in parallel.
- OpenAI frontier / web-search wiring for chat — unwired for both apps (`ai-model-access.md`).
