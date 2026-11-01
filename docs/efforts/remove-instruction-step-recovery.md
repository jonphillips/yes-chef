# Effort — Remove the temporary Recover Missing Instruction Steps action

Status: Ready
Summary: The production cut is done, so remove PROD-CUTOVER Step 10a's temporary Settings action, its model, its
Core type and its tests. Nothing else uses them.

Schema-free. No migration. The rows it recovered stay; only the action goes.
Related: [`PROD-CUTOVER.md`](../PROD-CUTOVER.md) Steps 10a and 13 ·
[archive/recover-lost-instruction-steps.md](archive/recover-lost-instruction-steps.md) (what it added)

## Why

Step 10a put back the 241 instruction steps that the first re-seed attempt lost. It was built to be removed once
the cut was done, and every piece is marked `// TEMPORARY: PROD-CUTOVER Step 10a`. The cut passed on 2026-11-01.
Left in place, it's a Settings button that restores rows from an arbitrary backup file, with nobody watching it.

## What to remove

- `YesChefPackage/Sources/YesChefCore/InstructionStepRecovery.swift`
- `YesChefPackage/Tests/YesChefCoreTests/InstructionStepRecoveryTests.swift`
- `YesChefApp/InstructionStepRecoveryModel.swift`
- In `YesChefApp/SettingsViews.swift`, every block marked `TEMPORARY: PROD-CUTOVER Step 10a`: the model property,
  its initializer wiring, the Settings row, the file importer and the result alerts. After the change,
  `grep -rn "Step 10a" YesChefApp YesChefPackage/Sources YesChefPackage/Tests` finds nothing.
- Anything that constructs the model only to pass it into `SettingsView`. Follow the compiler.
- Run `xcodegen generate` for the removed files.

## Done when

- The grep above is empty, and nothing else in the app refers to the removed types.
- **Verification** per [`verification.md`](../verification.md): `scripts/check-drift.sh`, the elevated generic iOS
  build, and `YesChefTests`, since this removes an app-target model. A `YesChefTests` pass means exit 0 with no
  "Restarting after unexpected exit" line.
- In `PROD-CUTOVER.md` Step 13, tick the removal item.
- Closeout per ADR-0005 D16. No device pass: Settings simply loses a row.
