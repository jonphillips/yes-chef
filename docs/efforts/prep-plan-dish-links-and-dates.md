# Effort — the prep plan knows things the model doesn't

**Status:** scoped 2026-07-26 from the PR [#237](https://github.com/jonphillips/yes-chef/pull/237) architect
review and Jon's device pass. Dispatch-ready. **No schema** — both slices use fields that already exist and
already sync.

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

## Sequencing

**Slice 1 first, then Slice 2**, though they are independent and can ship in one dispatch. Two reasons: Slice 1
is Core-only and its result is visible to the cook immediately, and it **changes the shape of `serves`** — a
placed menu should start producing "Saturday's Korean Bavette" — so Slice 2's matcher wants writing against
the post-dates output rather than being retrofitted to it. If they do ship together, write the matcher tests
to cover both shapes.

## Explicitly out of scope

- **Auto-relinking on a text match without a human gate.** ADR-0040 D3 — and the dogfood data shows why: exact
  match succeeds on `Korean Bavette` and fails on `…Salad (Korean)`, so half the chips would silently return
  and half would not, with nothing explaining the difference.
- **Multi-dish steps.** `sourceDish` is a single optional. Real multi-links are a schema change and their own
  ADR — record the want, do not build it.
- **A date on `PrepPlanStepRecord`.** ADR-0034 D1; see also PR #237's round 1, where scoping the *ask* rather
  than the *storage* was the fix.
- **Changing the outboard wire format to carry ids.** Closed by ADR-0042 Amd 1.

## Handoff note

Slice 2 makes `sourceDish` human-settable for the first time. Worth a one-line amendment to
[ADR-0040](../decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) recording that the corollary's accepted
cost ("text imports intentionally drop the chip") is now **recoverable by hand** rather than permanent — the
decision is unchanged, its consequence is softened.
