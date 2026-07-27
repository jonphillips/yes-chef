# Effort: Grocery rapid add — a persistent Add Item field, plus Accept All on review (2026-07-26)

**Type:** New authoring affordance + one latent-bug fix + one perf guard + one review-chrome slice. App layer
and one shared-component extraction; **no schema, no Core model change.** One dispatch, five slices.

**Why Slice E rides here:** it is unrelated to groceries and cohesive with nothing else — it is a small,
self-contained chrome change from the same dogfood pass, and giving it its own dispatch costs more in
ceremony than it costs to implement. It touches no file the other four slices touch.
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Ready to dispatch — all three confirms closed with Jon 2026-07-26 (see Decided).**

From Jon's 2026-07-26 dogfood pass: *"the ceremony of adding things to grocery list is annoying. What if there
was a persistent 'Add Item' field at the top that would just let me add one after another and would parse and
assign intelligently to area of store"* — plus the stale-sheet bug found in the same session, and the Paprika
reference shot (persistent `+ Add Item` row pinned above the aisle sections; fraction glyphs at the bottom).

**Read before starting:** [`fraction-input-accessory.md`](fraction-input-accessory.md) (the pill row this
reuses — it is `private` today, see Finding 4), [ADR-0035](../decisions/ADR-0035-grocery-store-area-grouping.md)
(store-area grouping and the on-device classifier), [ADR-0029](../decisions/ADR-0029-main-thread-write-and-fetch-cost.md)
(the writer-convoy disease Finding 3 is a fresh instance of), and — **for Slice E only** —
[ADR-0026](../decisions/ADR-0026-review-collection-sheet.md) (the universal review-collection sheet) plus
[ADR-0025](../decisions/ADR-0025-reader-comment-ingestion.md) (where the comment proposals come from). Then
`CURRENT_HANDOFF.md` Verification Pattern.

---

## The findings that shape this dispatch

**Two of them cut scope; one adds a slice that is easy to skip and would sink the feature.**

### Finding 1 — the stale-sheet bug, diagnosed

[`GroceryItemEditorView`](../../YesChefApp/GroceryViews.swift) seeds all five of its `@State` properties in
`init` via `State(initialValue:)`. That only takes effect the **first time SwiftUI creates storage for that
view identity**. Dismiss and re-present quickly — before the dismissal animation finishes — and SwiftUI hands
back the same state box with the previous text intact. That is exactly Jon's report: *"hit add to list quickly
enough, the old value is still there."* Not a race in the model; a view-identity/state-lifetime mismatch.

It also affects **Edit**, not just Add: the same view, the same seeding pattern.

### Finding 2 — deterministic area assignment is **already wired into the add path** (scope cut)

I planned a two-stage design: instant deterministic seed, then a deferred model sweep. Stage 1 already exists.
[`GroceryRepository.addCustomItem`](../../YesChefPackage/Sources/YesChefCore/GroceryCore.swift) line 241:

```swift
aisle: aisle?.nonEmptyGroceryText ?? GroceryStoreArea.seed(for: canonicalName)?.title,
```

`GroceryStoreArea.seed(for:)` does a canonical-name lookup with a head-noun fallback. **So the new field needs
no area logic at all** — it passes `aisle: nil` and the row lands in the right section immediately, offline,
with no model call. Do not add a second seeding path.

### Finding 3 — the deferred sweep is already wired too, and it is the perf risk (adds Slice C)

`categorizeUncachedItems()` **already fires after every custom-item add**
([`GroceryModels.swift:706`](../../YesChefApp/GroceryModels.swift)). Good — except look at what it does:

| Step | Cost |
|---|---|
| `GroceryStoreAreaCache.backfill` | `GroceryItem.fetchAll(db)` + per-row `upsert`, **inside `database.write`** |
| `$itemRows.load()` | full re-load |
| `uncategorizedCanonicalNames` | `GroceryItem.fetchAll(db)` again |
| `applyClassified` | `GroceryItem.fetchAll(db)` a third time + per-row `upsert` on the writer |
| `$itemRows.load()` | full re-load again |

Three whole-table scans, two write transactions and two full reloads — **per item added**. Today that's fine:
one add per sheet, one sheet per minute. The entire point of this effort is to turn that into ten adds in
twenty seconds, at which point it is [ADR-0029](../decisions/ADR-0029-main-thread-write-and-fetch-cost.md)'s
writer convoy again, in a new place, and the feature ships feeling *worse* than the sheet it replaced.

**This is the slice most likely to be skipped as "not part of the ask" and is the one that decides whether the
feature is good.** See Slice C.

### Finding 4 — the fraction pill row is `private`

`IngredientFractionPillRow` is `private struct` in
[`RecipeEditorView.swift:160`](../../YesChefApp/RecipeEditorView.swift). It must be **extracted**, not
reimplemented — a second copy of the glyph row is exactly the drift the fraction effort closed.

---

# DISPATCH — persistent add field (A–D) + review-sheet Accept All (E) — app layer; no schema, no Core model change

## SLICE A — the persistent Add Item field

**Placement — top** (Decided). Pinned above the aisle sections in `GroceryDetailView`, matching the Paprika
reference — a `safeAreaInset(edge: .top)` on the item list, reusing the `safeAreaInset` + `@FocusState` idiom
the fraction work already established. A leading `+` glyph and an "Add Item" prompt so it reads as an
affordance and not as a search box.

**Behavior — this is the whole feature, so it is spelled out:**

1. Return (`.onSubmit`) commits the line — **and so does a trailing add button** (Decided), which must be the
   same code path, not a second commit implementation.
2. The field **clears**.
3. Focus **stays** — after *both* commit paths, including the button tap. A button that dismisses the keyboard
   breaks the add-one-after-another loop this effort exists to create.
4. Empty or whitespace-only input is a **silent no-op**, not an error alert. The button is `.disabled` in that
   state; Return stays a no-op.

**Parsing.** Run the existing `IngredientParser.parse(text)` on the raw line — it returns
`(quantity, quantityText, unit, item, preparation)` and already handles mixed numbers and vulgar-fraction
glyphs. Map `item` → `title`, `quantityText` → `quantityText`, `unit` → `unit`. Pass **`aisle: nil`** so
Finding 2's seed lookup runs. Do not hand the whole raw line through as `title` — that is the current
behavior and it is why "2 cups chicken broth" would sort under *C* as one blob.

**`preparation` folds into `notes`** (Decided) — never dropped, per ADR-0040 lossless-or-loud. So
`2 cups chicken broth, chopped` yields a row whose `notes` reads `chopped`, not a row that quietly discards
it. When `preparation` is nil, `notes` stays nil rather than becoming an empty string.

**Reuse the existing commit path.** `saveCustomItemButtonTapped` already does list resolution, the write, and
the sweep kick — but it also sets `destination = nil`, which is sheet-lifecycle business the field has no part
in. Factor the body into a `addItemLine(_ text: String) -> Bool` the sheet path also calls, rather than
duplicating the write.

**Acceptance:** typing `2 cups chicken broth` + Return produces a row titled "chicken broth", quantity `2`,
unit `cups`, filed under **Canned and Jar Goods** with no network call; the field is empty and still focused;
five more items can be typed without touching anything else. The trailing add button produces an identical
row from an identical line and also leaves the field focused. `2 cups chicken broth, chopped` carries
`chopped` into `notes`.

## SLICE B — fraction pills on the add field

1. **Extract** `IngredientFractionPillRow` out of `RecipeEditorView.swift` into its own file as a shared
   internal component. **No behavior change to the recipe editor** — same glyph set
   (`ScaleFraction.ingredientInputCases`), same append-at-end insertion, same accessibility strings.
2. Present it beneath the add field, gated on the field's `@FocusState`.

Insertion stays **append-at-end** — SwiftUI `TextField` exposes no cursor position, the caveat the fraction
effort already recorded and accepted ("type `1 `, tap ½").

**Acceptance:** the recipe editor behaves exactly as before; the pills appear under the grocery add field only
while it is focused; `1 ½ tsp` typed via pills parses to quantity `1.5`, unit `tsp`.

## SLICE C — debounce the classification sweep (the one that must not be skipped)

Coalesce `categorizeUncachedItems()` behind a **single cancel-and-restart debounced Task** on
`GroceryLibraryModel` — a burst of adds schedules one sweep, ~1.5–2s after typing stops, not one per item.
This also feeds the classifier the batch it already wants (`GroceryCategorizationClient` chunks its input and
`GroceryCategorizationAttemptCache` dedupes attempts — both are wasted when it's called with one name at a
time).

Keep the existing `.task`-on-appear call ([`GroceryViews.swift:181`](../../YesChefApp/GroceryViews.swift)) as
an immediate (undebounced) pass; it is once per appearance and it is what catches items synced from another
device. The debounce applies to the **post-mutation** call sites only.

Do **not** attempt the deeper fix here (the three `fetchAll` scans, the per-row upserts). Those are a real
ADR-0029-shaped follow-up; debouncing removes the multiplier, which is what this effort creates.

**Acceptance:** adding ten items in rapid succession issues **one** classification pass, verifiable in the
ADR-0043 model-call record; the sweep still runs, and the last item added still gets an area.

## SLICE D — the stale-sheet fix

Move the editor's draft out of `@State`-seeded-in-`init` and into `GroceryLibraryModel`, carried by the
`.addCustomItem` / `.editItem` destination payload — state that belongs to the destination should live with
the destination, not in a view whose identity SwiftUI may reuse. (`.id()` on the sheet content forces fresh
identity and would also "work"; it treats the symptom and leaves the same trap for the next editor.)

Worth doing even though Slice A retires the sheet's hot path: **Edit has the identical bug**, and Edit is not
superseded by anything here.

**Acceptance:** dismiss the Add editor and immediately re-open it — every field is empty. Open Edit on item A,
dismiss, immediately open Edit on item B — item B's values are shown, not A's.

## SLICE E — Accept All on the review sheet, and Discard All demoted

From the same dogfood pass: *"with the NYTComments, I've already processed them in the outboard LLM, so
accepting each comment is tedious. Perhaps an Accept All button … Maybe 'Discard all' becomes a small looking
link near the 'Review' instruction … just trying to eliminate fat-finger problems."*

Today [`RecipeCollectionReviewSheet`](../../YesChefApp/RecipeCollectionReviewSheet.swift) has **Discard All in
the trailing toolbar slot and no accept-all counterpart** — the destructive action holds the most prominent
position, and the constructive one requires N round trips through a sheet.

**The change:**

1. **Accept All** takes the trailing toolbar slot as the confirmation action. It commits every item, then
   reports once (see point 4). No confirmation dialog — it is the constructive path and every item is
   individually undoable afterward.
2. **Discard All** demotes to a small plain-text button beside the "Review each assistant proposal before
   saving it." line, and **keeps** its existing `confirmationDialog`. Destructive stays confirmed; prominent
   and destructive stop being the same button.
3. Both stay `.disabled` while `activeCommittingItemID != nil`, as Discard All already is.

**The correctness trap — there are two different definitions of "unedited" in this one file, and Accept All
must honour both.** This is the [[editable-summary-unchanged-commit-path]] trap in a new place, and it fails
*silently*: Accept All would commit content that differs from what tapping through each item produces, with
no error.

| Presentation | What an untouched commit sends today | Where |
|---|---|---|
| `.sheet` | `item.editableText ?? item.summary` | `ChatApplyReviewSheet` seeds `draftText` this way (`RecipeChatWorkspace.swift:981`) |
| `.inline` | `item.summary`, unconditionally | `launchReview(for:)` |

So Accept All iterates and, **per item**, reproduces that item's own definition — it does not pick one and
apply it to both. Extract the per-presentation choice into a single computed property on the item
(`unmodifiedApprovedText`) and have `launchReview`, the sheet's seed, and Accept All all read it, so the two
definitions can never drift apart again.

**Two further constraints:**

- **Always the primary commit.** Call with `usingSecondaryCommit: false`. `secondaryCommit` is a deliberate
  *alternate destination* (per ADR-0023, overwrite vs. variation) and must never be chosen in bulk.
- **Sequential, not concurrent.** Commit items one at a time — `commitItem` sets a single
  `localCommittingItemID`, and the underlying writes serialize on the shared `DatabaseWriter` anyway
  ([ADR-0029](../decisions/ADR-0029-main-thread-write-and-fetch-cost.md)). If one item throws, stop, keep the
  remaining items in the list, and report what did commit — a partial Accept All must leave a truthful list
  behind, never silently drop the failures.

4. **`CollectionReviewCommitSummary` is single-valued** (`title` + `text`) and cannot describe a bulk commit.
   Extend it to carry a count so the confirmation can read "Saved 7 proposals" rather than echoing the last
   one's text and implying only it was saved.

**One interaction to check:** `reconcilePresentedItem()` auto-presents the review sheet when exactly one
`.sheet` item remains. Accept All draining the list down through 1 must not flash that sheet open on its way
to empty.

**Acceptance:** with 7 comment proposals staged, Accept All saves all 7 and the confirmation says so; each
saved item is byte-identical to what tapping Review → Save would have produced (assert this for both
presentations); Discard All is a small text button by the instruction line and still asks before discarding;
neither control is tappable mid-commit.

---

## Explicitly out of scope

- **A learned `canonicalName` → area cache.** Verified today:
  `GroceryStoreAreaCache.applyClassified` writes `aisle` onto **rows**, never into a name→area table, so the
  same ingredient in a new list is re-classified from scratch and a hand-fixed area teaches the app nothing
  ([[grocery-area-no-learned-cache]] still holds). Real gap, genuinely worth closing — a synced table is cheap
  ([[synced-table-cost-calibration]]) — but it needs its own decision about invalidation and about whether a
  hand-edit is a correction or a one-off, and it must not ride in on this effort's momentum
  ([[withdraw-not-defer-orphaned-schema]]).
- **Multi-line paste into the add field** (paste a whole ingredient list, get N rows). Tempting and adjacent,
  but that is prose→ingredients, which is [ADR-0036](../decisions/ADR-0036-promote-note-to-recipe.md)'s
  territory and wants its own thinking about the review gate.
- **The deeper sweep rewrite** (killing the three `fetchAll` scans and the per-row upserts). Named in Slice C;
  deliberately left as an ADR-0029-shaped follow-up.
- **Retiring the editor sheet.** It stays as the full-fidelity path — notes, explicit aisle override, and
  editing an existing row. The field becomes the primary *add* path, not the only one.

## Decided (Jon, 2026-07-26) — all confirms closed

- **`preparation` folds into `notes`.** Lossless-or-loud (ADR-0040) rather than the simpler silent drop.
  Folded into Slice A.
- **Field pins to the top**, above the aisle sections, per the Paprika reference. The bottom-above-keyboard
  alternative was considered for one-handed reach and rejected in favour of matching the reference.
- **A trailing add button ships alongside Return.** Both are the *same* commit path, and **both leave the
  field focused** — a button that resigns first responder would break the add-one-after-another loop that is
  the entire point of the effort. Disabled on empty input.
