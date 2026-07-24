# Effort: ADR-0045 V1 review fixes (2026-07-24)

**Type:** Review revision of an **open PR** — [#227](https://github.com/jonphillips/yes-chef/pull/227)
(`codex/adr-0045-v1-seeded-section-ask`). **Same branch, same PR** — do not open a new one, do not rebase
onto a fresh branch. The Core extraction in #227 is correct and stays; the defects are in the app-layer
wiring and in *what* gets seeded.
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Ready** — dispatched from the 2026-07-24 architect review of #227.

**Read before starting:** [ADR-0045](../decisions/ADR-0045-onboard-path-stays-viable.md) in full (it is the
spec — D2, D3, D6 and OQ3/OQ4 are all load-bearing here), then the PR #227 diff, then
`RecipeChat.swift` (`RecipeChatModel.init` → `loadPersistedThread`, `systemPrompt()`,
`RecipeChatRecipeContext.serialized(excludingPlaybookSections:)`), `AIHandoffContext.swift` (the section
prompt builders + `bounded`), `MenuChatContext.swift` (`prepPrompt`), and `RecipeChatWorkspace.swift`
(`latestReplySubject` / `canRun`). Then `CURRENT_HANDOFF.md` § Verification Pattern.

**Two invariants from the ADR still bind, and neither is relaxed by anything below.** **Do not loosen
`requiresSubject`** (D6). **Do not expand scope past the three section-scopable entry points** — the
meal-calendar and Workbench cold starts stay a recorded follow-on (OQ3), even though S3 below makes them
look easy.

**Build/verify:** `xcodegen generate` only if files are added; elevated `generic/platform=iOS` build
(required evidence for app-layer work); Core suite; `scripts/check-drift.sh`. **No simulator installs** —
Jon device-passes. S4 in particular is a *behavior* change that only a real first reply can confirm; ship it
and say plainly in the PR that it is unverified until Jon's pass.

---

## S1 — Seed only a **cold** thread (blocker)

**Bug.** `RecipeChatModel.init` calls `loadPersistedThread()`, and chat threads persist for 30 days keyed
per-recipe / per-menu. Both new call sites in #227 send the seed unconditionally, so every re-open of a
recipe or menu that already has a saved thread appends **another full seed** to the restored transcript and
fires **another model call** — and `history()` ships the whole growing thread on each one. It is also
pointless: a restored thread already ends in an assistant reply, so `latestReplySubject` is non-nil and the
verbs are already lit. **Only the cold start needs a seed — that is exactly what OQ4 resolved.**

**Fix.** Put the rule in Core, not at the call sites:

```swift
/// Sends `text` only when the thread is cold. The seeded opener exists to remove a cold start
/// (ADR-0045 OQ4); a restored thread already has a reply, so `latestReplySubject` is already non-nil.
public func seedIfCold(_ text: String) async
```

Guard on `messages.isEmpty` (and the existing `!isResponding, responseTask == nil` guard inside `send`).
Route the recipe **panel-open** path and the menu **Ask** path through it. Core-testable, and it cannot be
gotten wrong at the two further entry points OQ3 already tells you are coming.

**Keep `send` public and unguarded** — S2 and S5 both need an *explicit* send into a warm thread.

## S2 — The section-menu Ask must re-scope, not dismiss (blocker)

**Bug.** `RecipeDetailModel.chatButtonTapped` closes the panel whenever a chat is open. On wide iPad the Ask
panel is an explicit non-modal companion, so the normal flow is: open Ask from Make-ahead → tap **Ask** in the
Serve With section menu → **the panel closes.** Only the first section you touch is ever scoped, and the
section menus otherwise read as a dismiss button. D3 says section-scoped at *every* entry point.

**Fix.** Track the section the open panel was seeded for (e.g. `private(set) var seededAskSection:
PlaybookSectionKind?` on `RecipeDetailModel`, set on open, cleared when `destination` clears). Then:

| Invocation | Behavior |
|---|---|
| No chat open | Open + `seedIfCold` for the invoked section |
| Chat open, **same** section (incl. the column-top Ask ↔ `.makeAhead`) | Close — today's toggle, unchanged |
| Chat open, **different** section | **Keep the open model and its transcript**, `send` that section's seed, update `seededAskSection` |

The different-section case deliberately uses `send`, not `seedIfCold`: the cook explicitly asked about
another section, so the opener is wanted even though the thread is warm. Do **not** rebuild the chat model —
the existing comment's "rather than rebuilding the model and discarding the scratch transcript" intent holds.

## S3 — Stop shipping the recipe/menu twice, at the wrong budget (blocker)

**Bug.** `systemPrompt()` already embeds the subject via `context.serialized(for: activeTier)`. The seed then
embeds the *whole subject again*: `RecipeHandoffContext.prompt(for:)` appends `bounded(...)`, hardcoded to
`frontierSerializedCharacterBudget` (120k), and `MenuChatContext.prepPrompt()` serializes at
`.frontierPreferred` — **both tier-blind**. On the on-device tier (12k budget — the tier this whole ADR
hedges toward) the first turn carries a tier-budgeted copy *plus* a copy allowed to be 10× the tier budget.
That is [[reasoning-budget-starves-output]] with the safety rail bypassed. On a short recipe it is "merely"
2× the context; on a long one with notes, learnings, and reader feedback it is a blowout.

**Root cause, and it is a design seam, not a slip.** The outboard prompt is **self-contained by
construction** — it lands in a bare external thread with no system prompt, so it must carry its own context.
Onboard it lands *on top of* a system prompt that already owns subject, context, and tier budgeting. D2's
"one prompt source per verb" is right; the reusable part is the **framing + preferences + finalize
convention**, not the context payload.

**Fix.** Add an explicit destination to the prompt builders — e.g.

```swift
public enum AIHandoffPromptDestination: Equatable, Sendable { case outboard, onboard }
```

— threaded through `RecipeHandoffContext.prompt(for:destination:)` (defaulting to `.outboard` so every
existing caller is untouched), the three private section builders, and `MenuChatContext.prepPrompt`. It
controls **exactly two things**:

1. **The trailing `\(context)` block is omitted for `.onboard`.** The system prompt supplies it, at the
   active tier.
2. **Transport-only sentences are omitted for `.onboard`** — specifically the menu prompt's *"This text will
   be pasted back into the recipe app, so do not include commentary, Markdown fences, menu item IDs, or
   JSON."* Nothing is pasted onboard; that sentence is simply false there.

**Everything else stays byte-identical**, including the framing, the `lineListFormat` contract, the taste
profile, the per-verb preference, and *"The return must be plain, paste-ready review text — not JSON —
because the cook reviews and edits it in Yes Chef before it is saved"* (that one is **true onboard** — the
`ChatApplyReviewSheet` is exactly that review). The existing outboard tests must pass **unmodified**; if one
needs editing, you have changed the outboard string and that is a bug.

**Two things that look like follow-on fixes and are NOT — read both before you "helpfully" tidy them:**

- **Keep the `knownLearnings` block in the onboard seed.** `RecipeChatRecipeContext.serialized` does *not*
  emit learnings, so the system prompt has no copy. Drop only `\(context)`.
- **The onboard discussion WILL see the current content of the section being discussed**, because the chat's
  system-prompt serialization does not exclude it, whereas the outboard hand-off deliberately does
  (`excludingPlaybookSections:` — "keeps a fresh hand-off from echoing its own prior output"). **This is
  intended onboard and must not be replicated.** A discussion about improving what is already written wants
  to see what is already written; the exclusion is a blind-*regeneration* concern. Do not thread a section
  exclusion into `RecipeChatContext`.

**Also out of scope, deliberately:** `RecipeChatContext.serialized(for:)` ignores the tier for the `.recipe`
and `.mealPlan` cases and always uses the 12k default. That is **pre-existing shipped behavior**, it is the
baseline every recipe chat has always run at, and it is ADR-0043 S3's territory. Note it in the PR body;
do not fix it here.

## S4 — One line, so the opener opens instead of dumping (blocker)

**Bug.** After S3 the first turn still carries **three formatting contracts at once**: the system prompt says
short plain prose, no headings or bullets; the section prompt says flat line-list, no bullets or Markdown
emphasis; and `discussAsk` then appends *"You may discuss this freely."* The likeliest first reply is an
immediate full deliverable dump — which technically satisfies D6 (a reply exists, the verbs light up) while
missing the entire point of a *discussion* opener.

**Fix.** For `.onboard` only, append one sentence after the discuss clause, to the effect of:

> The format above describes the finalized return, not this conversation — discuss conversationally until the
> cook asks you to finalize.

**Flag it honestly in the PR body: this is the one place this dispatch authors new prompt text**, and
ADR-0045's "What this does not do" says *"It does not re-author any prompt."* It is an **onboard-only**
addition that leaves the outboard string untouched, which is why it is being taken rather than worked around.
**This is already recorded — see [ADR-0045 Amendment 1](../decisions/ADR-0045-onboard-path-stays-viable.md#amendment-1--the-onboard-seed-reuses-the-outboard-prompts-framing-not-its-payload)
(A2), which is the governing text for S3 and S4 both. Do not edit the ADR yourself.**

## S5 — The nits (all small, all in the same files)

1. **Delete the `= .makeAhead` default** on `chatButtonTapped(section:)`. Both call sites already pass
   explicitly, so it is unused — and a defaulted section argument is the *exact* "section silently dropped"
   affordance the ADR's Context table diagnoses. Do not leave the trap re-armed.
2. **`MenuViews.ensureChatIsOpen` is misnamed and non-idempotent** — it rebuilds the model and now fires a
   model call on every call, and it is *also* wired as `regeneratePrepPlan:` (`MenuViews.swift:179`), so
   "regenerate" discards an open panel and fires a fresh seed. Split the two intents:
   - **Ask** → open if needed, then `seedIfCold`.
   - **Regenerate prep plan** → open if needed, then an explicit `send` (regenerate genuinely wants a fresh
     opener on a warm thread), **without** discarding an open panel's model.
   Rename accordingly (`presentAsk()` / `regeneratePrepPlan()` or similar).
3. **Make the menu's deliverable format explicit.** `AIHandoffToken.discussAsk(context:deliverableFormat:)`
   defaults to `.menuPrepPlan`; a defaulted deliverable format on a shared Core helper will eventually glue
   prep-plan wording onto a Chef It Up context. Pass `.menuPrepPlan` at the menu call site. (Keep the default
   on the parameter if removing it churns `prompt`'s existing convention — the call-site explicitness is the
   point.)
4. **Seed failure must not be worse than the cold panel.** If the seed call fails (no API key, on-device
   unavailable), today's result is a wall of machine-authored text attributed to the cook, *and* still-gray
   verbs. At minimum, when the seeded send fails, remove the seed user-message so the panel returns to its
   honest empty state with the existing `errorText` shown. Do not silently swallow the error.

## Tests

Core, in `YesChefCoreTests` — the two blockers are currently invisible to the suite:

- **S1:** a chat model constructed against a persisted non-empty thread does **not** append a seed on
  `seedIfCold`; a cold one does. One test each.
- **S3:** for each of the three sections + the menu, `prompt(for:destination: .onboard)` **excludes** the
  serialized subject block, **retains** the known-learnings block, and is otherwise a substring-for-substring
  match of the `.outboard` text (framing, format contract, taste profile, preference). Assert the menu's
  paste-transport sentence is present outboard and absent onboard.
- **S4:** the onboard seed contains the discussion-precedence sentence; the outboard prompt does not.
- **Regression guard:** keep #227's existing `exported.hasSuffix(ask)` assertions passing for the outboard
  path — that is the proof D2's one-prompt-source claim still holds.

S2 is app-layer; cover what you can by keeping the section-switch decision in `RecipeDetailModel` (a plain
function over `seededAskSection` + the invoked section) rather than inline in the view.

## Out of scope — do not do

- Loosening `requiresSubject` (D6).
- The meal-calendar and Workbench cold starts (OQ3 follow-on).
- V2's Finalize button, and any `AIHandoffReturn` wiring.
- V3 / the frontier-model setting — that rides ADR-0043 S3, which is a **separate parallel PR**. Do not touch
  tier resolution or AI Settings on this branch.
- Any schema change. ADR-0045 adds none.
