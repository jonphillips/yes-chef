# ADR-0030 — Recipe-detail polish: metadata chips + servings-attached scaler

Status: **Proposed** — 2026-07-11 (architect sketch off a ChatGPT mockup Jon commissioned). View-layer
only: **no schema, no model, no sync, no LLM.** Scopes a *deliberately small* treatment pass on the
recipe Reader and rejects the mockup's magazine-redesign half outright. Binds the SF / no-idiom-drift
posture of [[macos-longterm-target]]; sits under the priority caution of
[[post-browser-sync-vs-features-tension]].

## Context

Jon commissioned a mockup (ChatGPT) exploring "polish" on the recipe detail screen and reacted to it
himself: it reads as *magazine layout / screenshot porn* — a heavyweight serif display title eats the
vertical space the ingredients should own, and mixing a serif into the type ramp buys "designed" at the
cost of consistency with the rest of the app. His two keepers: **subtle button/metadata treatments** are
worth mining, and the **serving scaler should attach to the current servings amount** rather than living
as a toolbar button (he explicitly rejected the mockup's slider-over-a-range control).

**The load-bearing observation from reading the actual view:** the shipping Reader is *already* most of
the way to the mockup's restrained good ideas, and none of the way toward its bad ones. Before proposing
work, here is what ships today in [RecipeDetailView.swift](YesChefApp/RecipeDetailView.swift):

| Mockup element | Shipping reality | Verdict |
|---|---|---|
| Giant serif display title | `Text(recipe.title).font(.title.bold())` — SF, restrained (`:300`) | **Mockup regresses us. Reject.** |
| Serif/sans mix | Single SF ramp throughout | **Reject the mix.** |
| Accent numbered step badges | Already shipped — white number in `Circle().fill(Color.accentColor)` (`:566`) | **Already done.** |
| Bordered "View Original" pill | Already `.buttonStyle(.bordered)` (`:369`) | **Already done.** |
| "Base Recipe" affordance | Ships as the variation `Picker(.menu)` (`:398`, ADR-0021) | **Already done, better.** |
| Metadata as filled/bordered chips | Plain secondary `Label`s in an HStack (`recipeStats`, `:441`) | **Real gap — adopt.** |
| Scaler attached to servings | Scaler is a **toolbar button** (`:76`); summary *also* printed as static text over Ingredients (`:526`) | **Real gap — the crux.** |

So this ADR is not "redesign the Reader." It is two targeted moves, and a written rejection of the rest so
we don't re-litigate the serif next quarter.

## Decision (proposed)

### D1 — Metadata becomes chips, staying on the SF ramp

`recipeStats` (`:441`) today renders servings / time / rating / difficulty as bare
`.subheadline`/`.secondary` `Label`s. Give them the one treatment the mockup gets right: a **capsule
chip** — bordered or tinted-fill, glyph + text, consistent corner radius — reused across all four stats
and the reference/tags/category `Label`s directly below them (`:346`–`:361`) so the block reads as one
system. This is a `ViewModifier` (`recipeChip`) or a small `Chip` view, applied in place; **no new
strings, no model touch.** Keep SF, keep `.secondary` weight; the chip is *shape*, not *typography*.

**Explicitly rejected** (write it down): the serif display title, any second type family, the airy
full-bleed magazine spacing, and re-opening the AI-panel styling (a solved surface — ADR-0011/0024).
These make screenshots prettier and daily cooking worse.

### D2 — The scaler attaches to the servings stat; the toolbar button retires (the crux)

Today the same concept is smeared across three places: the **base** servings live in the `Serves …` stat
(`recipeStats`, `:443`), the **multiplier** is a toolbar button opening a `.popover` (`:76`–`:87`), and
the multiplier is *also* printed as static secondary text in the Ingredients header (`:526`). Three
representations, none of them the obvious tap target.

Consolidate onto Jon's instinct: **the servings stat is the scaling control.** The `Serves …` chip
(D1) becomes tappable and shows the *scaled* servings (`scaledServingsSummary` already exists, `:869`);
tapping it presents the existing `ScalePanel` popover (`:840`). Retire the toolbar scaler button and the
duplicate summary text over Ingredients — one control, where the eye already looks for "how much does
this make."

**This is a pure view rewire.** The model API is untouched and sufficient: `scaleButtonTapped()`,
`scaleSummary`, `scaledServingsSummary`, `scaleFactor`, and `ScalePanel(model:)` all already exist
([RecipeModels.swift:803](YesChefApp/RecipeModels.swift)). We move the popover anchor and delete a
duplicate; we do not rebuild scaling.

Three sub-decisions this raises — my leans, for Jon's call:

- **D2a — Inline stepper, or keep the popover?** Jon's language ("attached to the current servings")
  hints at an inline `−`/`+` stepper on the chip. But scaling here isn't ±1 serving — it's a
  *multiplier* with a whole+fraction picker (½×, 1⅓×, 2×; `ScalePanel`, `:860`). A stepper mismatches
  that model. **Lean: tap the servings chip → the existing `ScalePanel` popover, anchored to the chip.**
  Keeps the real control, honors "attached to servings," minimal churn. Revisit an inline stepper only
  if dogfooding says the popover is too heavy for a quick 2×.
- **D2b — No-`servingsText` fallback.** Scaling is gated on `!ingredientLines.isEmpty` (`:74`), but the
  servings stat only renders `if let servingsText` (`:443`). A recipe with ingredients but no servings
  string would lose its scaler entirely if the control *only* lives on that chip. **Lean:** when
  `servingsText` is nil, fall back to a minimal "Scale" chip in the same stat row (glyph + current
  `scaleSummary`), so the control is always present when scaling is possible.
- **D2c — It scrolls away.** The toolbar scaler is always on screen; a content-anchored one scrolls off.
  Real, and acceptable — scaling is a set-once-per-cook decision, not a scrubbed-continuously one, and
  the scaled quantities stay visible in the ingredient list regardless. **Lean:** accept it; do not add a
  sticky header for this. Flag for the device pass.

## Consequences / boundaries

- **No schema, no model, no sync, no LLM, no new copy.** Entirely `RecipeDetailView` + one small chip
  component. Lowest-risk class of change; the diff is legible.
- **Reuse over rebuild.** `ScalePanel` and the whole scale model stay as-is; D2 relocates an anchor and
  removes a duplicate. D1 is a modifier applied to existing `Label`s.
- **SF is ratified here, not incidentally.** Per [[macos-longterm-target]] the app layer must not drift
  into platform/idiom-specific chrome; committing to the system ramp (no serif, no second family) is the
  macOS-friendly call too. The chip is the *only* borrowed treatment.
- **Compact layout.** `recipeStats` already lives inside a `ViewThatFits` (`:329`) that reflows to a
  VStack on narrow widths; chips must wrap there, and the tappable servings chip must keep a ≥44pt hit
  target. iPad-primary, iPhone-correct.
- **Priority honesty.** This is exactly the "screenshot porn over the solvable sync gate" pull Jon
  flagged in [[post-browser-sync-vs-features-tension]]. It's cheap and self-contained, so it carries
  little opportunity cost — but if sync/dogfood threads are open, it waits with zero design decay. Ship
  it in a lull, not ahead of the gate.

## Slice plan (proposed)

One slice, optionally two if Jon wants the chip landed and lived-with before rewiring the scaler:

- **S1 — metadata chips (D1).** `recipeChip` modifier / `Chip` view; apply across `recipeStats` +
  reference/tags/category labels. Pure presentation. Additive, reversible.
- **S2 — servings-attached scaler (D2).** Make the servings chip the `ScalePanel` anchor showing scaled
  servings; delete the toolbar scaler button (`:75`–`:88`) and the duplicate summary over Ingredients
  (`:526`); add the no-`servingsText` fallback chip (D2b). Settles D2a/D2b/D2c per the leans above unless
  Jon redirects.

Lean verification ([[lean-verification-default]]): one app build for `iPad Pro 13-inch (M5)` +
`scripts/check-drift.sh`, no simulator install — Jon does the device pass (the scrolls-away feel in D2c
and the compact-wrap in the `ViewThatFits` branch are the two things only a device confirms).

## Open questions for Jon

1. **D2a** — tap-to-popover (my lean) or inline stepper on the chip? The multiplier model argues against a
   stepper, but it's your "attached" instinct — your call.
2. **One slice or two?** Chips and scaler are independent; happy to land D1 alone first if you want to
   feel the chip before touching the scaler.
3. **Chip fill vs. border** — tinted-fill (mockup) or hairline-bordered (matches the existing
   `.bordered` View Original button)? Border is the more conservative, more SF-native choice; fill is
   punchier. Lean border for consistency with `:369`.

## Related

- ADR-0021 (recipe variations — owns the "Base Recipe" picker the mockup reinvents as a button),
  ADR-0011/0024 (actionable-chat + editable review — the AI panel styling, deliberately out of scope
  here), ADR-0004 (structured editor — the Reader's sibling surface).
- Memory: [[macos-longterm-target]], [[post-browser-sync-vs-features-tension]],
  [[lean-verification-default]], [[recipe-variations-overlay]].
