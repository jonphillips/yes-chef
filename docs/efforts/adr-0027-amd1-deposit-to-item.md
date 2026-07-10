# Effort: ADR-0027 Amendment 1 — Deposit chat intelligence onto the item you point at

**Type:** A new menu chat verb (target-adaptive). Takes intelligence **already in the chat** (a Compare
verdict, a "here's how I'd change this" riff — the current selection, or absent one the latest reply) and
writes it onto **the existing menu item you point at**, in the mode that item's canonical-ness demands:
- **recipe target → append.** Write it as a `RecipeNote` on that recipe. Never rewrite the recipe.
- **note target → revise.** LLM weaves the intelligence into the note; a **compose surface** (original
  copyable + woven editable draft) lets Jon assemble the final text, which overwrites the note.

No queue, no auto-Workbench, no graduation — those were considered and cut (Amd-1 A4). **Schema-free:** the
recipe path upserts an existing `RecipeNote`; the note path updates the existing `menuItems.notes` column.
**Owner:** implementer (per slice) · Claude (architect/review) · Jon (product/review)
**Status:** **Ready to dispatch.** Target-designation gesture confirmed by Jon 2026-07-10: **tap-to-target**
(§ The new plumbing). Everything is decided. Implements
[ADR-0027 Amendment 1](../decisions/ADR-0027-harvest-chat-into-notes.md#amendment-1--deposit-chat-intelligence-onto-the-item-you-point-at-recipe-append--note-revise)
(Accepted 2026-07-10). Extends base ADR-0027 (same harvest nature) and the
[ADR-0011](../decisions/ADR-0011-actionable-chat-make-ahead.md) apply-action contract; the note-revise
compose surface borrows [ADR-0024](../decisions/ADR-0024-editable-proposal-preview.md) editability +
[ADR-0023](../decisions/ADR-0023-recipe-edit-proposals.md)'s side-by-side spirit.

**Read before starting:** the [ADR-0027 Amendment 1](../decisions/ADR-0027-harvest-chat-into-notes.md)
decisions in full (A1 target-adaptive, A2 recipe-append, A3 note compose-surface, **A4 the recorded
reversal — do not resurrect the queue**, A5 target binding, A6 promotion is out of scope). Then, the shape to
copy / touch:
- `YesChefApp/MenuModels.swift` — `applyActionCatalog(for:)` (:457) is where the verb is added, alongside
  complement (:463), harvest (:481), prep-plan (:498). The `[AnyChatApplyAction]` mapping (:519/:539/:559)
  and the private commit helpers `commitComplementSuggestion` (:586) / `commitCapturedNote` (:598) are the
  patterns to mirror. `commitCapturedNote` already reaches `MenuRepository` inside `database.write`.
- `YesChefCore/MenuComplement.swift` — the **payload + client pattern to mirror**: `Equatable`/`Sendable`
  plan/item structs with `editableReviewText()` / `applyingEditableReviewText(_:)` (ADR-0024 round-trip),
  and the `@Dependency`-injected client with static `parse(_:)` + `liveValue` + fixture tests.
- `YesChefCore/RecipeChat.swift` — the contract: `ChatApplyAction<Payload>` (:562), `AnyChatApplyAction`
  (:670) with `requiresSubject` (:674). **`extract`'s `selection` is the raw selected text, empty when
  none**; that is the *source* (the intelligence). The *target* is new (§ below).
- `YesChefApp/RecipeChatWorkspace.swift` — selection-as-**source** plumbing that already exists, no change:
  `ChatAssistantSelection`, `actionSubject(for:)` (~:485).
- `YesChefCore/MenuChatContext.swift` — `MenuChatItemContext` (:212) already carries each item's `id`,
  `kind`, `notes`, and `recipeID`-derived fields; the target picker/selection reads from the same item set.
- `YesChefCore/Models.swift` — `RecipeNote` (:853) + `RecipeNoteType` (:884; `.general`, `.adaptation`, …);
  `YesChefCore/RecipeCore.swift` `insert(_:in:)` (:449, `RecipeNote.upsert`) is the write primitive. The
  ADR-0025 D7 reader-feedback curation is the precedent for **writing `RecipeNote` rows from a chat commit**.
- `YesChefCore/MenuCore.swift` — `addNoteItem` (:206) and the `updateNoteItem` sibling (wired at
  `MenuModels.swift:332`) — the latter is the note-revise overwrite path.

**Build/verify (house constraint, [[lean-verification-default]]):** `xcodegen generate` after adding files;
package logic via `swift build`; app via `scripts/xcodebuild-summary.sh -skipMacroValidation`, built once;
then `scripts/check-drift.sh`. **No simulator install** — Jon does the device pass (primary
`iPad Pro 13-inch (M5)`, both orientations; `iPhone 17 Pro` for the compact sheet + the target-designation
gesture, which is the thing to feel out on device).

---

## The invariant this preserves

**The model proposes; the human reviews; a tap writes** (ADR-0011). Deposit adds no auto-commit. The genuinely
new element vs. every prior menu verb is a **target**: this is the first verb that writes onto a
*pre-existing specific item* rather than adding a row or writing the whole plan. Two guardrails carry over:
**never rewrite the canonical recipe** (A2 — recipe gets an *appended* note, never an edit) and **a rewrite
is reviewed before it lands** (A3 — the note compose surface).

## Sync posture (ADR-0002)

**None.** Recipe path → `RecipeNote.upsert` on the existing `recipeNotes` table (`Schema.swift:273`). Note
path → in-place update of `menuItems.notes` (`Schema.swift:388`). No new table, column, or enum case; nothing
touches `workbenchCandidates`. Both writes are additive/in-place on already-synced tables — sync-safe by
construction.

## The new plumbing (shared by both slices) — **tap-to-target** (confirmed)

Deposit needs a **source** (chat intelligence — reuse the existing selection/latest-reply subject) **and a
target** (which menu item). No target mechanism exists today; `commitCapturedNote` even notes "menu detail …
has no selected-day state" (`MenuModels.swift:600`). **Decision (Jon, 2026-07-10): tap-to-target.**

Add a `selectedTargetItemID` to the menu detail model; **tapping an item row marks it the active deposit
target** with a visible affordance. The deposit action reads it. Matches Amd-1 A5 and directly answers Jon's
original "I don't have a way to select the note." **On device, verify the compact-layout case:** on iPhone
the chat is a sheet over the menu, so tap-item-then-run-verb spans two surfaces — confirm it's fluid (a
selection made in the menu must survive presenting the chat sheet); on iPad split-chat it's natural. (An
in-verb picker was the considered alternative — rejected for the extra modal step; do not build it.)

**Ordering constraint (why target must precede extract):** the note-revise weave needs the original note body
**as LLM input**, so `selectedTargetItemID` must be set **before** `extract` runs. Tap-to-target satisfies
this by construction (the target is chosen before the verb is invoked); a "pick target at the review step"
design would not, and is out.

**Gating:** surface the right verb by the selected target's kind — recipe-kind → "Add to recipe notes",
note-kind → "Revise this note" (per OQ-Amd-1 lean: two labels, because append and rewrite are different
promises). With no target selected, the deposit verb(s) don't appear (or appear disabled with "Select the
recipe or note to deposit onto").

## Slice plan

### S1 — the target binding + the **recipe** path (append; prove the plumbing on the cheap case)

Ships the new target-designation (§ above) on the **simplest** commit — no preview, no compose surface — so
the plumbing is proven before S2 adds UI weight.

**Payload (new, `YesChefCore`, mirror `MenuComplement`):** `DepositNotePlan { note: DepositedNote }`,
`DepositedNote { text: String }` (a recipe note is body-only; no title), `Equatable`/`Sendable`, with
`editableReviewText()` / `applyingEditableReviewText(_:)`.

**Client (new, `menuDepositClient`, `@Dependency`-injected):** `extract(intelligence:messages:tier:)` — the
**source is the chat selection/latest-reply** (the intelligence), **not** the menu context (do not copy
complement's `context:` param). The prompt is **light synthesis into a clean recipe note**: take the advisory
reasoning already in the source and reshape it into a tidy note a cook would keep; **do not invent** detail
absent from the source; return a single `{text}`. LLM always runs (reshape is the point). Static `parse(_:)`
+ fixture tests mirroring `MenuComplementTests`.

**Wiring (`MenuModels.applyActionCatalog`):** a `ChatApplyAction<DepositNotePlan>` titled **"Add to recipe
notes"**, shown only when the selected target is **recipe-kind**. Map its plan → **one**
`ChatApplyReviewItem` (the existing single-item editable review from the ADR-0026 sheet — no compose surface
needed for append). Commit → a new `commitDepositToRecipe(_:targetRecipeID:)`: build a `RecipeNote`
(`recipeID` = the target item's `recipeID`, `noteType` — *lean `.adaptation`* since this is adaptation
intelligence, `.general` acceptable; flag the choice in the PR) and `insert`/upsert via the `RecipeCore`
path. The recipe body is **never** touched.

**Prove it:** with a recipe-kind item selected as target, run "Add to recipe notes" on a Compare-style reply →
one tidy note in the review sheet → commit → a `RecipeNote` appears on that recipe. Regression-check
complement / harvest / prep-plan untouched.

### S2 — the **note** path (compose surface; reuses S1's target binding)

**Client mode:** add a `revise` mode to `menuDepositClient` (or a sibling) that additionally takes the
**target note's current body** and **weaves** it with the intelligence into a draft. Synthesis is explicitly
permitted here (a note is non-canonical, A3).

**Compose surface (the real UI work):** the review sheet for this verb shows **two panes** — the **original
note text, read-only + copyable** (preserved source), and the **LLM-woven combination as the editable
draft**. Jon edits the draft / lifts from the original; the composed text commits. This extends the ADR-0024
editable preview with a source pane (ADR-0023 side-by-side spirit), single commit destination.

**Wiring:** a `ChatApplyAction` titled **"Revise this note"**, shown only when the selected target is
**note-kind**. Commit → overwrite that note via `MenuRepository.updateNoteItem` (the `menuItems.notes`
in-place update, precedent at `MenuModels.swift:332`). The note **stays on the menu**, ephemeral; nothing is
copied elsewhere.

**Prove it:** select a note-kind item, run "Revise this note" on a Compare reply → compose sheet shows the
original beside a woven draft → edit → commit overwrites the note; the original menu note reflects the
composed text.

## Out of scope

- **Promote a note → a real recipe** (Amd-1 A6). User-triggered *where the note lives*, not this verb, not a
  queue. Deferred (base ADR-0027 D5, touches ADR-0021/0023 + [[reference-placement-and-original-provenance]]).
- **Any Workbench write** (A4 recorded reversal). "Add to Workbench" stays a separate manual affordance.
- **The seed-bubble verb model** — separate interaction concern Jon owns.
- **A third copyable pane for the raw intelligence** in the note compose surface (OQ-Amd-2 sub-choice) —
  *lean folded-into-draft only*; add only if dogfood wants it.

## Open questions (carried from the ADR)

- **OQ-Amd-1 — one adaptive label or two?** *Lean two* ("Add to recipe notes" / "Revise this note"), driven
  by target kind. Baked into the slices above; revisit at dogfood.
- **Target-designation mechanism** — **Resolved: tap-to-target** (Jon, 2026-07-10). See § The new plumbing.
- **Recipe note type** — `.adaptation` (lean) vs `.general` for deposited recipe notes. Minor; PR-flag.
