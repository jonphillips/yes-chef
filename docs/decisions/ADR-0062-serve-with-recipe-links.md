# ADR-0062 — A Serve With row can link to a recipe

> **One-line:** Each Serve With row stays free text and can also point at one recipe. A linked chip opens that recipe.
> Linking is the cook's act: the model never sees or sets a link. It adds one nullable, synced column.

Status: **Accepted** — 2026-11-04. Effort:
[`efforts/archive/serve-with-recipe-links.md`](../efforts/archive/serve-with-recipe-links.md).
Origin: Jon's 2026-11-04 dogfood pass: *"Serve with is kind of pointless because you can only enter Freeform text. There
should be some sort of recipe selector as well? What are we doing here?"* He chose optional links the same day.
Builds on: [ADR-0048](ADR-0048-playbook-edit-grain.md) (Serve With rows, provenance, regeneration keeps identity) ·
[ADR-0021 Amd 4](ADR-0021-recipe-variations.md) (related recipes as loose peer edges) ·
[ADR-0039](ADR-0039-playbook-column-thinking-vs-doing.md) (the capsule strip) ·
[ADR-0061](ADR-0061-one-recipe-handoff.md) (Serve With's hand-off) ·
[ADR-0056](ADR-0056-move-to-production-and-data-carry.md) (Production schema is additive-only).
Adjacent, unchanged: [ADR-0057](ADR-0057-prepared-components.md) (parked), where a component is something a dish
requires, not an accompaniment.

## Context

Serve With began as model output. ADR-0048 turned that blob into `recipeServeWith` rows (`title`, `note`, `sortOrder`,
`provenance`), and hand-typed Add arrived with the rows. The rows feed recipe chat and hand-off prompts as text.

Nothing connects a row to the library. A pairing you own a recipe for is a dead label, and following it means leaving
the recipe and searching. Related Recipes does link recipes, but it means "keep these together": its edges are
symmetric, and they hold no note and no free text. "Crusty bread" can't be one.

## Decisions

### D1 — One nullable soft reference on the row

`recipeServeWith` gains `linkedRecipeID TEXT`, nullable, with no foreign key. A second FK is what the
`recipeRelatedRecipes` migration ruled out for SQLiteData's CloudKit sharing model, and a soft reference can't park a
row behind a recipe that hasn't arrived yet. A row has at most one link, so a join table would add nothing.

### D2 — The title stays the cook's label

The row keeps `title` and `note`, and the chip shows `title`. Picking a recipe fills the title only if it's blank. It
never overwrites one, and renaming the recipe later doesn't change it. Someone who wrote "the cornbread" meant that.

### D3 — A link resolves when it's read

A chip behaves as linked only if its target exists and isn't archived. Otherwise it's a plain chip and opens the editor.
This has to happen on read, because sync can deliver a link before its target, or a target's delete after the link.

- **Archived target:** keep the link, so restoring the recipe brings it back. This matches `relatedRecipes(for:)`, which
  also hides archived recipes.
- **Permanent delete:** `permanentlyDelete` clears `linkedRecipeID` on rows pointing at the recipe, in the same
  transaction, and leaves their text. This is the same reason it already deletes related-recipe edges by hand, and
  stale ids are dead data.
- **Duplicate merge:** `recipeIsContentEmpty` treats a recipe that a Serve With row links to as not empty, as it does
  for related-recipe edges, so a merge can't discard a recipe something points at.

### D4 — A linked row survives regeneration

`replaceModelSuggestions` deletes unmatched `.model` rows, which would silently destroy a link the cook made. It now
leaves any linked row in place. `provenance` doesn't change when a row is linked, because it answers who authored the
row (ADR-0048 OQ2), not whether the cook has touched it. **Clear Serve With** still clears everything, behind its
existing confirmation. Cloning a recipe carries links.

### D5 — The model never sees or sets a link

`ServeWithItem`, `ServeWithSuggestion`, `ServeWithPlan`, chat context, hand-off prompts and the return contract don't
change. Suggestions stay text, and there's no matching of titles to recipes, which would be a heuristic guessing at a
link the cook can make in two taps.

### D6 — The chip navigates; the editor edits

- **Linked chip:** shows a link glyph, and a tap opens the recipe. Edit stays reachable from a context menu and an
  accessibility action, and from the row list behind the header's pencil. An unlinked chip works as it does today.
- **Item editor:** gains a Recipe section with **Link a Recipe**, or the linked recipe's title and **Remove Link**.
- **Picker:** the private `RelatedRecipePicker` is extracted and reused, with its scoped row read. It excludes the
  current recipe and recipes other rows on this recipe already link to. Archived recipes aren't offered.

### D7 — One-way

A link goes from the dish to its accompaniment. The target shows nothing in return. A "served with these" list on the
other side can be added later from the same column if dogfooding asks for it.

### D8 — The field reaches Production before the build does

This is a synced table, and a Production schema deploy is one-way. The app can't save the field until Production has
it, and `testflight`'s expected-fields gate blocks an upload until then. Before the first TestFlight build containing
this work, Jon creates the fields in Development, confirms the export differs only by those fields, and deploys. The
steps are held in [`device-passes.md`](../device-passes.md).

## Rejected

- **Drop hand-typed entry and leave linking to Related Recipes.** No schema, but the dead-label problem stays.
- **A `kind` on related-recipe edges.** Those edges are symmetric and have no note or free text, and rows would need a
  data migration into a worse fit.
- **Provenance flips to `.handAuthored` on link.** It would make regeneration simple by recording the wrong author.
- **The chip opens the editor, with an Open Recipe button inside.** Two taps to the thing the link is for.

## Consequences

- One more field in CloudKit Production, permanently.
- Existing rows are untouched: every row starts unlinked, and nothing needs backfilling.
- Linked rows are visually distinct, so the strip shows which pairings you can cook from here.
- An "add this pairing to the menu" action becomes possible. It isn't part of this decision.
