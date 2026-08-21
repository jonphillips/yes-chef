# Effort: the learnings parser floor, and the paste door that rescopes a return (2026-08-19)

**Type:** Two PRs off one dispatch. **No schema. No new tables, no columns, nothing added to the promotion
list.** No new `.swift` files except one small model extension (so `xcodegen generate` *is* required).
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** Designed, ready to dispatch. **PR A unblocks Jon's testing immediately** — he currently cannot
produce a single recipe learning by any route.
**Summary:** A recipe hand-off return was rejected with *"Each learning must begin with a bullet"* — a rule
that exists nowhere in the return contract. `learningBullets` accepts only `- `/`* `/`• `, and on the recipe
and workbench-compare paths a single non-conforming line throws away **the entire return, deliverable
included**. Compounding it, there is no in-app way to author a recipe learning at all, and the recipe
Learnings section is hidden when empty — so the only door to the feature is the one that's broken. Separately,
pasting a variation-scoped return into the base-recipe door reports "doesn't match" and, on *Review Anyway*,
silently rescopes the revision to the base recipe.
**Related:** [ADR-0038](../decisions/ADR-0038-external-llm-handoff.md) Amd 1 (the two-part return), Amd 2 (the
in-app door), Amd 4 (append-only ingest + exact dedup) · [ADR-0040](../decisions/ADR-0040-editable-at-the-grain-it-is-stored.md)
(lossless-**or-loud** — this is loud *and* lossy, the worst corner) · [ADR-0021](../decisions/ADR-0021-recipe-variations.md)
(variation scope) · [ADR-0042](../decisions/ADR-0042-workbench-handoff-and-the-return-block.md) Amd 4 (the
dual-sink recipe-body return this sits in front of).

**Read before starting:** ADR-0038 Amd 1 and Amd 4, then `CURRENT_HANDOFF.md` Verification Pattern. **Do not
read `DONE-LOG.md`.**

---

## The finding, precisely

The contract's only statement about learnings, in `AIHandoffReturnContract.projectInstructions`
(`YesChefPackage/Sources/YesChefCore/AIHandoff.swift:628`) and its pasted twin
`docs/chatgpt/PROJECT-INSTRUCTIONS.md:7`:

> Include a `YC-LEARNINGS:` section with distinct durable learnings unless the hand-off expressly asks you to
> omit it.

No bullets. But `learningBullets` (`AIHandoff.swift:968`) accepts a line **only** if it begins with exactly
`- `, `* `, or `• `. Numbered learnings, en/em-dash bullets, `#`-prefixed anything, a code fence the model was
told not to emit but emitted anyway, or plain sentences — all contract-compliant — parse to **zero learnings**
and a pile of remainder. Then:

| Path | A non-conforming line in `YC-LEARNINGS:` |
|---|---|
| Menu prep plan (`AIHandoffIntentImport.swift:135`) | carried into review as evidence |
| Meal plan (`:225`) | carried into review as evidence |
| Reader feedback (`:47`) | throws only if **nothing** parsed |
| **Recipe (`:180`)** | **throws — deliverable discarded** |
| **Workbench compare (`:255`)** | **throws — deliverable discarded** |
| **Commit of hand-edited learnings (`HandoffReviewCoordinator.swift:424`)** | **refuses to save** |

The recipe throw sits *above* the `switch handoff.taskType`, so it takes down Make-Ahead, Chef It Up, Serve
With, **and** the ADR-0042 Amd-4 revision brief alike.

The test `learningBulletsPreserveNakedSentencesAndParagraphsAsRemainder`
(`YesChefPackage/Tests/YesChefCoreTests/AIHandoffTests.swift:110`) **asserts the floor**. It is not a
regression guard to preserve — it locked in the defect, and this dispatch rewrites it.

---

## Where the code is

| Thing | Location |
|---|---|
| The parser | `YesChefPackage/Sources/YesChefCore/AIHandoff.swift:968` (`learningBullets`) |
| Its return type | `:852` (`LearningBulletsReturn`), `:846` (`PlainTextReturn`) |
| Section splitter (leave alone) | `:994` (`splitting`), `:1005` (`isLearningsMarker`) |
| Recipe throw | `YesChefPackage/Sources/YesChefCore/AIHandoffIntentImport.swift:180` |
| Workbench-compare throw | `:255` |
| Error cases | `AIHandoff.swift:1030`, `:1050` (`unparsedLearningLines`) |
| Commit throw + message | `YesChefApp/HandoffReviewCoordinator.swift:424`, `:959` (`HandoffReviewError`) |
| The learnings review item | `HandoffReviewCoordinator.swift:329` |
| **The evidence precedent to copy if ever needed** | `HandoffReviewCoordinator.swift:247` (meal-plan strategy) |
| Shared Learnings UI (already supports Add) | `YesChefApp/MenuPrepPlanEditingViews.swift:177` (`LearningsSection`) |
| Menu call site — passes `addLearning` | `YesChefApp/MenuPlaybookColumnView.swift:203` |
| **Recipe call site — gated on non-empty, no `addLearning`** | `YesChefApp/RecipePlaybookView.swift:103` |
| Menu's in-app create (the model to mirror) | `YesChefApp/MenuDetailModel+PrepPlanEditing.swift:11` |
| Recipe learning model funcs (where the mirror goes) | `YesChefApp/RecipeDetailModel+Enrichment.swift:287-330` |
| Paste-door routing | `YesChefApp/HandoffInAppTransport.swift:62` (`stageReview`), `:23` (`unmatchedMessage`) |
| Scope match | `YesChefApp/AppIntents/HandoffIntents.swift:228` (`matches`), `:170` (`metadata`) |
| Synthesized handoff for a known source | `HandoffIntents.swift:752` (`stageReviewForKnownSource`) |
| Stale pasteboard snapshots | `RecipeVariationPromotionPresentation.swift:138`, `RecipeDetailView.swift:203`, `RecipePlaybookView.swift:339`, `MenuViews.swift:392`, `HandoffInAppTransport.swift:263` and `:275` |

---

# PR A — the parser floor and the missing door

## S1 — the parser stops inventing a rule

Rewrite `learningBullets` as a **tolerant** extractor and rename it, because the name is what taught the
strictness: `learningBullets` → **`learnings(from:)`**, `LearningBulletsReturn` → **`LearningsReturn`**. Five
call sites (`AIHandoff.swift:865`, `:960`, `HandoffReviewCoordinator.swift:423`, plus tests) — take the churn.

Per line of the `YC-LEARNINGS:` section, after trimming whitespace:

- Skip empty lines and lines that are **only** a code fence (` ``` ` with an optional language tag). A fence
  carries no content; this is the one silent drop.
- Strip a leading list marker if present, then re-trim: any of `-` `*` `•` `–` `—` `‣` `·` (with or without a
  following space — `-text` is a bullet), a leading `#`+ run, or an ordinal `^\d{1,3}[.)]\s+`.
- **Whatever non-empty text remains is a learning.** No line inside a `YC-LEARNINGS:` section is rejected.
- Keep ADR-0038 Amd-4 exact dedup (the existing `seen` set), unchanged.

**`unparsedLines` therefore goes to `[]` for learnings and the concept leaves this parser.** Delete
`LearningsReturn.unparsedLines` and `PlainTextReturn.unparsedLines` rather than leaving always-empty plumbing
([[withdraw-not-defer-orphaned-schema]] applied to a field). `MenuPrepPlanReturn.unparsedLines` **stays** — its
entries come from the *deliverable* parse, which is a different and still-correct strictness.

**The human is the filter, not the parser.** A stray `Learnings:` header or a model's chatty sign-off becomes
a junk learning — visible, editable, and one swipe from gone in the review sheet. That is the trade this
design already made when it made learnings an editable review item; losing an entire return to protect
against a stray line is not.

**Do not touch `AIHandoffReturnContract.version`.** It stays `2.1`. The parser change makes the shipped
contract sufficient, and a bump silently invalidates the project instructions in every chat app Jon has
pasted them into (standing guard). No prompt text changes in this effort.

## S2 — a stray line stops destroying the return

- Delete the `guard returned.unparsedLines.isEmpty else { throw }` at `AIHandoffIntentImport.swift:180` and
  `:255`.
- Delete the guard at `HandoffReviewCoordinator.swift:424`.
- Delete `AIHandoffIntentImportError.unparsedLearningLines` and `HandoffReviewError.unparsedLearningText`
  once unused — grep first; leave the *reader-feedback* and *prep-plan* unparsed cases alone, they are live.
- `HandoffReviewError.emptyLearnings`: *"Add at least one bulleted learning before saving."* → *"Add at least
  one learning before saving."*
- `mealPlanReview` (`:225`) currently sums `parsed.unparsedLines + returned.unparsedLines`; drop the second
  term with the field.

Do **not** add an evidence panel for learnings remainder. After S1 there is no remainder to show, and building
the panel anyway is the orphaned half of a design.

## S3 — a recipe can have a learning without an LLM in the loop

Today `createLearning` exists only on `MenuDetailModel`, and `RecipePlaybookView:103` hides the Learnings
section entirely when the list is empty — so on a recipe there is no add button, no empty state, and no way
in. That is why the library has zero recipe learnings.

- Add `RecipeDetailModel.createLearning(_ text: String) -> LearningCreationResult` in
  `RecipeDetailModel+Enrichment.swift`, a direct mirror of `MenuDetailModel+PrepPlanEditing.swift:11`:
  `LearningRepository.insertNew(texts: [text], sourceType: .recipe, sourceID: recipeID, provenance: .inApp, …)`,
  same duplicate toast, same error surfacing. `LearningCreationResult` is already shared — do not redeclare it.
- `RecipePlaybookView:103` — **drop the `if !model.learnings.isEmpty` gate** and pass
  `addLearning: model.createLearning`. `LearningsSection` already renders the "No Learnings Yet"
  `ContentUnavailableView` and the Add Learning row; nothing new is needed in the shared component, and the
  menu call site is the working reference.

---

# PR B — the paste door stops rescoping the return

## The rule

**The token is the authority for scope; the paste door is only a door.** Today a return's target is decided
by *where it was pasted*, which is why a variation-scoped brief pasted at the base-recipe door reports a
mismatch and then, on *Review Anyway*, commits against the base — `stageReviewForKnownSource`
(`HandoffIntents.swift:752`) rebuilds a synthetic handoff from the **door's** metadata, `variationID: nil` and
all. The same shape lets a Make-Ahead return pasted into the Serve With door be parsed as a Serve With list.
The stored `aiHandoffs` row already carries the true `sourceType`/`sourceID`/`taskType`/`variationID`/
`dayOffset`, and the matched path already routes by it.

## S4 — route by the resolved row

In `HandoffInAppTransport.stageReview` (`:62`):

- **Token resolves to a stored hand-off → always route by that row**, whatever door it was pasted into. No
  warning for a scope difference *within the same item* (same `sourceType` + `sourceID`): a different
  `taskType`, `variationID`, or `dayOffset` is the token telling us where it belongs. Post a toast naming the
  real target so the redirect is visible, e.g. *"Reviewing against the "Spicy" variation."*
- **Token resolves to a hand-off on a different item** (different `sourceID`) → keep the confirmation, with
  accurate text naming both ends, and on confirm route to the **stored row's** item, not the door's.
- **No token, or an ID with no stored row** → unchanged. This is the legitimate `stageReviewForKnownSource`
  case (a regenerated or hand-typed result), and the door is correctly the only signal available.
- Narrow `HandoffExportSource.matches` (`HandoffIntents.swift:228`) to *same item* accordingly, or replace it
  with a small `resolution` enum — Codex's call, but the reader-feedback branch keeps its own capture-scoped
  check untouched.
- `applyingScope(to:)` (`:255`) stamps `dayOffset` from the door onto menu-day complements. Drive it from the
  **resolved row's** `dayOffset` when there is one; leave the no-token path on the door.
- The unmatched alert copy at `HandoffInAppTransport.swift:23` is wrong today even in the case it survives —
  *"The handoff ID is missing or doesn't match this recipe"* was shown when the ID matched perfectly and only
  the variation differed. Rewrite it to say which of the two actually happened.

The revision-brief sheet's scope banner (`HandoffReviewCoordinator.swift:773`) stays — after S4 it should
never disagree with the row, and it is the last visible check if it ever does.

## S5 — delete the stale pasteboard snapshots (folds into PR B)

`.disabled(!UIPasteboard.general.hasStrings)` appears at six sites (table above). It is a snapshot taken when
the **view body** is evaluated, not when the menu opens, so a Paste item can sit greyed out against a
clipboard that has held the result for minutes — which is how the Choices-row Paste appeared dead while the
toolbar's worked. Universal Clipboard produces the same false negative for a not-yet-fetched remote item.

Delete all six. Every one of those actions already handles the nil case deliberately and routes the empty
string to the transport for visible feedback (`HandoffInAppTransport.swift:100`) — the guard buys nothing and
costs a dead-looking button.

---

## Doc updates riding along

- **`ADR-0038` Amendment 7** — the parser floor rule (a `YC-LEARNINGS:` line is a learning, format-agnostic;
  the review sheet is the filter) and the token-is-authority routing rule. **The architect writes this**; do
  not draft it in the PR.
- `docs/CURRENT_HANDOFF.md` done/next edit rides in **PR A's own commit**, read from `main`
  ([[handoff-bump-rides-in-slice-pr]]). PR B gets its own bump. Never a separate doc PR.

## Verification

Per `CURRENT_HANDOFF.md` Verification Pattern, plus:

- `swift build` the package for S1/S2; the app build is required for S3–S5.
- `xcodegen generate` if any new `.swift` file lands (S3 should extend the existing
  `RecipeDetailModel+Enrichment.swift`, so ideally none does — but run it if one does, it is a build-claim
  tripwire).
- **Rewrite `AIHandoffTests.swift:110`** to assert the new floor, and add cases for: `1. `/`2) ` ordinals,
  `– `/`— ` dashes, `-text` with no space, a stray ` ``` ` fence, a naked sentence, and mixed bullets and
  sentences in one section. Add a recipe-path test proving a **deliverable survives** a non-bullet learnings
  line — that is the regression this whole effort exists for.
- Run the **`YesChefTests` app target** — S3 touches `RecipeDetailModel`. Standing Codex-env gotcha: that
  target cannot run in Codex's sandbox; say so plainly rather than claiming a pass, and the architect runs it
  locally ([[codex-build-excuse-reproduce]]).
- **No simulator installs.** Jon does the device pass.

## For Jon's device pass

1. On a recipe with no learnings: the Playbook shows the **Learnings** section with its empty state and an
   **Add Learning** row. Add one by hand; it persists and badges *Hand-authored*.
2. Hand off a Playbook section, have the outboard return `YC-LEARNINGS:` as a **numbered list**, paste back —
   learnings land, deliverable intact.
3. Same, with learnings as **plain sentences, no markers at all**.
4. Hand-edit the learnings box in the review sheet into prose and Save — it saves.
5. Hand off from a **Choices** variation row, then paste at the **base recipe toolbar** door — no mismatch
   alert; a toast names the variation; the brief's scope banner says *variation*.
6. Paste a Make-Ahead return into the **Serve With** section door — it opens the Make-Ahead review, not a
   mangled Serve With list.
7. Copy a result in ChatGPT, return to a recipe you were already looking at, open the Choices row menu —
   **Paste is enabled**, first try.
