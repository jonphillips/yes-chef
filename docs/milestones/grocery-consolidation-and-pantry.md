# Grocery consolidation + pantry thresholds (the "don't make me think about salt" milestone)

*Build order for Codex. Architect/editor-in-chief: this doc is the contract; the strategic
arc is in [../implementation-plan.md](../implementation-plan.md) (**Phase E — grocery polish**,
where this is scheduled), the product boundaries in
[../FUTURE_INTELLIGENCE_AND_PLANNING.md](../FUTURE_INTELLIGENCE_AND_PLANNING.md) (§7.5
deterministic core, §13 list math, §14 pantry — **read these first; they pre-settle the
hard boundary**), and the house rules in `/Users/jon/code/jon-platform/docs/ios/`. Where this
doc and those conflict, stop and flag it — don't silently diverge.*

*Authored ahead of schedule (2026-06-29) on purpose: the design was settled with Jon while the
thinking was fresh. It is **not** the next milestone — it lands in Phase E, after the sync gate.
Do not start building it before then without Jon's go.*

## The milestone in one sentence

Make the grocery list **trustworthy about the pantry** — Jon never sees kosher salt or other
things he always has, but a recipe that demands *a lot* of a finite staple (a cup of soy sauce)
surfaces for review instead of being silently hidden — by replacing the brittle one-off string
matching with **one canonical ingredient key**, a **same-dimension unit compare**, and a
**per-pantry-item threshold**, all computed as **deterministic list math** with **no blocking
dialogs**.

## Why this milestone (and why it's deterministic, not "AI")

The grocery/pantry subsystem already exists (built solo, pre-architect: `GroceryCore.swift`,
`GroceryPantryAssumptions.swift`, the selection sheet). It works, but it leans on **exact
normalized-string equality with hand-coded escape hatches** — the literal `switch` mapping
`anchovy fillets → anchovies` in [canonicalGroceryItemTitle](../../YesChefPackage/Sources/YesChefCore/GroceryCore.swift),
the hardcoded `doNotShop` and `defaultStaples` lists, and **three different normalizers**
(`groceryConsolidationKey`, `normalizedPantryText`, the parser tokenizer) that don't share a
key and can disagree. Every new collision — scallion/green onion, plurals, "extra-virgin" vs
"olive oil" — needs another hand-coded case, in two places. That is the brittleness this
milestone retires.

The temptation is to throw a model at it. **Resist it on the merge path.** §7.5 already settled
this: *shopping-list combining and pantry suppression are deterministic list math, not AI.* The
split this milestone honors:

- **Intelligence at ingest, determinism at merge.** The on-device model (when it lands; §7.4)
  normalizes each ingredient line **once** at capture into a cached canonical form. The grocery
  engine then joins on that cached key with pure functions — testable, offline, reproducible. No
  model call ever runs on the consolidation or suppression path.
- **The threshold decision is arithmetic, not judgment.** "Does the total soy sauce across this
  shop exceed ½ cup?" is a same-dimension comparison, not world knowledge. It belongs in the
  pure core.

So this milestone adds **zero** real-time model calls. It makes the *deterministic* layer good
enough that the one-offs disappear.

## The boundary this milestone must not cross (settled with Jon, 2026-06-29)

§14 draws a hard line: **pantry quantity tracking is not a feature goal; the pantry must not
become inventory management.** A per-item threshold walks right up to that line, so the
distinction is load-bearing and must be stated in code and tests:

- **A threshold is a *static rule*.** "Remind me if a shop needs more than ½ cup of soy sauce."
  Set once, never changes as Jon cooks. He is describing *how much is a lot for this item* — not
  *how much he currently has*.
- **Inventory is a *running balance*** that decrements as you cook. **This milestone must never
  add depletion, on-hand counts, or any value that changes when a recipe is cooked or an item is
  purchased.** Write this as an explicit non-goal so nobody "helpfully" adds it later.

If a future idea needs a decrementing count, it is a *different* feature with its own ADR — not
a quiet extension of this one.

## Definition of done

A reviewer can, in the running app:

1. **Never see a true staple.** Add a recipe with `2 tbsp olive oil` and `1 tsp kosher salt`;
   neither appears on the grocery list at all (suppressed, not shown). They are reviewable in an
   **"Assumed in pantry"** section, collapsed/quiet, with one-tap add-back — never in the
   buy-these rows, never in "Purchased."
2. **Be reminded on a big ask.** A pantry item with a threshold (soy sauce, ½ cup) is suppressed
   when the **consolidated total** across the list is ≤ ½ cup, but when three recipes push the
   total over ½ cup it surfaces in a visibly-promoted **"You may need more — soy sauce (¾ cup
   total)"** review row. **No modal interrupts the add.**
3. **Cross-recipe totals drive it.** Two recipes each calling for 3 tbsp soy sauce (each under
   threshold) together exceed it and surface — proving the check runs **after consolidation over
   the whole list**, not per-recipe at add time.
4. **Learn nothing it can't compute.** A new pantry item defaults to **unlimited / never show**.
   An item whose recipe quantity can't be compared to its threshold (no parsed quantity, or a
   unit in a different dimension) **fails safe to surfacing** for review, never silently hidden.
5. **Consolidate semantically, within reason.** `anchovy fillets` and `anchovies` merge into one
   row with no code change for that specific pair (canonical key, not a `switch`); `2 tbsp` +
   `1 tbsp` = `3 tbsp`; `8 oz` + `1 lb` merges via same-dimension conversion; genuinely
   non-comparable units stay as separate rows (preserve over interpret).

Invariants at merge:

- `swift test --package-path YesChefPackage` green; suppression, threshold, unit-compare, and
  canonical-key behavior each covered by pure-core tests with **no UI and no model**.
- The **one canonical key** is the *only* normalizer; `groceryConsolidationKey`,
  `normalizedPantryText`, and the parser's ad-hoc folding are unified or deleted, not left to
  drift apart.
- **No depletion/inventory** field exists anywhere. The threshold is static.
- `isPurchased` is **not** reused for pantry suppression — "assumed in pantry" is a distinct,
  derived state, never written into the purchased flag (or "Clear Purchased" would delete things
  Jon never bought).
- Pantry suppression and threshold flagging are a **pure function** of `(consolidated list ×
  pantry policies)` — recomputed, not stored mutable state.

## In scope

- A **canonical ingredient key**: one normalization function, populated by the parser today and
  by the on-device model later (same column either way), reused by both consolidation and pantry
  matching.
- A small **deterministic override/alias table** replacing the `anchovy` `switch` (data, not
  code branches) — also the home for the old `doNotShop` staples.
- A **same-dimension unit-compare/merge** layer: convert within a known dimension (volume,
  weight, count) when both sides are known units; leave unknown/mixed units as separate rows.
- **Pantry policy** on `PantryItem`: an `unlimited` flag (default true) + an optional
  `threshold` (quantity + unit). One knob; policy falls out of the number.
- A pure **`PantrySuppression`** function over the consolidated list + pantry policies →
  `{ shown, assumedInPantry, needsReview }`.
- The grocery-list **"Assumed in pantry" review section** (quiet) + **promoted over-threshold
  rows**; one-tap add-back. **No blocking dialog.**
- Migrating the existing exact-match staple behavior onto the new key (no regression in what's
  hidden today).

## Out of scope — with destinations

| Deferred | Goes to | Why not now |
|---|---|---|
| **On-device model normalization at ingest** | the photo/LLM capture milestone (§7.4, M2 "Out of scope") | This milestone makes the *parser* populate the canonical key deterministically; the model swaps in behind the same column later, no engine change |
| **Depletion / on-hand quantity / inventory** | nowhere (explicit non-goal, §14) | Crosses the settled boundary; would need its own ADR and a different product stance |
| **Full unit normalization for display/scaling** (perfect conversions everywhere) | Phase E scaling work | The compare layer here is bounded to "is the total over the threshold" + same-unit merge; it need not render perfect quantities |
| **Aisle/store-section inference** | later grocery polish | Independent concern; canonical key is the prerequisite, not this milestone's job |
| **Per-recipe (vs per-shop) threshold mode** | revisit only if Jon wants it | Decided: threshold is evaluated on the **consolidated shop total** — that's the "do I have enough" question |

## Architecture & module layout

Everything new is **pure `YesChefCore`** except the two review surfaces.

```
YesChefCore/
  CanonicalIngredient.swift     # the one normalization fn + the alias/override table
  Measure.swift                 # dimension model + same-dimension compare/convert (bounded)
  PantryPolicy.swift            # unlimited flag + threshold (qty+unit) on PantryItem
  PantrySuppression.swift       # pure: (consolidated list × policies) → shown/assumed/review
  GroceryCore.swift             # canConsolidate + quantity merge re-pointed at the canonical key
YesChefApp/
  GroceryViews.swift            # "Assumed in pantry" section + promoted review rows (no dialog)
  GroceryModels.swift           # wire the suppression result into the list view model
```

The selection sheet's existing "Skipped Pantry Staples" section stays, re-pointed at the
canonical key; the **new** review surface is in the grocery list itself (post-consolidation),
because only the list knows the cross-recipe total.

## Data model changes

`PantryItem` gains:

- `isUnlimited: Bool` — default **true** (new items never show; see Decision #1).
- `thresholdQuantity: Double?` + `thresholdUnit: String?` — the static "a lot" line; both nil
  when `isUnlimited` or when the item is "always confirm" (threshold 0).

`IngredientLine` / `GroceryItem` gain a cached **`canonicalName: String?`** (the join key),
populated at parse/generation time. Migration-aware — backfill from existing rows using the new
normalizer so nothing already hidden becomes visible. **Coordinate the schema migration with the
sync milestone** (this lands in Phase E, after sync — confirm the CloudKit-zone implications in
the PR, don't assume).

## The slices (each is one PR into `main`)

`main` is protected — every slice is a branch + PR, green at merge. Tick the box in the PR that
completes it. Slices are ordered so each is independently shippable and testable.

- [ ] Slice 1 — One canonical key + alias/override table (dissolve the one-offs)
- [ ] Slice 2 — Same-dimension `Measure` compare/merge (bounded)
- [ ] Slice 3 — Pantry policy model (unlimited default + optional threshold), migration-aware
- [ ] Slice 4 — `PantrySuppression` pure function + grocery-list review section (no dialog)

### Slice 1 — One canonical key + alias/override table

Introduce `CanonicalIngredient.canonicalName(_:)` — the **single** normalizer (whitespace,
case/diacritic folding, light singularization, prep-adjective stripping) — and a **data** alias
table (`anchovy fillet/filet/… → anchovies`, the old `doNotShop` staples) replacing the
`switch`. Cache it as `canonicalName` on `IngredientLine`/`GroceryItem`. **Re-point**
`canConsolidate` and `isPantryStaple` at this one key; delete `groceryConsolidationKey` and
`normalizedPantryText` (or collapse them into the new fn). **Tests:** the anchovy pair merges
with no code branch; scallion/green-onion and a plural pair merge via the alias table; the two
old normalizers' existing behaviors are preserved; nothing hidden today becomes visible.
**Done when:** there is exactly one normalizer, the `switch` is gone, and consolidation +
pantry matching ask the same key.

### Slice 2 — Same-dimension `Measure` compare/merge

A bounded `Measure` model: known units mapped to a dimension (volume/weight/count) with
conversion factors. `merge` combines two quantities **only** when same-dimension and both units
known (`8 oz + 1 lb → 24 oz`); otherwise the rows stay separate. `compare(total, threshold)`
returns `.over / .underOrEqual / .incomparable`. **No guessing across dimensions; no inventing
factors.** **Tests:** within-dimension merges; cross-dimension and unknown-unit pairs report
incomparable / stay separate; the existing same-unit add still works. **Done when:** the engine
can answer "is this total over that threshold" and merge compatible units, and refuses anything
it can't do exactly.

### Slice 3 — Pantry policy model (unlimited default + threshold)

Add `isUnlimited` (default **true**), `thresholdQuantity`, `thresholdUnit` to `PantryItem` with
a **migration-aware** backfill (existing pantry items → `isUnlimited = true`, so current
suppression is unchanged). Editor UI: a per-item control — *Always have it (never show)* /
*Remind me if a recipe needs more than [qty][unit]* / *Always confirm*. **The threshold control
is only offered for measure-unit items (volume/weight); count-y items (garlic cloves) show only
unlimited-or-shop** (Decision #6 — a "½ clove" threshold is nonsense). **Tests:** migration
preserves current behavior; the three policy states round-trip; threshold 0 = always confirm; a
count-y item exposes no threshold field.
**Done when:** a pantry item carries a static policy, defaults to unlimited, and the migration
strands nothing. **Flag in the PR:** the schema change vs. the sync milestone's zone.

### Slice 4 — `PantrySuppression` + grocery-list review section

The payoff. A pure `PantrySuppression.evaluate(list:policies:)` over the **consolidated** list
returns `{ shown, assumedInPantry, needsReview }`: unlimited matches → `assumedInPantry`;
threshold matches with total over (or incomparable) → `needsReview`; threshold matches under →
`assumedInPantry`. Wire into `GroceryModels`/`GroceryViews`: a quiet **"Assumed in pantry"**
section with one-tap add-back, and **promoted "You may need more — X (total)"** rows. **No
blocking dialog anywhere.** `isPurchased` untouched. **Tests:** unlimited item never shown;
threshold under hidden, over surfaced; **cross-recipe total** over threshold surfaces though
each line is under; incomparable units surface (fail-safe); **add-back moves a row to `shown`
for this list only and leaves the pantry item's policy untouched** (Decision #7). **Done when:**
the Definition-of-done scenarios all pass, the suppression is a pure function, and nothing is a
modal.

## Constants register (pre-justified — jon-platform "constants need a rationale")

- **New-pantry-item default = `unlimited` (never show).** Decided with Jon (2026-06-29):
  optimistic default minimizes interruptions; the cost is the occasional missed big-ask, which
  Jon accepts and will correct per-item over time. The cautious alternative (threshold 0 /
  always-confirm by default) was rejected as too chatty for the common case.
- **Threshold evaluated on the consolidated *shop* total, not per recipe line.** The question is
  "do I have enough across this whole shop," which only the post-consolidation list can answer; a
  per-add dialog structurally can't see the cross-recipe total.
- **Incomparable units fail safe to *surfacing*.** Over-reminding is cheap; silently hiding a cup
  of a finite staple is the failure Jon actually cares about. Mirrors the codebase's "preserve
  over interpret."
- **`Measure` converts only within a known dimension with known units; never across.** No
  invented factors, no density assumptions (volume↔weight). Refuse and keep rows separate.
- **One canonical normalizer.** Two matchers asking different questions of the same data is a
  latent bug surface; consolidation and pantry matching share the key by construction.

## Decisions (confirmed with Jon, 2026-06-29)

1. **New pantry items default to unlimited / never show.** "I'm sure I'll learn my lesson the
   hard way once or twice, but that's better long term." Fewer interruptions wins; per-item
   correction is the teaching path.
2. **Dialog-free.** Paprika uses an intervening confirm dialog on add; Jon explicitly prefers
   **not** to. Surface via a reviewable list section instead — non-blocking, persistent,
   glanceable.
3. **Threshold is a static rule, never inventory.** No depletion, no on-hand count, ever (§14
   boundary). A decrementing count would be a separate feature + ADR.
4. **Threshold checked on the consolidated shop total** (not per recipe), so combined small asks
   that add up are caught.
5. **Intelligence at ingest, determinism at merge.** The model (later) only populates the cached
   canonical key; no model call on the consolidation/suppression path (§7.5).
6. **No threshold for count-y items.** A threshold is only offered for items whose canonical unit
   is a measure (volume/weight); count-y staples (garlic cloves) are **unlimited-or-shop** — the
   editor does not show a threshold control for them. Keeps the UI honest (a "½ clove" threshold
   is nonsense) and matches where thresholds are actually useful (liquids/bulk).
7. **Add-back is one-shot for the list.** Tapping add-back on an "assumed in pantry" row moves it
   to `shown` **for that list only**; it does not edit the pantry item. A *persistent* "actually
   shop this" is a deliberate edit to the item's policy, made in the pantry editor — not a
   side effect of one shopping trip.

## Working agreement

- Each slice: branch → PR → merge (`main` protected; self-merge per the collaboration protocol).
  Commits end with the Co-Authored-By trailer; PR bodies end with the Claude Code trailer.
- Tests with swift-testing + CustomDump; control date/uuid/db via `@Dependency`; the suppression
  and threshold functions are pure and tested without UI or a model.
- Surface every new constant, schema change, and the migration in the PR description — flag,
  don't bury. The pantry schema change vs. the sync zone is a **must-flag**.
- Blocked or spec looks wrong → write it in the PR, label `question-for-architect`; don't
  silently diverge. The **no-inventory** boundary is the one most likely to erode — guard it.
