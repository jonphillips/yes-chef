# Effort: Dogfood fixes — batch 3 (ingredient formatting · AI verbs · keep-awake)

**Type:** Editor/render fix + latent-capability surfacing + tiny platform affordance.
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/review).
**Status:** **SHIPPED** — all four slices implemented and architect-approved 2026-07-03
([PR #75](https://github.com/jonphillips/yes-chef/pull/75) → DONE-LOG). Kept here as the effort record;
non-blocking device-pass notes live in the DONE-LOG entry.
**Source:** Jon dogfooding, 2026-07-03 — "more control over ingredients list (HEADERS, spacing, not
everything bulleted)"; "AI buttons for Substitution / Chef It Up / Serve With, as a dropdown, each in
its own section not Notes"; "keep screen on while cooking".

**Do the slices in order, one PR.** Each is independent. Slices 1 & 3 both touch the ingredient
render path (`ingredientLineList`) — do 3 right after 1 so that work is fresh. Now four slices; if that
runs heavy, a clean split is 1+3 (ingredients) as one PR and 2+4 (verbs + keep-awake) as another —
confirm with Jon before splitting.

---

## SLICE 1 — Ingredient list honors headers / sections / spacing (the real-cooking friction)

**The model already supports everything Jon wants; the renderer discards it.**
`IngredientSection` (named subsection) and `IngredientLine.isHeader`
(`Models.swift:611` / `:640`) both exist and round-trip. But
[`RecipeDetailView.swift:393` `ingredientLineList`](../../YesChefApp/RecipeDetailView.swift) renders
**every** line as `"• \(scaledText)"` — ignoring `isHeader` and section `name`. So the substrate is
there; the affordance and the render are the gap. **No schema change.**

- **Render (`RecipeDetailView.swift`):**
  - An `isHeader` line renders as a **heading** (bold, no bullet), not a bulleted item.
  - Group by `IngredientSection`; render a non-empty section `name` as a subsection heading with
    spacing above (the "space between lines / between groups" ask).
  - Bulleted lines stay bulleted; headers and section titles do not. Keep scaling working
    (`IngredientScaler`) for non-header lines only.
- **Editor (`RecipeEditorView.swift` / `RecipeEditorModels.swift`):** expose the structure that
  already exists — let a line be toggled to a **header**, and let a section carry a **name**. Minimal,
  list-native controls (a per-line "make header" toggle + editable section title); don't build a
  rich-text editor.
- **Import (check, don't over-build):** confirm the parser tags obvious in-list headers as
  `isHeader` on the way in (e.g. "For the sauce"); if it already does, this is render+editor only.
  If it flattens them, a small tagging pass belongs here — but keep it conservative (a missed header
  is a bullet, not a crash).
- **Verify:** a recipe with sectioned ingredients (e.g. "For the cake" / "For the frosting") shows
  headings + grouping, not a flat bulleted wall; editor can add/toggle a header; round-trip + scaling
  intact.

## SLICE 2 — AI verbs: Chef It Up + collapse the verb buttons into a dropdown

The actionable-chat catalog ([`actionable-chat-make-ahead.md`](actionable-chat-make-ahead.md)) was
built for exactly this: each verb commits to **its own field/section, never Notes** — which is
already the invariant Jon is asking for. Two recipe-level verbs here; ingredient-scoped
**Substitution** is its own slice (Slice 3) because it commits per-line, not per-recipe.

- **Chef It Up (verb #2, already named "out of scope → after make-ahead proves"; make-ahead shipped).**
  Mirror the make-ahead slice end-to-end: additive nullable `Recipe.chefItUp: String?` (sync-safe, no
  schema-version dance — ADR-0010, [[sqlitedata-blob-cloudkit-asset]]), a structured extract client +
  pure `apply…` commit op, a catalog entry, and its **own "Chef It Up" section** in the detail view
  with field-clear undo. Same shape as make-ahead → low-risk copy of a proven pattern.
- **Serve With (verb #3 — resolved: an *accompaniment*, not a recipe).** Jon's constraint: the LLM
  emits "barely a recipe" (e.g. *"cilantro-scallion rice, stir butter in at the end"*) — so **do not**
  create a `Recipe` row or promote it to the library. Commit to its **own "Serve With" section on the
  parent recipe**, shaped as a small **list of `{ title, note }` accompaniment items** (not one blob) so
  each is independently removable. Additive-nullable structured field on `Recipe` (JSON-encoded list is
  fine; sync-safe). Render as its own section; each item removable = undo. **Escape hatch (do NOT build
  now, just don't foreclose):** a later "promote this accompaniment → real recipe" action — which is why
  items carry identity now (harvest-now/converge-later, cf. [[galavant-capture-engine-reuse]]). The
  structured *menu-planning cards* axis remains separate and later.
- **Dropdown:** the verbs render today as a vertical stack of bordered buttons
  ([`RecipeChatWorkspace.swift:268`](../../YesChefApp/RecipeChatWorkspace.swift)). At 2+ verbs, collapse
  them into a single `Menu` ("Apply…") so the panel doesn't grow a button per verb. Low-stakes UI.
- **Verify:** on a recipe, chat → "Apply… → Chef It Up" / "→ Serve With" each write to their own
  section, sync like any field, clear as undo; no chat turn writes on its own.

## SLICE 3 — Ingredient Substitution (per-line, reveal-on-tap)

The odd-shaped verb, now resolved (Jon, 2026-07-03): it is **ingredient-scoped, not
conversation-scoped**, and recorded on the line so the swap survives (Jon's real case: `1 Tbsp masa
harina` → *"1 tsp flour + 2 tsp fine cornmeal"*). Shares the Slice 1 ingredient-render path — do it
after Slice 1.

- **Schema:** add `public var substitution: String?` to `IngredientLine` (`Models.swift:626`) + init.
  Additive nullable TEXT column on `ingredient_lines` in `Schema.swift` — sync-safe (UUID PKs, no new
  unique index, no reserved name; [[sqlitedata-blob-cloudkit-asset]]).
- **Render (reveal-on-tap — the scannability requirement):** a line with a substitution shows normally
  plus a **subtle indicator** (small swap glyph, e.g. `arrow.triangle.2.circlepath`); **tapping reveals**
  the sub text inline (disclosure). Default collapsed so the list stays scannable — this is Jon's
  explicit ask, not a nicety.
- **Scaling caveat (decide with Jon):** the sub text is freeform prose tied to the line's stated amount,
  so it does **not** auto-scale with the multiplier. Default: show as-is. Alternative if Jon prefers:
  hide the reveal when `scaleFactor != 1` so a stale "2 tsp cornmeal" can't mislead a doubled batch.
- **Verb (ingredient-scoped):** entry is **from the ingredient line** ("Find a substitute"), not the
  conversation. The extract client gets *that ingredient + recipe context*, proposes a sub; the tap
  commits to `line.substitution` (model proposes, tap writes — same invariant, subject = the
  `IngredientLine`). This is the first non-recipe-level subject; keep `RecipeChatContext`/catalog
  general enough to carry it (cf. [[chat-verb-commit-shapes]]).
- **Manual path:** the editor can set/edit/clear a substitution on a line directly (recording is the
  goal; AI is one way to fill it). Clear = undo.
- **Verify:** on a line, set a sub (via AI and manually); list stays scannable with an indicator; tap
  reveals; round-trip + sync intact; clearing removes it.

## SLICE 4 — Keep the screen awake while cooking

- Set `UIApplication.shared.isIdleTimerDisabled = true` **scoped to the cook/reader presentation
  only** (full-screen recipe / cooking workspace), and restore it (`false`) on dismiss and on
  `scenePhase` background so it never leaks into normal browsing. Prefer setting it from the reader
  view's lifecycle rather than a global toggle.
- **Verify:** open a recipe in cook/full-screen, leave it idle past the auto-lock interval → screen
  stays on; leave the reader → auto-lock returns.

---

## Verification

Per `CURRENT_HANDOFF.md`: `xcodegen generate` after adding files; `swift build` the package for the
logic (Chef It Up client/commit tests); build `YesChef` once for `iPad Pro 13-inch (M5) (16GB)` with
`-skipMacroValidation`; `scripts/check-drift.sh`. `swiftui-specialist` checkpoint on the ingredient
render + the dropdown. Jon does the device UI pass. FoundationModels-linked tests can't run under
`swift test` here — `swift build` the Chef It Up extract/commit (parser is the tested default).
