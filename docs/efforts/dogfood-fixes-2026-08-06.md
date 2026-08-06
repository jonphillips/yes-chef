# Effort: Dogfood fixes — 2026-08-06 (calendar compact layout, grocery UX, label proposer)

**Status: Designed — Jon-managed manual execution.** Not dispatched to Codex as a batch; Jon drives the
slices manually with Claude. Deliberately **kept out of `CURRENT_HANDOFF`** — this doc is the working
backlog and sequencing record. Individual slices, when taken, follow the normal PR + handoff-bump ritual.
**Summary:** Six dogfood observations from Jon's 2026-08-06 pass, triaged into three threads. **A —**
the Meal Calendar's compact (iPhone) Week view is a wide/iPad grid forced onto a phone: it overflows
horizontally, truncates titles to unreadable stacks, drags the day-agenda below it off the left edge,
**and** its cells are un-tappable-to-recipe because the grid never receives the recipe-nav callback (one
root cause, two symptoms). **B —** two cheap grocery UX wins: add-a-whole-day-to-groceries and a
success toast. **C —** label suggestions: capture-time tag/category editing (verbatim JSON-LD
passthrough, no massage) and the on-demand `LabelProposer` under-firing / mis-mapping on existing
recipes (protein floor checks only the first ingredient line; cuisine excluded from the floor; model
biased to pick a wrong *existing* label over a correct *new* one).
**Related:** [ADR-0026](../decisions/ADR-0026-review-collection-sheet.md) (review-collection sheet — the
capture-time edit surface for C1) · [ADR-0052](../decisions/ADR-0052-grocery-learned-area-table.md)
(learned-correction table shape — the durable answer for C2) ·
[tandoor-idea-harvest.md](tandoor-idea-harvest.md) (correction-rules generalization; **this feedback is
the dogfood trigger it names**) · [ADR-0049](../decisions/ADR-0049-unified-categories.md) /
[recipe-facets.md](recipe-facets.md) (the category/facet model `LabelProposer` classifies against) ·
[ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md) (the compact/regular shell that Thread A
lives inside). Concept links: [[llm-vs-determinism-surface-boundary]], [[personal-app-latency-tolerance]],
[[grocery-area-no-learned-cache]].
**Owner:** Jon (product + manual execution driver) · Claude (architect/diagnosis) · Codex (implementation
when a slice is dispatched).

---

## Source feedback (verbatim, 2026-08-06)

1. iPhone Meal calendar view is messed up (screenshot: compact **Week** view).
2. Meal Calendar — would be nice to add an entire day to a grocery list.
3. Adding items to grocery list — would be nice to have a toast for a successful add.
4. NYTimes is bringing in a bunch of categories and tags and I have no way to edit or remove in the
   capture process. It would be nice to massage at capture time.
5. Meal Calendar: I can't tap to view any recipe!
6. Our label suggester only pulled "Italian" out of "Spanish Style Garlic Shrimp"; "Spanish Pork Bites"
   pulled nothing. (Happens on the **existing-recipe** suggest button, *not* during capture.) Is there
   anything in `tandoor-idea-harvest` / ADR-0052 that helps? Other thoughts?

---

## Thread A — Meal Calendar compact Week view (items 1 + 5, one root cause)

**These are the same corner of code.** Highest-value fix in the batch: the calendar is both broken-looking
and dead-to-touch on the phone, and both trace to the Week grid being an unadapted wide-layout component.

### Root cause

`MealCalendarWeekGrid` builds a 7-column grid with a hard per-column minimum
([MealCalendarViews.swift:715-716](../../YesChefApp/MealCalendarViews.swift#L715)):

```swift
Array(repeating: GridItem(.flexible(minimum: 72), spacing: 8), count: 7)
```

7 × 72 + 6 × 8 = **~552pt minimum width**. iPhone portrait content width ≈ 390pt. `.flexible(minimum:)`
cannot shrink below 72, so the `LazyVGrid` overflows the screen. Observed in the screenshot:

- Only ~5 of 7 columns fit — **Mon clipped left, Sat/Sun off the right edge**.
- 72pt columns are too narrow for titles → "Gingery…" wraps to unreadable 3-char stacks.
- **The day-agenda block below is also clipped left** — a *secondary* symptom: the 552pt grid drives the
  whole ScrollView's content width to 552pt, so every sibling lays out in an over-wide canvas that spills
  past 390pt. The Month/Week/Day segmented control overflowing is the same story.

**Item 5 shares this code.** `MealCalendarWeekGrid(model:cellMinHeight:)` and
`MealCalendarMonthGrid(model:cellMinHeight:)` are constructed **without** the `onRecipeSelected` callback
that the day-agenda path receives ([MealCalendarViews.swift:285-287](../../YesChefApp/MealCalendarViews.swift#L285)).
The grid cells are un-tappable-to-recipe *by construction*.

### Fix approach

On **compact** width, replace the 7-across Week grid with a **vertical day-list** built from the same
agenda rows the day view already uses — those rows already carry `onRecipeSelected`, so this fixes item 1
(layout) and item 5 (tap-to-recipe) in one slice. Keep the grid for regular (iPad) width.

- **Month view is probably fine** — its grid is `.flexible(minimum: 36)` (~288pt, fits). Confirm, don't
  rebuild.
- **Verify Day view** taps through to a recipe too (it routes through the agenda view, so it likely does;
  confirm on device).
- Sanity-check the segmented control isn't independently over-wide once the grid stops poisoning the
  ScrollView width.

**Size:** medium. **Priority:** highest. **Slices:** likely one PR (compact Week → agenda list + callback
wiring). No schema, view layer only.

---

## Thread B — Grocery quick wins (items 2 + 3)

Two small, additive UX wins; good to batch into one slice.

### B1 — Add a whole day to the grocery list (item 2)

The Meal Calendar already has a hand-off source (`MealCalendarHandoffSource.swift`) and per-day rows. This
is "select all recipe rows for a day → existing add-to-grocery path," surfaced as a per-day action (fits
the per-day overflow menu established in the 2026-07-25 ferry pass). **Size:** small.

### B2 — Success toast on grocery add (item 3)

Pure feedback affordance. **Note there is no toast primitive today** — per memory, the only centralized
app treatments are `.attentionCard()` and the FormFields `Stacked*` fields. So this is "build one
lightweight, reusable toast, then call it from the grocery add path," not "drop in an existing component."
Worth doing as a shared treatment since it'll be reused well beyond grocery. **Size:** small (plus a
one-time primitive).

---

## Thread C — Label suggestions (items 4 + 6)

Two *different* mechanisms that both surface as "the tags are wrong/thin," so keep them separate.

### C1 — Massage categories/tags at capture time (item 4)

**This is the verbatim JSON-LD passthrough.** `RecipeJSONLDExtractor` takes the site's metadata straight
([lines 75-77](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/RecipeJSONLDExtractor.swift#L75)):
`recipeCategory → addCategory`, `recipeCuisine → addCuisine` (prefixed `Cuisine > …`), `keywords →
addTag`. `RecipeParseBuilder` only dedupes. NYT ships a firehose of keywords, and the cook has no
pre-commit edit step.

**Fix direction:** let the capture-review flow prune/rename categories & tags **before** commit. The
universal review-collection sheet ([ADR-0026](../decisions/ADR-0026-review-collection-sheet.md), effort
[adr-0026-review-collection-sheet.md](adr-0026-review-collection-sheet.md)) is the right host — this is a
consumer of that surface, not a new one. **Size:** medium. No new schema.

### C2 — `LabelProposer` under-fires / mis-maps on existing recipes (item 6)

The suggest-labels action runs a **union of a deterministic `floor()` + an on-device model call**
([LabelProposer.swift:235-241](../../YesChefPackage/Sources/YesChefCore/LabelProposer.swift#L235)).

**Framing correction:** the deterministic floor **never classifies Cuisine**. It only touches Protein
(matched against `ingredientLines.first`), Technique (title), and Dish Type (title)
([floor():358-370](../../YesChefPackage/Sources/YesChefCore/LabelProposer.swift#L358)). So "Italian" for
*Spanish Style Garlic Shrimp* came from the **on-device model**, not the deterministic parser. Two
distinct defects:

**Defect 1 — the model picks a wrong *existing* label over a correct *new* one.** The system prompt says
*"Prefer exact existing paths… Do not invent paths"* and ranks `newChild`/`namespace` as "expensive…
exceptional" ([instructions:261-263](../../YesChefPackage/Sources/YesChefCore/LabelProposer.swift#L261)).
"Spanish" isn't in the seed cuisine list (American/Chinese/French/Indian/Italian/Japanese/Korean/Mexican/
Thai/Vietnamese), so a small model reached for the nearest existing Mediterranean (Italian) instead of
proposing `newChild ["Cuisine","Spanish"]`. On-device is also the weakest tier for this "name the cuisine"
judgment.

**Defect 2 — the deterministic floor structurally under-fires** (why *Spanish Pork Bites* got nothing):
- **Protein only checks `ingredientLines.first`** — the first ingredient line is almost always oil / salt /
  an aromatic, not the headline protein. The detail path *does* hand it every non-header line
  ([RecipeFacetCoverage.swift:174-181](../../YesChefPackage/Sources/YesChefCore/RecipeFacetCoverage.swift#L174)),
  so scanning all lines (bounded) is a one-spot fix with outsized recall gain.
- **Cuisine is excluded from the floor by design** — even in-vocabulary cuisines ("Thai Green Curry" →
  Thai) depend entirely on the model. A whole-word title match against existing Cuisine values is cheap
  and safe.

**Does tandoor / ADR-0052 help? Yes — the target is the *floor*, not capture.** Tandoor's
`KEYWORD_ALIAS`/`FOOD_ALIAS` = a **cuisine gazetteer** (cuisine adjectives in titles → a Cuisine value,
matched deterministically), and ADR-0052's sticky corrections = when the cook accepts "Spanish" or fixes
Italian→Spanish, seed the gazetteer so future "Spanish …" titles get it deterministically (same win/lose
ordering as store-area learning). That is the correction-rules pattern with a **new target: the proposer's
deterministic vocabulary.** Per the tandoor doc's own guard, don't build the general rule-table subsystem
on harvest momentum — the cheap wins below need no ADR; the gazetteer/learned table is the second slice
and *this feedback is the trigger the doc names.*

**Fix ladder (do the cheap ones first — they'd have fixed both example recipes outright):**

| Fix | Cost | Needs ADR? |
|---|---|---|
| Protein floor scans all ingredient lines, not `.first` | tiny | no |
| Add Cuisine whole-word title match to the floor | small | no |
| Loosen the anti-`newChild` bias **for Cuisine** so it proposes "Spanish" not "Italian" | prompt tweak | no |
| Raise the tier for this user-tapped action (you tap and wait — [[personal-app-latency-tolerance]]) | tiny | no |
| Broaden the seed Cuisine gazetteer (genuinely thin) | small data | no |
| Cuisine-word alias table + learned corrections | med | yes — ADR-0052 sibling |

**Size:** the top four are near-free (candidate first slice); the gazetteer + learned-correction table is a
separate, ADR-gated slice.

---

## Suggested sequencing (Jon-driven)

1. **Thread A** — compact Week → agenda list + recipe-nav callback (fixes 1 + 5). Highest value.
2. **Thread C2 cheap ladder** — protein-all-lines, cuisine-in-floor, cuisine `newChild` bias, tier bump.
   Small, high-signal, no ADR.
3. **Thread B** — day→groceries + toast primitive.
4. **Thread C1** — capture-time tag/category edit via the ADR-0026 sheet.
5. **Thread C2 durable** — cuisine gazetteer + learned corrections (ADR-0052 sibling), only if the cheap
   ladder leaves a real gap. This is the graduation the tandoor harvest names.
