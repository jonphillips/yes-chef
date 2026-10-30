# Recipe relationships — parked notes

**Status:** Parked 2026-10-30, moved from `open-questions.md` as written (jon-platform ADR-0005 D14).
**Summary:** Suppression, variation, and collection are three primitives, not one. Open: split §22A into two entities or keep one, with list multi-select as the shared prerequisite.

Restore the part you schedule to a brief in `docs/efforts/`, in the plan PR that schedules it.

## Recipe relationships — suppression vs. variation vs. collection

Design discussion 2026-06-30. The thesis: these are **three distinct primitives that
differ on *who does the managing***, and the tempting unification is the classic
premature-abstraction trap. This **challenges §22A `RecipeFamily`** in
[DATA_MODEL.md](../../DATA_MODEL.md), which currently bundles the first two into one entity
(an optional `preferredRecipeID` + a role-discriminated `RecipeFamilyMember` join).

1. **Suppression / preferred-canonical** — *rivals* (substitutes): the "one true
   chocolate-chip cookie" with the also-rans hidden but kept. **Asymmetric**: one real
   winner that lives in the main library, losers suppressed yet available for
   comparison. Parent **is a real recipe**. Managed: *you, once* (crown the winner).
2. **Variation cluster** — *siblings* (complements) on a shared base: Cook's Illustrated
   "Sugar Snap Peas with {almond+orange / pine-nut+lemon / sesame+ginger}". **Symmetric**:
   all members stay visible, **no winner**. Membership asserted **manually** (multi-select
   → "group as variations") — precise, never auto-derived, so no false clusters across
   2,115 recipes. Parent is a **synthetic display header, NOT a real recipe and NOT a
   `preferredRecipeID`** (don't mint a phantom recipe / pollute the count). Label is
   **LLM-proposed** (the *shared theme* — ingredient **or** technique **or** form, kept
   general), human-overridable, cached once, never re-derived on render. Grouping is
   rendered **at display time** (tall parent row + smaller child links). Managed:
   *nobody ongoing* — the list draws it.
3. **Curated collection** — hand-authored, ordered, sectioned editorial index
   ([ADR-0008](../../decisions/ADR-0008-curated-collections.md)). Managed: *you, ongoing*.

- **Position: don't unify suppression and variation by default.** They differ in
  cardinality (asymmetric vs. symmetric), parent semantics (real winner vs. synthetic
  header), and lifecycle (crown a winner vs. curate a peer family). §22A's role-enum +
  `preferredRecipeID` shape fits suppression but mis-fits variation. Let whichever ships
  first stand alone; only unify if the second *proves* shared structure. The tell that
  they're secretly one concept: wanting the variation parent to be "the best of the
  three" — that's primacy, i.e. suppression leaking back in.
- **Open — concrete model decision:** split §22A into two entities, or keep one entity
  with two display policies (collapse-to-preferred vs. expand-as-cluster)? Defer until
  the first of the two ships.
- **Shared prerequisite — multi-select in the recipe list.** The list is **single-select
  today** ([RecipeLibraryView.swift:728](../../../YesChefApp/RecipeLibraryView.swift)
  `List(selection: $model.selectedRecipeID)`). Both suppression (select the losers) and
  variation (select the siblings) need batch selection, as do batch tag/categorize/trash.
  **Build it early and separately**, ahead of and independent from either relationship
  feature. Not in the current milestone arc; sequencing TBD.
- **Sync-safe — these impose zero constraint on doing iCloud first (2026-06-30).** Every
  primitive here is *purely additive*: new tables (family / cluster header / membership
  joins) + at most a nullable column, all keyed on the existing `recipes.id` UUID. None
  touch an existing synced column, recipe identity, or primary key — and CloudKit's
  append-only schema only punishes *destructive* changes (delete/rename/retype/re-key),
  not new record types or nullable fields. So sync can ship first deploying today's
  schema, and RecipeFamily/clusters arrive later as a clean additive migration. The
  synthetic-header decision helps here: the variation parent isn't a recipe, so it can't
  perturb synced recipe records at all. **This is independent of the import-before-sync
  gate** — that gate is about import *trustworthiness*, not relationship modeling.
