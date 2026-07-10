# Effort: ADR-0027 "Capture to menu" — a harvest verb (extraction, not generation)

**Type:** A new menu chat verb. Takes content **already in the chat** — a user's text selection in an
assistant bubble, or, absent one, the transcript — and captures it as **one or more `MenuItem` notes** on
the menu. The model **segments and reshapes** (rambling chat prose → a clean recipe-looking note); it
**never invents**. No schema — additive in-memory payload + a note write through the existing repository.
**Owner:** Codex (implement, per slice) · Claude (architect/review) · Jon (product/review)
**Status:** **Ready to dispatch.** Implements [ADR-0027](../decisions/ADR-0027-harvest-chat-into-notes.md)
(Accepted 2026-07-10). Its one prerequisite — the [ADR-0026](../decisions/ADR-0026-review-collection-sheet.md)
collection sheet — is **already merged** ([#138](https://github.com/jonphillips/yes-chef/pull/138),
`RecipeCollectionReviewSheet`), so this is unblocked. Extends
[ADR-0012](../decisions/ADR-0012-menu-actionable-chat.md) (the `MenuItem`-note commit target, Amendment 2)
and the [ADR-0011](../decisions/ADR-0011-actionable-chat-make-ahead.md) apply-action contract.

**Read before starting:** [ADR-0027](../decisions/ADR-0027-harvest-chat-into-notes.md) in full (the
vocabulary banner + D1–D6 are load-bearing; D2 selection-scoping and OQ2 "LLM always runs" are the two
easy-to-get-wrong calls). Then, for the shape to copy:
- `YesChefCore/MenuComplement.swift` — the **payload + client pattern to mirror**: `MenuComplementPlan` /
  `MenuComplementSuggestion` (Equatable/Sendable structs), `editableReviewText()` / `rendered()` /
  `applyingEditableReviewText(_:)` for the ADR-0024 round-trip, and `MenuComplementClient` (the
  `@Dependency`-injected LLM client with a static `parse(_:)` + `liveValue`).
- `YesChefApp/MenuModels.swift` — where the verb is wired: `applyActionCatalog(for:)` (~:457) builds the
  `ChatApplyAction`s (complement ~:462, prep-plan ~:480) and maps each into `ChatApplyReviewItem`s in the
  returned `[AnyChatApplyAction]` (~:500). `commitComplementSuggestion` (~:548) → `MenuRepository`. This is
  the file the new verb is added to.
- `YesChefCore/RecipeChat.swift` — the contract: `ChatApplyAction<Payload>` with
  `extract: (selection: String, context: [RecipeChatMessage]) -> Payload` (~:562) — **`selection` is the
  raw selected text, empty string when none**; `ChatApplyReviewItem` (~:594) with its per-item
  `commit(approvedText:)`.
- `YesChefApp/RecipeChatWorkspace.swift` — the selection plumbing that **already exists** and needs **no
  change**: `ChatAssistantSelection` (~:799), `actionSubject(for:)` (~:485) already prioritizes a
  `.selection` subject and feeds its text into `extract`'s `selection` param.

**Build/verify (house constraint, [[lean-verification-default]]):** `xcodegen generate` after adding files;
package logic via `swift build`; app via `scripts/xcodebuild-summary.sh` with `-skipMacroValidation`, built
once; then `scripts/check-drift.sh`. **No simulator install** — Jon does the device pass (primary on
`iPad Pro 13-inch (M5)`, both orientations; `iPhone 17 Pro` for the compact sheet).

---

## The invariant this preserves

**The model proposes; the human triages the whole set; a tap writes** (ADR-0011/0012). Harvest adds no new
write path of its own beyond one note-commit; nothing is auto-committed. The new twist vs. complement is
only the verb's *relationship to the content* — **preserve, don't invent** — enforced at the output-shape
level (a JSON array of `{title, body}`, one per distinct thing already present), per
[[llm-curation-not-synthesis]].

## Sync posture (ADR-0002)

**None.** New in-memory payload; commit writes **existing** `MenuItem` note rows. No new table, no column,
no enum case. Captured notes are always `.note` kind with **no `recipeID`** ([[menu-item-recipe-id-invariant]]
sidestepped for free — the invariant only bites recipe-kind rows). Sync-safe by construction.

## Slice plan

### S1 — the "Capture to menu" verb (prove the selection path first)

**Payload (new, in `YesChefCore`, mirror `MenuComplement.swift`):**
- `MenuNoteHarvestPlan { notes: [HarvestedNote] }` and `HarvestedNote { title: String, body: String }`,
  both `Equatable`/`Sendable`, with `editableReviewText()` / `applyingEditableReviewText(_:)` for the
  ADR-0024 editable round-trip (title line + body, same idiom as `MenuComplementSuggestion`).

**Client (new, `MenuNoteHarvestClient`, `@Dependency`-injected like `menuComplementClient`):**
- `extract(selection:messages:tier:)` — **note the deliberate absence of a `context:` argument.** Per D2
  the menu context is **not** sent; the menu is the write target, not source material. This is the direct
  fix for Jon's "it sent the whole menu" surprise — do not copy complement's `context:` parameter over.
- **Source selection (D2):** if `selection` is non-empty → the source is the **selection alone**; if empty →
  the source is the **transcript** (`messages`, assistant turns). Two prompt modes, one client.
- **The prompt is extraction, not generation (D1, OQ2).** Instruct the model to: (a) find the **distinct**
  dish(es)/note(s) present in the source — **one or several**; (b) reshape each from rambling chat prose
  into a **clean, recipe-looking note** (a short title + a tidy body of the specifics already stated);
  (c) **never invent** ingredients, dishes, or detail not in the source; (d) return a **JSON array of
  `{title, body}`**, one per distinct note; **empty array is valid** (precision over recall on the
  transcript-scan path). Add a static `parse(_:)` + fixture tests mirroring `MenuComplementTests`.
- **LLM always runs** (OQ2) — no no-LLM fast path even for an exact selection; the segment + reshape is the
  point.

**Wiring (`MenuModels.applyActionCatalog`):**
- Add a `ChatApplyAction<MenuNoteHarvestPlan>` titled **"Capture to menu"** (`extractingTitle:` e.g.
  "Capturing…", `commitTitle:` "Add to Menu"). Its `extract` calls the new client with `selection` +
  `messages` (no context).
- In the returned `[AnyChatApplyAction]`, map `plan.notes` → **one `ChatApplyReviewItem` per note** (mirror
  the complement mapping at ~:501): `editableTitle: "Note"`, `editableText: note.editableReviewText()`,
  per-item `commit` writing the note.
- **Commit target (D3):** each accepted note → its own `MenuItem` note via a new
  `commitCapturedNote(_:)` → `MenuRepository` (parallel to `commitComplementSuggestion` /
  `addComplementItem`). Kind `.note`, **no `recipeID`**. **Placement (OQ1):** drop into the
  **currently-viewed day / an unslotted parking spot** — do **not** ask the model for placement. Confirm
  what "currently-viewed day" is reachable from in the menu model; if there is no clean unslotted home, a
  default day/slot the user then moves is acceptable — flag the choice in the PR.

**Prove it (the exact dogfood repro):** highlight a dish paragraph in an assistant bubble → "Capture to
menu" → **one** clean note in the collection sheet → commit → it lands as a `MenuItem` note. Then the
no-selection path: no highlight → the verb scans the transcript → N candidate notes in the sheet.
Regression-check that complement and prep-plan are untouched.

### S2 (deferred — do not build without Jon) — the recipe sibling

Same verb, `RecipeNote` commit target on a recipe (capture a chat tip into a recipe note). Named follow-on
(ADR-0027 D6); build only if Jon asks and only if S1's shape ports cleanly.

## Out of scope

- **Promotion to a real recipe** ("Create a recipe from this note") — a separate downstream step (ADR-0027
  D5), touches ADR-0021/0023 and [[reference-placement-and-original-provenance]]. Harvest makes the *note*;
  it does **not** create recipes.
- **Sending the menu as source context** — explicitly forbidden (D2). A menu dedup *hint* is a possible
  later addition, not S1.
- **A taste preference** (ADR-0018 `AIPromptPreferenceKind`) — deferred (OQ4); the guardrail stays code.
- **Cross-bubble selection** — parked (OQ3); the transcript-scan path covers multi-bubble capture anyway.
