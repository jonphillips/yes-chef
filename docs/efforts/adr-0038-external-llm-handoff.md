# Effort: ADR-0038 — External-LLM handoff (session-tracked, App-Intents-routed)

**Type:** A reusable "hand this off to a native LLM app, discuss, bring the artifact back" loop. Generalizes
the menu-only Copy-Prep-Prompt / Paste-Prep-Plan round-trip into a **transport-agnostic core** (a
device-local session record + a serializer + the existing plain-text parser/review machinery) exposed
primarily through **App Intents / Shortcuts**. The core reuses everything; the new surface is the session
record + two intents + three entities.
**Owner:** Codex (implement, per slice) · Claude (architect/review) · Jon (product/review)
**Status:** **Ready to dispatch (S1 first).** Implements [ADR-0038](../decisions/ADR-0038-external-llm-handoff.md)
(Proposed 2026-07-13). Every risk was retired pre-code on 2026-07-13: `Ask ChatGPT` returns text as a value
(OQ3), and a live beach-menu round-trip came back in the exact review-text format the parser accepts (D2).
Extends [ADR-0034](../decisions/ADR-0034-prep-plan-work-session-timeline.md) (the menu escape hatch this
generalizes) and rides [ADR-0011](../decisions/ADR-0011-actionable-chat-make-ahead.md)/[ADR-0024](../decisions/ADR-0024-editable-proposal-preview.md)/[ADR-0026](../decisions/ADR-0026-review-collection-sheet.md)
(apply-action, editable-preview human-as-author, review-collection sheet) **unchanged**.

**Read before starting:** [ADR-0038](../decisions/ADR-0038-external-llm-handoff.md) in full (D1 core, D2
plain-text-not-JSON, D4 App Intents, D5 the two-modes→two-actions map, D6 route-by-ID-preview-always, D7
reuse variation/replace commits; OQ1 device-local, OQ6 per-menu project). Then the shapes to reuse:
- `YesChefCore/MenuChatContext.swift` — the outbound serializer to mirror: `prepPrompt()` (~:57), the static
  `prepPrompt(context:tasteProfile:makeAheadPreference:)` (~:179), and `serialized(for:)` budgeting (~:83).
- `YesChefCore/MenuPrepPlan.swift` — the plain-text round-trip that **already parses ChatGPT's output**:
  `editableReviewText()` (~:61) / `applyingEditableReviewText(_:)` (~:74); the header/line helpers
  (`isEditablePrepPlanSessionHeader` ~:347 accepts any colon-terminated line, `editableReviewLine` ~:132
  splits on `→`). **One hardening (D2):** pin the exact `→` glyph in the outbound prompt, or extend
  `editableReviewLine` to also accept `->`.
- `YesChefApp/MenuViews.swift:400`–`462` — the existing manual transport (`copyPrepPrompt` / `pastePrepPlan`),
  the S1 stand-in for the intent pair. Leave the buttons working.
- `YesChefCore/RecipeChat.swift` — the commit contract (`AnyChatApplyAction` ~:670, `ChatApplyReviewItem`
  ~:594); `YesChefApp/RecipeCollectionReviewSheet.swift` + `RecipeChatWorkspace.swift` — the review surface
  the intent import opens (D6).
- `YesChefCore/Models.swift` (`Menu` ~:368) + `Schema.swift` — where the `AIHandoff` table + migration and the
  `Menu.externalProjectName` column land.

**Build/verify ([[lean-verification-default]]):** `xcodegen generate` after adding files/target membership;
package logic via `swift build`; app via `scripts/xcodebuild-summary.sh -skipMacroValidation`, once; then
`scripts/check-drift.sh`. **No simulator install** — Jon does the device pass. **App Intents / Siri /
Action Button need a real device**, and the device pass also settles OQ6's `Start chat in project`
variable-vs-fixed question.

---

## The invariant this preserves

**Yes Chef owns the context at the start and the durable artifact at the end; the native app hosts the
conversation; the human is the final author of anything committed** (ADR-0024/0026). No auto-write on the
discuss path — the imported artifact always lands in the review sheet (D6). The immediate path may commit
directly but still surfaces the result. External content is data, never instructions.

## Sync posture (ADR-0002)

- **`AIHandoff` — device-local, never syncs (OQ1).** Keep it out of the CloudKit SyncEngine record set;
  confirm the per-table opt-out, else use a lightweight device-local store. It only *references* synced
  UUIDs (`sourceID`), so a cross-device return still routes.
- **`Menu.externalProjectName` — additive, syncs** (a menu attribute; travels with the menu). Adds one
  held additive column to the standing prod-schema-promotion list (`CURRENT_HANDOFF.md`).

## Slice plan

### S1 — the handoff **core**, proven through the existing menu paste path (first dispatch)

The menu round-trip already works; S1 adds the *session* around it, no new UI surface.
- **`AIHandoff` record (new, device-local):** `id: UUID`, `sourceType` (`.recipe`/`.menu`/`.mealPlan`),
  `sourceID: UUID`, `taskType`, `createdAt`, `importedAt: Date?`, `status`
  (`.awaitingReturn`/`.imported`/`discarded`), `schemaVersion: Int`, `exportedPrompt: String`. New `@Table` +
  migration, **excluded from sync** (Sync posture above).
- **Token emit (D2/D6):** `copyPrepPrompt` prepends a `YC-HANDOFF: <uuid>` header line and creates the
  `AIHandoff` (`.menu`, the viewed menu's id, `.prepPlan`, `exportedPrompt` = the copied text).
- **Token strip + route (D6):** `pastePrepPlan` reads the token, looks up the handoff, strips the header,
  parses via the existing `applyingEditableReviewText`, marks `importedAt`/`.imported` (dedupe on
  `importedAt`). Missing/absent token → today's behavior unchanged (self-describing fallback).
- **Harden the `→` glyph** per D2.
- **Prove it:** Copy Prep Prompt (record created, token in clipboard) → `Ask ChatGPT` shortcut → Paste Prep
  Plan (token matched, plan parses into bands, handoff flips to `.imported`, re-paste no-ops).

### S2 — the App Intents surface + review-sheet import + per-menu project (follows S1)

- **`AppEntity` for Recipe / Menu / MealPlan**, marked **`SyncableEntity`** (stable iCloud UUIDs). New
  `AppIntents/` group in the app target (in-process; calls `RecipeRepository`/`MenuRepository`).
- **`ExportHandoffContext(source:)`** — `source` as `@UnionValue` of the three entities; creates the
  `AIHandoff`, returns the prompt string **and** `Menu.externalProjectName` (for `Start chat in project`).
  OQ5: resolve a no-`source` invocation (Action Button) via an `EntityQuery` "current" or a picker — decide
  here.
- **`ImportHandoffResult(handoffID:, result:)`** — routes by id (param or stripped token), parses, and
  **`OpensIntent`** into `RecipeCollectionReviewSheet` (D6 — discuss path always previews).
- **`Menu.externalProjectName: String?`** — additive column; a menu-detail field to set it. Verify on-device
  whether `Start chat in project` takes the project as a variable (OQ6); flag the finding in the PR.
- **Prove it:** a Shortcut `ExportHandoffContext(menu) → Ask ChatGPT → ImportHandoffResult` (immediate) and
  `ExportHandoffContext(menu) → Start chat in project → …return… → ImportHandoffResult` (discuss → sheet).

### S3 — generalize the serializer to Recipe + MealPlan (follows S2)

- Recipe + MealPlan context builders on the `MenuChatContext` pattern (frontier budget, method, uncapped
  ingredients, an intro prompt tuned from `tasteProfile`/AI settings, asking for review-text output).
- Commit shapes per source: recipe → `Recipe.makeAhead` (and adjust/variation, ADR-0021/0023); meal-plan →
  make-ahead-strategy ([ADR-0013](../decisions/ADR-0013-meal-planner-actionable-chat.md), classify commit
  shape first per [[chat-verb-commit-shapes]]).

**Batching ([[batch-slices-and-lean-handoff]]):** S1 first (it de-risks the record + sync-exclusion + token
before greenfield App Intents). S2 follows with S1's learnings; S3 last. S1+S2 may bundle if S1's
sync-exclusion lands cleanly.

## Out of scope

- **Widened share-extension "Import into Yes Chef"** (ADR-0038 Deferred) — App Intents cover the ground; the
  extension stays lean ([[extension-sync-construct-not-run]]).
- **`SnippetIntent` inline review** in Shortcuts/Siri, **`LongRunningIntent`**, **`IndexedEntityQuery`** —
  future enhancements, not v1.
- **Creating ChatGPT projects from Yes Chef** — impossible via Shortcuts; the user creates the project, Yes
  Chef selects into it (OQ6).
- **Provider = Claude** alongside ChatGPT — separate `open-questions.md` item; the handoff is agnostic to
  which native app hosts the chat.
