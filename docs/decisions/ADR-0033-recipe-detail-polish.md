# ADR-0033 — Recipe-detail polish: metadata chips + servings-attached scaler

Status: **Accepted** — 2026-07-12 (architect sketch off a ChatGPT mockup Jon commissioned 2026-07-11;
scope + open questions settled with Jon 2026-07-12). View-layer only: **no schema, no model, no sync, no
LLM.** A *deliberately small* treatment pass on the recipe Reader that rejects the mockup's
magazine-redesign half outright. Binds the SF / no-idiom-drift posture of [[macos-longterm-target]]; sits
under the priority caution of [[post-browser-sync-vs-features-tension]].

> **Numbering note.** This ADR was first drafted 2026-07-11 as `ADR-0030-recipe-detail-polish.md` in the
> "Recipe Detail design discussion" commit but never landed on `main`; the `ADR-0030` number was
> meanwhile taken by *local-backup-and-restore*. Renumbered to **0033** (next free after 0032); the
> README index is corrected in the same slice.

## Context

Jon commissioned a mockup (ChatGPT) exploring "polish" on the recipe detail screen and reacted to it
himself: it reads as *magazine layout / screenshot porn* — a heavyweight serif display title eats the
vertical space the ingredients should own, and mixing a serif into the type ramp buys "designed" at the
cost of consistency with the rest of the app. His two keepers: **subtle button/metadata treatments** are
worth mining, and the **serving scaler should attach to the current servings amount** rather than living
as a toolbar button (he explicitly rejected the mockup's slider-over-a-range control).

**What sharpened this from polish into a fix (2026-07-12):** the toolbar scaler — *the only affordance to
scale a recipe* — **crashes the app when tapped.** The scaler button lives in
`ToolbarItemGroup(placement: .secondaryAction)`
([RecipeDetailView.swift:96](YesChefApp/RecipeDetailView.swift)) with a `.popover(isPresented:)` attached
directly to the `Button`. `.secondaryAction` collapses its items into an overflow "•••" **menu**; a
SwiftUI popover anchored to a `Button` that the framework has hoisted into a menu has no valid
presentation anchor and traps. So scaling is currently **unreachable** — this ADR's D2 is the fix, not
just a relocation.

**The load-bearing observation from reading the actual view:** the shipping Reader is *already* most of
the way to the mockup's restrained good ideas, and none of the way toward its bad ones. What ships today
in [RecipeDetailView.swift](YesChefApp/RecipeDetailView.swift):

| Mockup element | Shipping reality | Verdict |
|---|---|---|
| Giant serif display title | `Text(recipe.title).font(.title.bold())` — SF, restrained | **Mockup regresses us. Reject.** |
| Serif/sans mix | Single SF ramp throughout | **Reject the mix.** |
| Accent numbered step badges | Already shipped — white number in an accent-filled `Circle()` | **Already done.** |
| Bordered "View Original" pill | Already `.buttonStyle(.bordered)` (`:378`) | **Already done.** |
| "Base Recipe" affordance | Ships as the variation `Picker(.menu)` (`:380`, ADR-0021) | **Already done, better.** |
| Metadata as filled/bordered chips | Plain secondary `Label`s in an HStack (`recipeStats`, `:450`) | **Real gap — adopt (D1).** |
| Scaler attached to servings | Scaler is a **toolbar button that crashes** (`:96`); summary *also* printed as static text over Ingredients (`:538`) | **Broken + smeared — the crux (D2).** |

So this ADR is not "redesign the Reader." It is two targeted moves plus a written rejection of the rest so
we don't re-litigate the serif next quarter.

## Decision

### D1 — Metadata becomes chips, staying on the SF ramp

`recipeStats` ([:450](YesChefApp/RecipeDetailView.swift)) today renders servings / time / rating /
difficulty as bare `.subheadline`/`.secondary` `Label`s. Give them the one treatment the mockup gets
right: a **capsule chip** — **hairline-bordered** (not tinted-fill), glyph + text, consistent corner
radius — reused across all four stats *and* the reference-placement / tags / category labels directly
below them (`:356`, `:365`–`:370`) so the block reads as one system. This is a `ViewModifier`
(`recipeChip`) or a small `Chip` view, applied in place; **no new strings, no model touch.** Keep SF, keep
`.secondary` weight; the chip is *shape*, not *typography*.

**Chip fill vs. border — decided: border.** Hairline border is the more SF-native, conservative choice and
harmonizes with the existing `.buttonStyle(.bordered)` "View Original" button (`:378`); tinted-fill is
punchier but louder. If a device pass says the block is too quiet, revisit fill — but ship border.

The `tags`/`category` rows currently render through `WrappingLabels` (`:965`), a single glyph followed by
a run of plain text labels. Chipping these means each *label* becomes its own capsule (glyph + one label),
wrapping — i.e. `WrappingLabels` gains the chip treatment per element. Keep the ≥44pt-agnostic sizing;
these are non-interactive.

**Explicitly rejected** (write it down): the serif display title, any second type family, the airy
full-bleed magazine spacing, and re-opening the AI-panel styling (a solved surface — ADR-0011/0024).
These make screenshots prettier and daily cooking worse.

### D2 — The scaler attaches to the servings stat; the toolbar button retires (the crux + the crash fix)

Today the same concept is smeared across three places, one of which is broken: the **base** servings live
in the `Serves …` stat (`recipeStats`, `:452`), the **multiplier** is a toolbar button opening a
`.popover` (`:96`–`:111`) **that crashes when tapped**, and the multiplier is *also* printed as static
secondary text in the Ingredients header (`:538`). Three representations, none of them the obvious tap
target, and the only interactive one traps.

Consolidate onto Jon's instinct: **the servings stat is the scaling control.** The `Serves …` chip (D1)
becomes a **`Button`** that shows the *scaled* servings (`scaledServingsSummary` already exists,
[RecipeModels.swift:898](YesChefApp/RecipeModels.swift)); tapping it presents the existing `ScalePanel`
([RecipeDetailView.swift:893](YesChefApp/RecipeDetailView.swift)) as a `.popover` **anchored to the chip
in the content view** (not the toolbar). Retire the toolbar scaler button *and* its crashing popover
(`:96`–`:111`), and delete the duplicate summary text over Ingredients (`:538`) — one control, where the
eye already looks for "how much does this make."

**This is a pure view rewire; it also removes the crash by construction.** The model API is untouched and
sufficient — `scaleButtonTapped()` (`:903`), `scaleSummary` (`:892`), `scaledServingsSummary` (`:898`),
`scaleFactor`, `destination.scaling`, and `ScalePanel(model:)` all already exist. We move the popover
anchor from a toolbar-menu item (invalid) to a content `Button` (valid), and delete a duplicate. We do not
rebuild scaling. The `.popover` on a normal in-body `Button` presents correctly on both iPad and iPhone,
which is what dissolves the trap.

Three sub-decisions, now settled:

- **D2a — tap-to-popover, not an inline stepper (DECIDED).** Jon's ask ("a button that displays the widget
  when tapped") confirms the lean: scaling here is a *multiplier* with a whole+fraction picker (½×, 1⅓×,
  2×; `ScalePanel`), which a `−`/`+` stepper mismatches. Tap the servings chip → the existing `ScalePanel`
  popover, anchored to the chip. Keeps the real control, honors "attached to servings," minimal churn.
- **D2b — No-`servingsText` fallback (DECIDED: keep it).** Scaling is gated on `!ingredientLines.isEmpty`,
  but the servings stat only renders `if let servingsText` (`:452`). A recipe with ingredients but no
  servings string would otherwise lose its scaler entirely. When `servingsText` is nil, render a minimal
  **"Scale" chip** in the same stat row (glyph + current `scaleSummary`) so the control is always present
  whenever scaling is possible. Same `Button` → same popover.
- **D2c — It scrolls away (DECIDED: accept it).** The toolbar scaler was always on screen; a
  content-anchored one scrolls off. Acceptable — scaling is a set-once-per-cook decision, and the scaled
  quantities stay visible in the ingredient list regardless. No sticky header. Flag for the device pass.

## Consequences / boundaries

- **No schema, no model, no sync, no LLM, no new copy.** Entirely `RecipeDetailView` + one small chip
  component. Lowest-risk class of change; the diff is legible.
- **Fixes a hard crash.** D2 is not merely cosmetic — it restores the *only* path to scaling a recipe.
- **Reuse over rebuild.** `ScalePanel` and the whole scale model stay as-is; D2 relocates an anchor and
  removes a duplicate. D1 is a modifier applied to existing `Label`s.
- **SF is ratified here.** Per [[macos-longterm-target]] the app layer must not drift into
  platform/idiom-specific chrome; committing to the system ramp (no serif, no second family) is the
  macOS-friendly call. The bordered chip is the *only* borrowed treatment.
- **Compact layout.** `recipeStats` lives inside a `ViewThatFits` (`:338`) that reflows to a VStack on
  narrow widths; chips must wrap there, and the tappable servings chip must keep a ≥44pt hit target.
  iPad-primary, iPhone-correct.
- **Priority honesty.** This is the "screenshot porn over the solvable sync gate" pull Jon flagged in
  [[post-browser-sync-vs-features-tension]] — but the sync gate is now **crossed**, and D2 fixes a crash,
  so the opportunity cost is gone. Ship it.

## Slice plan

Two slices in one dispatch (D1 and D2 are independent; land in order):

- **S1 — metadata chips (D1).** `recipeChip` modifier / `Chip` view; apply across `recipeStats` +
  reference-placement / tags / category labels (`WrappingLabels` gains per-element chips). Bordered. Pure
  presentation, additive, reversible.
- **S2 — servings-attached scaler + crash fix (D2).** Make the servings chip a `Button` that anchors the
  `ScalePanel` popover and shows scaled servings; **delete** the toolbar scaler button + its crashing
  popover (`:96`–`:111`) and the duplicate summary over Ingredients (`:538`); add the no-`servingsText`
  fallback "Scale" chip (D2b).

Lean verification ([[lean-verification-default]]): one app build for `iPad Pro 13-inch (M5)` +
`scripts/check-drift.sh`, no simulator install — **Jon does the device pass** (the two things only a device
confirms: the crash is gone / scaler opens from the chip on both iPad and iPhone; and the compact-wrap +
scrolls-away feel in the `ViewThatFits` branch).

## Related

- ADR-0021 (recipe variations — owns the "Base Recipe" picker the mockup reinvents as a button),
  ADR-0011/0024 (actionable-chat + editable review — AI panel styling, deliberately out of scope),
  ADR-0030 (local-backup-and-restore — unrelated; shares the original mis-assigned number).
- Memory: [[macos-longterm-target]], [[post-browser-sync-vs-features-tension]],
  [[lean-verification-default]], [[recipe-variations-overlay]].
