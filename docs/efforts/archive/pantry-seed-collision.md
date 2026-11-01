# Effort — Pantry starters stop colliding across devices

Status: Ready
Summary: A fresh install no longer seeds pantry rows with positional fixed IDs that overwrite another device's pantry in iCloud; starter staples are added only on request, with IDs derived from each staple's canonical name.

No schema change, no migration, no sync-model change. Found 2026-10-31 while auditing the iPad's backup after a
Debug install.

## What happened

At launch, `YesChefApp` calls `seedPantryItemsIfNeeded` ([SampleData.swift](../../../YesChefPackage/Sources/YesChefCore/SampleData.swift)).
When the local pantry is empty it adds `GroceryPantryAssumptions.defaultStaples` with IDs from
`SampleUUIDSequence(start: 90_000)`, one ID per title **actually inserted**. `PantryRepository.addItems` skips
titles whose canonical name is already present ("freshly ground black pepper" and "ground black pepper" are
both `black pepper`), so the IDs are positions in a filtered list, and the filter has changed since the iPad
first seeded in July.

The iPhone's fresh TestFlight install (PROD-CUTOVER Step 11) had an empty pantry before sync, so it seeded. Its
list was three titles shorter, so from `…090008` on, every ID carried a different title than the iPad's row with
the same ID. Same IDs, newer write: the iPhone's titles replaced the iPad's in Production. Result in Production
today: "freshly ground black pepper", "ground black pepper" and "pepper" are gone (harmless, since each is the
canonical `black pepper` row that's still there), and "vegetable oil", "water" and "white pepper" each appear
twice. Every future fresh install would do the same thing again. `seedSampleDataIfNeeded` in the same file
already explains this exact collision and refuses to seed a live store; the pantry seed never got that guard.

## Changes

1. **No automatic pantry seed in the live app.** Remove the `seedPantryItemsIfNeeded` call from
   `YesChefApp.init` and delete the function. A live store's pantry starts empty until the cook asks for
   starters. Previews and tests that relied on the seed call a test helper instead.
2. **Retire the legacy UserDefaults pantry import.** It only fed that seed (`GroceryPantryStorage.storageKey` read
   in `YesChefApp.swift`). Both devices migrated long ago. Delete the read and `GroceryPantryStorage` if nothing
   else uses it.
3. **Starter staples get IDs from their canonical name.** Add
   `DeterministicID.pantryStaple(canonicalName:)` (UUIDv5, same namespace and pattern as `recipeCategory`, name
   `"pantryStaple:<canonicalName>"`). `PantryRepository.resetToDefaults` uses it for every default staple instead
   of the injected `uuid`. Two devices that both add starters now produce the **same** row for the same staple,
   so they converge instead of overwriting each other. User-added pantry items keep random IDs.
4. **The empty pantry offers the starters.** The `No Pantry Items` empty state
   (`GroceryViews.swift`, ~557) gets an **Add common staples** button that calls the same path as the existing
   reset action. The existing **Reset** action stays as it is, apart from change 3.

Existing rows aren't touched. The `…0900xx` IDs already in Production stay as ordinary rows; Jon removes the
three duplicates by hand (below).

## Done when

- Core tests: `pantryStaple` IDs are stable for a canonical name and differ across names; `resetToDefaults` run
  twice in two separate databases yields identical ID→title pairs; titles that share a canonical name produce
  one row; a user-added item still gets an injected random ID.
- A test that building the live app's dependencies on an empty store leaves `pantryItems` empty.
- `scripts/check-drift.sh`, the elevated generic iOS build, and `YesChefTests`, per `docs/verification.md`.
- The completing PR appends to `docs/device-passes.md`: *In the Pantry, delete the extra "vegetable oil",
  "water" and "white pepper" (either copy of each), and confirm on the other device that each now appears once.*
