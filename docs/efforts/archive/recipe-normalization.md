# Recipe normalization ("normalize recipe") — parked notes

**Status:** Parked 2026-10-30, moved from `open-questions.md` as written (jon-platform ADR-0005 D14).
**Summary:** A one-tap normalize that strips manual instruction numbers (the all-caps de-cap is the declined P2). Unscoped; sequence it with ADR-0014.

Restore the part you schedule to a brief in `docs/efforts/`, in the plan PR that schedules it.

## Live — recipe normalization ("normalize recipe" function)

- **Unscoped.** Jon (dogfood 2026-07-04): a one-tap "normalize recipe" that de-caps old all-caps Milk Street
  imports and strips manual instruction numbers (we now auto-number). No natural existing effort home; parked
  here until scoped. **Sequence with [ADR-0014](../../decisions/ADR-0014-recipe-text-editing-model.md)** — both
  touch the same recipe text, and normalization's interaction with any future user styling must be decided
  together. Likely an LLM enrichment/one-tap action rather than a chat verb; classify before slicing.
- **Sized 2026-07-28 from a backup export — scope grows to *section names*; urgency does not.** Of **541**
  named `ingredientSections`, **284 are ALL CAPS** — the Milk Street de-cap case living in a column nobody
  had counted. Three distinct sub-cases, all **legacy, bounded, and not growing**:

  | Case | Size | Shape |
  |---|---|---|
  | ALL-CAPS section names | **283** (pre-2026) | de-cap, same as line text |
  | `GATHER YOUR INGREDIENTS` | **70 recipes** | **null the name** — see below |
  | Flour Bakery mega-recipe | **1 recipe** | hand fix / re-capture, not normalization |

  **`GATHER YOUR INGREDIENTS` is trivially safe to clear: in 69 of the 70 recipes it is the *only* section**,
  so the name groups nothing and nulling it changes no structure, moves no line, deletes no row. It is also a
  **deterministic** function of synced rows, so it is in the safe class under the migration rule above —
  though it wants to run as a user-triggered normalize action anyway, not a migration.

  ⚠️ **It is NOT a live capture defect — an earlier reading of this was wrong.** All 70 are
  **cooksillustrated / cookscountry / americastestkitchen**, dated **2019–2020**: Paprika-era legacy imports
  that predate YesChef's extractor. By era: **legacy 529 named / 283 all-caps and all the junk; YesChef-era
  (2026+) 12 named / 1 all-caps / zero junk.** Likewise `included in your kit` / `from home` are **not**
  meal-kit groupings — they are one 2020 import, *Flour Bakery Chocolate Chip Cookies*, where a whole
  cookbook page became one recipe with **33 sections and 254 ingredient lines**.
  **Nothing is accumulating, so this is a one-time chore whose cost does not rise with delay.**
  ✅ **Spot-check done — Jon captured an ATK page 2026-07-28 and it came through clean.** The current
  extractor does not reproduce the defect, so normalization is confirmed as a **one-time legacy pass** with
  no capture-boundary work attached.
