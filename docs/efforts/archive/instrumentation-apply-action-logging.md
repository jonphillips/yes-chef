# Effort: Instrumentation — logging for the apply-action + LLM pipeline

**Type:** Diagnostic instrumentation ("for now" logging), no behavior change, no schema, no new deps.
**One Codex dispatch, one PR.** **Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
Sourced from Jon's menu-planner dogfood pass 2026-07-09 ("I feel like we need some logging for now") and the
2026-07-10 follow-up confirming it was the one un-built item from that list. Serves the parked **two-device
core-loop dogfood** — the next pass shouldn't be guessing why a verb misbehaved.

**Goal.** When a chat/menu verb misbehaves — specifically when it shows *"The assistant did not return anything
to review"* — the log must reveal **what the model actually returned and why `extract` produced nothing**
(non-JSON prose vs. `{"steps":[]}` vs. a truncated/empty completion — the last ties to the
[[reasoning-budget-starves-output]] failure mode). No behavior change, no schema.

**Read first:** `YesChefApp/YesChefApp.swift` (composition root, `$0.modelClient = TieredModelClient.live(...)`
~line 24), `YesChefApp/RecipeChatWorkspace.swift` (`run(_:)` ~391, empty-result at ~401,
`commit(_:approvedText:)` ~412, subject resolution `latestReplySubject` ~472 / `selectionSubject`),
`YesChefPackage/Sources/YesChefCore/MenuPrepPlan.swift` (`client` ~119: `modelClient.complete(request)` →
`parse(response.text)` ~129), and one sibling verb client (`MenuComplement.swift`, `RecipeEnrichment.swift`) to
confirm the shared `@Dependency(\.modelClient).complete(request)` → `parse(response.text)` shape.

**Scope boundaries:** App + Core only. **Do NOT modify `LLMClientKit`** (shared jon-platform package at
`../../../jon-platform/packages/LLMClientKit`). No in-app log viewer (parked). No changes to any verb client's
logic. `AppLog` + `LoggingModelClient` are the only new files.

**Build/verify (lean — the build/sim loop is the cost, not the code):** `swift build` the package +
`scripts/check-drift.sh`; `xcodegen generate` (new files added); build `YesChef` **once** for
`iPad Pro 13-inch (M5) (16GB)` with `-skipMacroValidation`. **No simulator install** — Jon device-passes by
reading Console. One build attempt; if the sim service is unavailable, paste the error and stop.

---

## Design (decided — don't re-litigate)

### 1. Substrate — `os.Logger`

Add a small `AppLog` namespace in `YesChefCore` with an OSLog subsystem (the app bundle id) and categories
`applyAction` and `llm`. Because this is a **single-user personal app, not a server**
([[personal-app-latency-tolerance]]), log payloads with `privacy: .public` so prompts/responses are actually
readable in Console/Xcode — that legibility is the whole point. Use `print` nowhere.

### 2. Point A — the LLM I/O seam (covers every verb at once)

Every verb resolves `@Dependency(\.modelClient) var modelClient` and calls `modelClient.complete(request)` →
`parse(response.text)`, so one decorator on that dependency instruments them all. Create a `LoggingModelClient`
decorator in `YesChefCore` wrapping a `ModelClient`; on `complete(_:)`:

- log a request summary (verb/tier/provider if available + the outgoing prompt text),
- call the wrapped client,
- log the **raw `response.text`**, latency, and — **if the LLMClientKit response exposes a stop/finish reason
  or usage/truncation flag** — that too (key signal for a truncated/empty completion; if the type doesn't
  expose it, add a `// TODO:` note, do **not** edit LLMClientKit),
- on throw, log the error (including `ModelClientError.onDeviceUnavailable` / `onDeviceContextTooLarge`) and
  rethrow unchanged.

Wire it once at the composition root: `$0.modelClient = LoggingModelClient(wrapping: TieredModelClient.live(...))`.
This is the **only** override site — every verb flows through it.

### 3. Point B — the apply-action lifecycle (app layer)

In `RecipeChatWorkspace.run(_:)` and `commit(...)`, log: verb id/title; **subject source** (explicit selection
vs. `latestReplySubject` fallback vs. subject chip); `extract` outcome (**item count**, or **empty** + which
`emptyResultMessage` fired); commit success/error. Together with Point A this makes the prep-plan case legible:
the raw model output *and* the `0 steps` extract result are both visible.

---

## Acceptance

- Triggering any chat/menu verb produces a legible Console trace: verb invoked (id + subject source) → outgoing
  prompt → raw model response (+ latency/tier, + stop reason if available) → extract result (N items, or empty +
  reason) → commit outcome.
- Reproducing **Build Prep Plan on a menu with no Make-Ahead detail** yields a trace where the model's actual
  output and the `0 steps` extract result are both visible — the "why nothing came back" is answerable from the
  log alone.
- Zero behavior change to any verb; `LLMClientKit` untouched; no schema.

## Explicitly out (parked)

- **In-app log viewer** — Console/Xcode is enough "for now"; a surfaced-in-app log is a later call.
- **Persisted / exportable logs** — unified logging's ring buffer suffices for a device pass.
- **Sync/enrichment/capture instrumentation** — this pass is the chat/menu apply-action + LLM seam; the same
  `AppLog` substrate can be extended to those later without rework.
