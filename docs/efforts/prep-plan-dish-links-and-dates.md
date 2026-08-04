# Effort — the prep plan knows things the model doesn't

**Status:** Slices 1–2 scoped 2026-07-26 from the PR [#237](https://github.com/jonphillips/yes-chef/pull/237)
architect review and Jon's device pass; **shipped in PR [#262](https://github.com/jonphillips/yes-chef/pull/262)**
(day-anchored labels device-confirmed). **Slice 3 scoped 2026-07-30** from the #262 device pass, **shipped in
PR [#265](https://github.com/jonphillips/yes-chef/pull/265) (merged 2026-07-30).** Slices 1–2 have **no
schema**; Slice 3 added **one column to a local-only table** (no sync, no prod-promotion entry — see the
slice). **This effort is fully shipped; see [`DONE-LOG.md`](../DONE-LOG.md) for the S3 record.**

**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).

**Related:** [ADR-0034](../decisions/ADR-0034-prep-plan-work-session-timeline.md) D2/D4 (the work-session label
and the `serves` live link) · [ADR-0040](../decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) D2/D3
(the human edits fields, never the wire format; hidden state is never re-derived from text) ·
[ADR-0042](../decisions/ADR-0042-workbench-handoff-and-the-return-block.md) Amd 1 ("the paste door never
carries identity").

---

## The theme

Two facts about a prep plan live in the app and never reach the model, and in both cases ADR-0034 designed for
the version where they do.

1. **`sourceDish`** — the dish link behind the `serves` chip. The outboard wire format cannot carry it
   (the prompt forbids menu item IDs; ADR-0042 closes the machine-section workaround), so every text return
   drops it — by design, per ADR-0040 D3. PR #237 made that loss *loud*. It is still **unrepairable**: the
   field is write-only from the LLM.
2. **The menu's calendar dates.** `MenuPlacement.startDate` is a real synced record and
   [`scheduledDate(for:)`](../../YesChefApp/MenuDetailSections.swift) already derives per-day dates — for the
   Dishes header only. `MenuChatContext` carries **no date of any kind**, so a placed menu and an unplaced one
   send byte-identical context.

Neither is a bug in a shipped decision. Both are plumbing the decisions assumed.

---

## SLICE 1 — the menu's dates reach the model (Core only)

**The gap.** ADR-0034 D2 retired the fixed horizon enum because "real session labels ('Saturday ~3 hrs out')
don't fit a fixed vocabulary," and its examples are all concrete: `"Sunday–Monday"`, `"Wednesday evening"`,
`"Saturday · ~3 hrs out"`. The model cannot produce those without knowing what day Day 2 *is*, so it invents
relative horizons instead — Jon's 2026-07-26 pass came back with "One week ahead / Two days ahead / One day
ahead / Morning of". That walks straight back into the ambiguity ADR-0034's own Context section opens with:
*"'2 days before' is '2 days before which meal?'"* On a multi-day menu those bands are genuinely
under-specified.

**Do this.**

1. **`MenuChatContext` gains the placement start date** (optional — an unplaced menu has none), populated in
   `init(detail:)` from the menu's `MenuPlacement`.
2. **Serialize concrete days.** Where the context renders `- Day: 2 (dayOffset 1)`, add the date when known:
   `- Day: 2 (dayOffset 1, Sat Aug 15)`. Add the menu's span to the header lines alongside `Duration`.
3. **The prompt asks for concrete session labels only when it can.** Two modes, and both must be explicit:
   - **placed menu** — ask for day-anchored work sessions ("Thursday evening", "Saturday, ~3 hrs out") and say
     the dates are authoritative;
   - **unplaced menu** — keep today's relative-horizon behavior. There is no day to name and inventing one
     would be worse than a relative band.
4. **`serves` improves for free** and should be mentioned in the prompt: "Saturday's Korean Bavette" beats
   "tomorrow's beef" on a multi-day menu.

**Do not** add a date to `PrepPlanStepRecord`. Sessions stay free-form labels grouped by
[`grouping`](../../YesChefApp/MenuViews.swift); the date informs *what the model writes*, never the storage.
ADR-0034 D1's one-plan-per-menu, banded-by-session shape is unchanged.

**Tests (Core):** a placed menu's serialized context contains the per-day dates and the placed-mode
instruction; an unplaced menu contains neither and keeps the relative-horizon wording; the day-scoped prep ask
(PR #237) names the day *and* its date.

**Verification:** package `swift build` + those tests + `scripts/check-drift.sh`. **No app build required** —
this slice adds no UI. Jon's device look is on the *output* (do the bands come back day-anchored on a placed
menu?), not on a screen.

---

## SLICE 2 — the dish picker, and `sourceDish` becomes human-settable

**The finding.** `sourceDish` is a field the human can neither see, type, nor repair:

- `PrepPlanStepEditorDraft` ([`MenuPrepPlanEditingViews.swift:57`](../../YesChefApp/MenuPrepPlanEditingViews.swift))
  carries session / task / serves — **no dish**.
- `PrepPlanStepRepository.update` ([`MenuPrepPlan.swift`](../../YesChefPackage/Sources/YesChefCore/MenuPrepPlan.swift))
  takes session / task / serves — **no `sourceDish` parameter**.
- `PrepPlanStepRepository.create` **does** write `draft.sourceDish`, but the app always hands it an
  editor-built draft, so it is always `nil`.

So links only ever decay. **ADR-0040 fixed the storage grain and left one field in exactly the state it
criticized** — hidden, underivable, unrepairable. This slice closes that.

**Core:**

1. **`update` gains a `sourceDish: MenuItem.ID?` parameter.** A real value, not a sentinel — `nil` clears the
   link. Update the existing call site.
2. **A matcher in Core** — given a `serves` string and the menu's item titles, return one candidate or `nil`:
   - exact match (case- and whitespace-insensitive);
   - then normalized — strip a **trailing parenthetical** (`Napa Cabbage, Cucumber & Scallion Salad (Korean)`
     ↔ `Napa Cabbage, Cucumber & Scallion Salad`), collapse internal whitespace;
   - **ambiguous → `nil`**; two items normalizing alike means no suggestion;
   - **compound `serves` → `nil`.** `Korean Bavette, Napa Cabbage, Cucumber & Scallion Salad` names two dishes
     and `sourceDish` cannot express it. Do **not** take the first. Detect by testing the whole string against
     the item list *before* any comma split — titles legitimately contain commas, so a naive split is wrong.

   **The matcher only proposes a default. It never writes.** Nothing persists until the human saves. That is
   what keeps this on the right side of ADR-0040 D3: the corollary forbids *silent* reconstruction, not a
   suggestion a human confirms.

**App:**

3. **`PrepPlanStepEditorDraft` gains `sourceDish`**, seeded from the step on edit.
4. **`PrepPlanStepEditorSheet` gains a Dish picker** below Serves — the menu's items plus an explicit **"No
   dish"**. When the draft's `sourceDish` is `nil`, pre-select the matcher's suggestion.
5. **Show that a suggestion is a suggestion** — when the selection came from the matcher rather than stored
   state, mark it (*"Matched from 'Serves'. Save to link."*). A cook must be able to tell a live link from a
   proposed one; not being able to is what made this annoying in the first place.
6. **`updatePrepPlanStep` passes `draft.sourceDish` through.**

**Tests (Core):** exact; parenthetical-normalized; ambiguous → nil; compound → nil; a comma-containing title
is not mis-split; empty `serves` → nil.

**Acceptance:** an inert chip is relinked in two taps; a hand-authored step can be linked at creation; "No
dish" clears a link and sticks; a compound `serves` offers no default.

**Verification:** package build + those tests, then the generic app build + `scripts/check-drift.sh`. Device
pass on iPhone — the editor sheet is a compact-width surface.

---

## SLICE 3 — the omission guard is for accidental drops, not for a regenerate

**✅ SHIPPED — PR [#265](https://github.com/jonphillips/yes-chef/pull/265), merged 2026-07-30.** Record in
[`DONE-LOG.md`](../DONE-LOG.md). The scoped brief below is retained as-built.

**Scoped 2026-07-30 from the #262 device pass.** Slice 1 works: on the placed NJ-Avalon menu the bands came
back day-anchored ("Previous Saturday afternoon", "Previous Sunday"). But regenerating the plan lit up the
"Review omitted steps before saving" banner on **nearly every existing step**.

**The finding.** [`omittedCurrentPrepStepEvidence`](../../YesChefPackage/Sources/YesChefCore/AIHandoff.swift)
diffs the current plan against the returned plan on **exact visible content** — `PrepPlanStepVisibleContent` =
`session` + `task` + `serves`. A *refinement* that keeps most steps produces a short, meaningful list ("you
dropped the broccoli step"). A *regenerate* rewrites the `session` labels — which is Slice 1's whole purpose —
**and** rephrases the `task` prose, so 100% of prior steps read as "missing." The guard is doing exactly what
it was built for (ADR-0040 lossless-or-loud: never silently drop a step), but it is answering the wrong
question. Its question — *"did the model silently drop work I meant to keep?"* — only makes sense against an
edit that was meant to be **incremental**. A regenerate is intended **wholesale replacement**. Slice 1
therefore *guarantees* this banner fires on the first post-Slice-1 regenerate of any pre-Slice-1 plan.

**The reframe.** The variable is **refine vs regenerate intent**, not the transport (onboard button vs outboard
paste). Both today funnel through the same [`AIHandoffReviewStager.menuReview`](../../YesChefPackage/Sources/YesChefCore/AIHandoffIntentImport.swift),
so the outboard "Paste Prep" path would blow up identically. Fix the *intent*, in one place, for both
transports:

- **Refine** → baseline = the current plan; the omission guard fires loud. Unchanged. This is the
  accidental-drop protection ADR-0040 exists for.
- **Regenerate** → baseline = **empty**; no omission list and no dropped-link list, because nothing was meant
  to be preserved. Surface a single light confirmation instead ("This replaces your 24-step prep plan"). The
  loss is **declared**, not silent — still on the right side of ADR-0040.

**Core.**

1. **An intent value (`.refine` / `.regenerate`) drives the advisory diff.** On `.regenerate`, both
   `omittedCurrentPrepStepEvidence` *and* `droppedSourceDishEvidence` run against an empty baseline (→ empty),
   so `advisoryNotes` is empty and the review presents as a clean replacement. On `.refine`, behavior is
   byte-for-byte what it is today. Thread the intent into `menuReview` — do **not** infer it from how many
   steps happen to match, which is the exact fragile heuristic that produced the false positives.
2. **Persist intent on the `AIHandoff` row for the outboard round-trip only.** The intent must survive the
   copy→paste gap, and the persistent handle is the `aiHandoffs` row (`status == .awaitingReturn` between copy
   and paste). Add a column (e.g. `regenerates: Bool`, default `false` so every existing row reads as
   `.refine`). **`aiHandoffs` is not registered in `CloudSync` — it is a local-only table**, so this is a
   plain local migration: **no prod-schema-promotion entry, and none of the deterministic-UUID
   sync-migration rules apply** ([[migration-writes-bypass-sync-triggers]] is about *synced* tables and does
   not bite here). Read the column in `menuReview` and map it to the intent. Keep `aiHandoffs` local — a
   regenerate flag is transient workflow state, not a synced record; do not add it to the sync list on
   momentum ([[withdraw-not-defer-orphaned-schema]]).
3. **The onboard path needs no schema at all.** Onboard staging builds a *transient* `AIHandoff`
   (`stageOnboardReview`, [HandoffReviewCoordinator.swift](../../YesChefApp/HandoffReviewCoordinator.swift),
   `handoffID: uuid()`, never written), so onboard intent is a plain in-memory parameter. The column exists
   **solely** to ferry intent across the outboard paste door — say so, so it is not mistaken for the onboard
   fix.

**App.**

4. **Onboard: `regeneratePrepPlan()` sets `.regenerate`;** the chat "Apply…" / Finalize path stays `.refine`.
   This alone fixes the banner Jon hit — and needs no migration.
5. **Outboard: a new "Handoff to Regenerate" action** in the prep-plan `…` menu, beside the existing
   ["Handoff Prep"](../../YesChefApp/MenuViews.swift) (which stays `.refine`). It stamps `.regenerate` on the
   persisted handoff row at copy time; "Paste Prep" then reads it and reframes instead of flooding omissions.
   Keep the two actions visibly distinct — "Handoff Prep" refines the plan you have, "Handoff to Regenerate"
   asks for a fresh one.
6. **Reframe the review header for regenerate.** With `advisoryNotes` empty, `prepPlanEvidenceTitle` already
   falls through to no error banner — but add a positive, non-alarming "replaces your N-step plan"
   confirmation so a full replacement is never a surprise. Do **not** reuse the "Review omitted steps"
   language.

**Tests (Core):** `.regenerate` → `omittedCurrentPrepStepEvidence` and `droppedSourceDishEvidence` both return
`[]` even when zero steps match; `.refine` → the existing evidence tests are unchanged; intent round-trips on
the `aiHandoffs` row through stage; the migration adds the column and existing rows read as `.refine`.

**Verification:** package build + those tests + `scripts/check-drift.sh`, then the **generic app build**
(App-layer: the new menu action and the review reframe). **This is a local migration, so it does *not* need a
two-device sync pass** — Jon's device look confirms three things: (a) onboard regenerate no longer floods
omissions, (b) outboard "Handoff to Regenerate" → paste returns a clean replacement, (c) a genuine refine
still surfaces a real dropped step. No prod-promotion entry.

---

## Sequencing

**Slice 1 first, then Slice 2**, though they are independent and can ship in one dispatch. Two reasons: Slice 1
is Core-only and its result is visible to the cook immediately, and it **changes the shape of `serves`** — a
placed menu should start producing "Saturday's Korean Bavette" — so Slice 2's matcher wants writing against
the post-dates output rather than being retrofitted to it. If they do ship together, write the matcher tests
to cover both shapes.

**Slice 3 ships after Slices 1–2 (PR #262) merge, in its own PR.** It is independent of the S1/S2 *data* but
only *reachable* because Slice 1 makes a regenerate rewrite every label. Keep it out of #262: those slices are
already device-passed and green, and Slice 3 brings a new outboard action, a review reframe, and a local
migration that each want their own focused pass rather than reopening tested work.

## Explicitly out of scope

- **Auto-relinking on a text match without a human gate.** ADR-0040 D3 — and the dogfood data shows why: exact
  match succeeds on `Korean Bavette` and fails on `…Salad (Korean)`, so half the chips would silently return
  and half would not, with nothing explaining the difference.
- **Multi-dish steps.** `sourceDish` is a single optional. Real multi-links are a schema change and their own
  ADR — record the want, do not build it.
- **A date on `PrepPlanStepRecord`.** ADR-0034 D1; see also PR #237's round 1, where scoping the *ask* rather
  than the *storage* was the fix.
- **Changing the outboard wire format to carry ids.** Closed by ADR-0042 Amd 1.
- **(Slice 3) Fuzzy / similarity matching of reworded steps in the refine diff.** It fights ADR-0040's
  exact-match-or-loud rule, and on a regenerate — where the prose genuinely changed — it would not help
  anyway. The fix is intent, not a smarter diff.
- **(Slice 3) Any change to Slice 1's storage or grouping.** The one-plan-per-menu, banded-by-session shape
  (ADR-0034 D1) is untouched; Slice 3 only changes which *baseline* the advisory diff compares against.
- **(Slice 3) Making `aiHandoffs` synced.** It stays local; the regenerate flag is transient workflow state.

## Handoff note

Slice 2 makes `sourceDish` human-settable for the first time. Worth a one-line amendment to
[ADR-0040](../decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) recording that the corollary's accepted
cost ("text imports intentionally drop the chip") is now **recoverable by hand** rather than permanent — the
decision is unchanged, its consequence is softened.

Slice 3 does not touch a synced table, so it adds nothing to the prod-schema promotion list. It is worth a
one-line note in ADR-0040 (or wherever the omission guard is recorded) that lossless-or-loud is scoped to
**refinements**: a user-declared **regenerate** is intended wholesale replacement, so suppressing the omission
list there is not a silence the rule forbids.
