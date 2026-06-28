# Audit — `main` Conformance Re-baseline

Audit date: 2026-06-27. Auditor: Claude Code (architect).
Scope: current `main` (through `5ea1533`), focused on the feature areas the
executor built **solo, without milestone build orders** — grocery, menus, meal
calendar — plus confirmation that the 2026-06-16 Pass-1 P0/P1 fixes actually landed
in the code before that newer work was stacked on top.

Method: pattern-conformance review against the now-codified house rules
(`~/code/jon-platform/docs/ios/persistence-and-sync.md`, `swift-style.md`) and the
Yes Chef ADRs, with `swift test` to certify the suite. This is the
[implementation-plan.md](../implementation-plan.md) Phase-A first task; its findings
define what (if anything) the Phase-A "stabilize" milestone must contain.

## Verdict

**The foundation is clean. Build forward.** Every Pass-1 P0/P1 finding is resolved,
and the grocery / menu / meal-calendar subsystems — built with no build order to
hold them to it — independently conform to the house patterns. `swift test`:
**48 tests in 11 suites pass.** There is no architecture-debt milestone to run here;
the residual findings are small and correctly belong to milestones already gated
later (sync, Family Cookbook). This is a strong signal the executor absorbed the
ADRs and the Pass-1 corrections.

The practical consequence for the plan: **Phase A collapses from a milestone into a
short cleanup slice.** The next real milestone is Phase B (import hardening). See
"Implication for the plan" below.

## Pass-1 findings — all resolved

| Pass-1 finding | Status | Evidence |
|---|---|---|
| **P0-1** hand-pulled `database.read` in `.task` → `CancellationError` / staleness | ✅ fixed | Zero `database.read` in app/sources; `@Fetch`/`@FetchAll`/`@FetchOne`/`FetchKeyRequest` in all five feature models + `RecipeListRequest.swift`, `MenuCore`, `MealCalendarCore`, `GroceryCore` |
| **P0-2** destructive delete-all/reinsert save | ✅ fixed | `RecipeCore.deleteMissingRows(_:keeping:in:)` (`:749-787`) deletes only absent rows; survivors upserted. Regression test `savePreservesUnchangedChildIDsAndNonGeneralNotes` passes |
| **P1-1** logic in views, no feature models | ✅ fixed | All `*Models.swift` are `@Observable @MainActor`; **zero** `#sql`/`db.execute` in the app target — persistence lives in pure `*Repository` functions called via thin `database.write` closures |
| **P1-2** raw `.sheet`, no swift-navigation | ✅ fixed | `SwiftNavigation`/`SwiftUINavigation` dependency (`project.yml:12`); `@CasePathable` `Destination` enums in all five models; 23 item-based navigation sites |
| **P1-3** stringly-typed columns | ✅ fixed | `RecipeLibraryPlacement`, `RecipeDifficulty`, `MealPlanItemKind`, `MealPlanItemSlot`, `GroceryItemOrigin`, `ParseConfidence`, `RecipeNoteType`, `RecipePhotoKind`, `PhotoSource` — all real `: String, …, QueryBindable` enums (`Models.swift`). No stringly-typed finite domains found |
| **P1-4** lossy bespoke snapshot | ✅ fixed | `RecipeBundleCoding.RecipeBundle` is the one canonical codable, reused for `originalSnapshot` (`RecipeCore.swift:362`) **and** Paprika import (`PaprikaHTMLImport.makeRecipeBundle`) — snapshot = interchange format, as the house doc now requires |

## New subsystems — conformance confirmed

The grocery/menu/calendar code was written to the same patterns:

- **Repository core (A-1).** `GroceryRepository`, `MenuRepository`, the meal-calendar
  and category repositories are pure `static func …(in db: Database)`. Feature models
  call them; the app target holds no SQL.
- **CloudKit laws.** Law 1 (UUID PKs) ✅ every table `"id" TEXT PRIMARY KEY DEFAULT
  (uuid())`. Law 3 (no unique indexes beyond PK) ✅ none present.
- **Law 2 applied correctly where it counts.** `groceryItemSources` — the multi-origin
  provenance row — carries exactly **one** hard FK (`groceryItemID`, `ON DELETE
  CASCADE`) and models every other reference (`recipeID`, `ingredientLineID`,
  `mealPlanItemID`, `menuID`, `menuItemID`, `menuPlacementID`) as a **loose UUID
  column, not a SQL FK** (`Schema.swift:360-379`). That is the single-FK sharing rule
  applied deliberately, not by accident.
- **Coverage.** `GroceryTests` (1232 lines), `MenuTests`, `MealCalendarTests`,
  `CategoryRepositoryTests`, `GrocerySourceContributionTests` all green.

## Residual findings — small, and already gated to later milestones

None of these block forward work; each belongs to a milestone the plan already
sequences later.

1. **Dedup-on-read absent for name-unique entities** *(→ Phase C, sync).* Pass-1
   flagged this for `Tag`/`Category`; it now also spans `GroceryList`, `Menu`,
   `PantryItem` (find-or-create by name with no lowest-UUID dedup cleanup). Harmless
   pre-sync, required by CloudKit law 3 before the first zone write. Test with seeded
   duplicates in the sync milestone.

2. **`menuItems.recipeID` is a second hard FK** *(→ Phase 2, Family Cookbook
   sharing).* `menuItems` has `menuID` (CASCADE) **and** `recipeID` (SET NULL) as SQL
   FKs (`Schema.swift:291-293`). Fine for the private DB and plain private sync; but
   when a menu "rides a share" under CloudKit *sharing*, the second relationship must
   become a loose UUID (law 2). Loosen it as part of the sharing milestone, not now.

3. **Loose-UUID dangling-reference tolerance is untested** *(→ Phase B/C, cheap
   now).* Because `groceryItemSources` origins are loose UUIDs with no cascade,
   deleting a referenced recipe/menu/placement leaves a dangling origin the
   repository must tolerate on read. The source-removal feature implies it does;
   add explicit tests (delete a recipe that contributes to a grocery row; assert the
   row degrades gracefully) so the by-convention integrity is pinned.

4. **ADR-0004 residual: text-change churn** *(known, → future row-aware editor).* A
   line whose *content* changes still can't be identity-matched and will re-create
   its row. Acknowledged in ADR-0004; awaits a structured editor. No action now.

5. **`NavigationSplitView` unconditionally** *(P2, cosmetic).* Still not the
   size-class-driven tab-on-iPhone / split-on-iPad pattern the UI doc wants. Acceptable
   for now; track.

6. **Enum backing is uniformly `String`** *(judgment call, fine).* House guidance
   prefers `Int`-backed enums for compactness, `String` "only where the raw value is
   itself meaningful." For a recipe domain (`"dinner"`, `"makeAhead"`) the meaningful
   raw value is defensible and aids import/debugging. Not a finding; noted so it isn't
   re-raised.

## Doc gap (not a code finding)

- **Menus has no ADR and no requirements entry.** The subsystem is ratified product
  (next-gen Paprika), but it entered the codebase through solo work and is undocumented
  in `PRODUCT_BRIEF`/`REQUIREMENTS_MVP_ROADMAP`. It needs an ADR for the
  recipe → menu → menuItem → menuPlacement → calendar → groceryItemSource provenance
  model, plus a requirements entry. Author alongside the Phase-B/D docs.

## Implication for the plan

[implementation-plan.md](../implementation-plan.md) provisioned **Phase A
(stabilize)** as the next milestone on the assumption the foundation might be
carrying Pass-1 debt under the newer features. It is not. Recommendation:

- **Drop the standalone Phase-A stabilization milestone.** Fold its only "now" item
  — finding 3, the dangling-reference tests — into a small opening slice of the
  import milestone (or a one-PR cleanup).
- **Make Phase B (import hardening) the next milestone**, and author its build order
  next. Findings 1 and 2 stay correctly parked on the sync and sharing milestones.
- Update `implementation-plan.md` Phase A accordingly when the Phase-B build order
  lands.
