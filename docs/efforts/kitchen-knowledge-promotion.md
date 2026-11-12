# Effort — Kitchen knowledge reaches everyone

Status: Ready
Summary: The built-in aliases, store areas, Advance-trip keepers and default pantry staples move from Swift into one bundled JSON file. **Settings › Developer › Export What I've Taught** writes your name fixes, area corrections, confirmed model areas and trip switches to a file. `scripts/promote-knowledge` merges exports into the bundled file for a reviewed PR. A data pass then deletes your rows the new file makes redundant. No schema change.

Origin: Jon, 2026-11-12, as Wendy starts using the app. One dispatch, two PRs: this repo, plus a small
`jon-platform` change for the TestFlight warning (step 8). **No persistent model change:** the data file is a bundled
resource, not a database table.

Decisions: [ADR-0070](../decisions/ADR-0070-what-you-teach-reaches-everyone.md) (D1–D7). Read it first, then
[ADR-0069](../decisions/ADR-0069-ingredient-name-fixes.md) D2–D3 (base keys vs fixed keys) and
[ADR-0052](../decisions/ADR-0052-grocery-learned-area-table.md) D2–D3 (the area ladder).

## Where things are (architect, 2026-11-12, `origin/main` 91882c3)

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `CanonicalIngredient.swift`: `aliases` and `defaultPantryStaples`. The prep-word, form-word and irregular-singular
  lists are rules and stay in Swift.
- `GroceryStoreArea.swift`: `seedAreas` (around line 190, the "editable quality floor"). The area-name normalization
  dictionary above it (`"dairy": .dairy`…) is a rule and stays. `GroceryStoreArea.normalized(_:)` parses an area title,
  including custom ones.
- `GroceryTrip.swift`: `GroceryTripRule.keepers` and `defaultTrip`. `advanceAreas` is a rule and stays.
- `IngredientNameFix.swift`, `GroceryAreaAssignment.swift`, `GroceryTrip.swift` (`GroceryTripAssignment`): the three
  taught tables.
- `SeedCoverageReport.swift`: `swiftLiteralEntries` and `GroceryStoreArea.swiftLiteral`, the ADR-0037 export this
  replaces.
- `Schema.swift`: `YesChefDataPasses` (around line 1491), with `currentVersion` and the pass list.
- `Package.swift`: `YesChefCore` declares no resources yet; the test target shows the `resources:` shape.

**App (`YesChefApp/`)**
- `SettingsViews.swift`: the **Developer** section (`seedCoverageRow`, around line 382, shows the pane/NavigationLink
  pattern).
- `SeedCoverageView.swift`: the clipboard Swift-literal action (around line 64).
- `ChatAccessFolderClient.swift` and `jon-platform/packages/ChatAccessKit`: how the app resolves the
  `iCloud.com.jonphillips.yeschef` container. Backups already live in its `Documents/`.
- `GroceryViews.swift`: an existing `ShareLink` (around line 210).

## Build

1. **The data file (D3).** Add `YesChefCore/Resources/BuiltInKnowledge.json` as a bundled resource:
   `{ "version": 1, "aliases": {…}, "areas": {name: area title}, "trips": {name: "advance"|"fresh"},
   "keepers": […], "pantryStaples": […] }`. Generate it from the current Swift literals and delete them. `trips`
   starts empty. A `BuiltInKnowledge` type loads it once. If it fails to decode, report an issue and fall back to
   empty; a test guarantees the shipped file decodes.
2. **Read through it.** Aliases, seed areas, keepers and default staples read from `BuiltInKnowledge`. A `trips`
   entry is checked first in `GroceryTripRule.defaultTrip`, then the keeper rule. Saved switches still beat both, as
   now. Order everywhere: your rows, then the file, then the model (D4). **Behavior doesn't change:** before deleting
   the literals, add a test that the JSON equals them and run it. Remove that test along with the literals, and say
   in the PR that it passed. The existing alias, area and trip tests stay green with no edits.
3. **Export (D5, D6).** **Settings › Developer › Export What I've Taught** builds a JSON file:
   `{ "exportedAt", "variant": "production"|"dev", "nameFixes": [{from, to}],
   "areas": [{name, area, source}], "trips": [{name, trip}] }`. It includes every name fix, `.user` area rows,
   `.model` area rows with `reviewedAt` set, and every trip switch. Never pantry items. It writes the file to the
   container's `Documents/Knowledge/` (visible in the Files app and on the Mac) and offers a `ShareLink` for the same
   file. That's how Wendy sends hers. The screen shows how many rows of each kind the file holds.
4. **Retire the ADR-0037 Swift-literal export.** Remove the clipboard action, `swiftLiteralEntries` and `swiftLiteral`;
   export replaces them. The audit itself (browse, fix, confirm) stays.
5. **Merge script.** `scripts/promote-knowledge [-n] [export.json…]`, in Python 3 (as jon-platform's `closeout` uses).
   With no paths it reads every `*.json` directly in
   `~/Library/Mobile Documents/iCloud~com~jonphillips~yeschef/Documents/Knowledge/`. For each entry:
   - not in the file → add it;
   - same value → skip;
   - different value → the export wins, because it's a person correcting the built-in;
   - two exports disagree → the newer `exportedAt` wins.

   It normalizes names the way the app does, so keep normalization in one place: lowercase plus diacritic folding.
   Names in exports are already base keys or fixed keys. It refuses an alias whose value is another alias's key, or
   that would make a cycle. It bumps `version` by one, prints Added / Changed / Conflicts / Skipped, and moves merged
   exports into `Knowledge/Merged/`. `-n` prints the summary and changes nothing. Its header comment documents the
   routine: run it before each TestFlight build, open the diff as a PR, and the architect reviews it.
6. **Cleanup pass (D5).** `YesChefDataPasses.currentVersion` becomes the code version plus
   `BuiltInKnowledge.version`. Both only go up, so a new file re-runs the passes, including the #499 canonical-key
   refresh. Add a **knowledge cleanup** pass after "canonical names" that deletes, as synced writes:
   - name fixes whose two sides now share a base key;
   - `.user` area rows equal to the built-in area;
   - `.model` area rows for any name the built-in file places, which ADR-0052 D2's ladder already shadows;
   - trip switches equal to the built-in trip for that name.

   It keeps every row that disagrees with the file.
7. **Status script.** `scripts/knowledge-status` prints the exports waiting in `Documents/Knowledge/`, if any.
   It always exits 0.
8. **TestFlight warning (`jon-platform` PR).** `scripts/testflight` gains an optional `PREFLIGHT_WARN` config key
   naming a repo script. Preflight runs it and prints its output as a warning without failing, and its usage text
   and `docs/ios/testflight.md` say so. Yes Chef's `testflight.conf` sets `PREFLIGHT_WARN=scripts/knowledge-status`.

## Tests

- `YesChefCoreTests`:
  - the shipped file decodes;
  - every area value parses with `GroceryStoreArea.normalized`;
  - no alias chains or cycles; identity entries like `anchovies → anchovies` are allowed.
- An export from a seeded database contains exactly the D6 set: an unreviewed `.model` row and a pantry item are left
  out.
- Cleanup, with a test `BuiltInKnowledge` injected:
  - deletes a fix the aliases now cover, a `.user` area equal to the file, a shadowed `.model` row and a redundant
    trip switch;
  - keeps a `.user` area that disagrees.
- Read order: a `trips` entry beats the keeper rule; a saved switch beats a `trips` entry.
- `scripts/tests/test_promote_knowledge.py` (`python3 -m unittest`) covers:
  - add, skip and change;
  - two exports disagreeing;
  - a refused chain;
  - the version bump;
  - `-n` changing nothing.

## Verify

`scripts/check-drift.sh`, the generic iOS build (AGENTS.md #9) and `YesChefTests` on a simulator; then the script
tests. No simulator installs.

## Done when

- Tests above pass; check-drift and the generic build are green. The PR states that the temporary equality test
  passed before it was removed.
- Closeout per ADR-0005 D16 (DONE-LOG, archive this brief, advance NEXT_UP per D12).
- The `jon-platform` PR is open and linked from this PR.
- Gate line appended to `device-passes.md`:
  - on the iPad, run **Export What I've Taught**, then `scripts/promote-knowledge -n` on the Mac and check that the
    summary lists your mint fix;
  - run it for real; that first promotion goes up as its own PR;
  - install a build with that promotion and check that the mint fix is gone from **Name Fixes** while "fresh mint
    leaves" and "mint" still merge into one item.
