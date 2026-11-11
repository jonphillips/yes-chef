# Effort — A prep step shows its make-ahead window, and plans leave room for leftovers

Status: Ready
Summary: Prep steps gain an optional `makeAheadWindow` ("Up to 3 days ahead"), filled by the in-app weave, the Copy Prep Prompt round trip and `stage_prep_plan`. It's editable, and shown above the task. Every producer also schedules so about 3 days of keeping remain after the meal. One nullable synced column, with a Production deploy.

Origin: Jon's Thanksgiving Week dogfood (2026-11-11). One dispatch, one PR. **Persistent model change, authorized by
ADR-0034 Amd 2.**

Decisions: [ADR-0034 Amendment 2](../../decisions/ADR-0034-prep-plan-work-session-timeline.md#amendment-2--a-step-shows-its-make-ahead-window-and-plans-leave-room-for-leftovers-2026-11-11)
(B1, B2; read it first). Precedent for every step below: [archived `menu-absorbs-calendar-days`](menu-absorbs-calendar-days.md)
S3, which added `workDayOffset` to the same table and threaded it through the same producers. Related:
[archived `stage-prep-plan`](stage-prep-plan.md) (the chat tool) · ADR-0060 Amd 5.

If #484 (dogfood fixes) merges first, it has changed `stage_prep_plan`'s description and the session-label styling in
`MenuViews.swift`. Build on top of both.

## Where things are (architect, 2026-11-11, `origin/main` 6e6f374)

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `Schema.swift`: the last migration is "Add prep plan work day offset" (about line 1363). Append after it.
- `MenuPrepPlan.swift`:
  - `PrepPlanStepRecord` and `PrepPlanStep` (Codable keys `session`/`when`, `task`, `serves`, `sourceDish`, `workDay`).
  - The editable review text: `editableReviewText`, `parsingEditableReviewText`, and `renderedEditableReviewLine` /
    `editableReviewLine` at the bottom.
  - `MenuPrepPlanClient.instructions` (about line 350): the in-app weave's JSON contract.
  - `PrepPlanStepRepository`: `create`, `update`, `replace` and its private `Contents` (about line 616).
- `MenuChatContext.swift`: `prepPrompt(…)` (about line 195, the Copy Prep Prompt text), and the "Current prep plan"
  lines (about line 295).
- `MenuBringIn.swift` (about line 184): copies steps into another menu.
- `ChatPrepPlanImport.swift`: `ChatAccessStagedPrepPlan.Dish.Step`, `apply` (the insert), and `same(_:_:)`.
- `ChatAccessExport.swift`: `PrepStepRecord` (about line 56) and where it's built (about line 198).
- Backup/restore: check whether `prepPlanSteps` has table-level coverage, as S3 of the precedent did.

**Helper (`YesChefMCP/Sources/YesChefMCPServer/`)**
- `YesChefMCPServer.swift`: `stage_prep_plan`'s description, its step schema, and `decodeAndStagePrepPlan`.
- `ChatAccessReadTools.swift` (about line 178): `get_menu`'s step fields.

**App (`YesChefApp/`)**
- `MenuPrepPlanEditingViews.swift`: `MenuPrepPlanStepView` (the step row) and `PrepPlanStepEditorDraft` /
  `PrepPlanStepEditorSheet`.
- `MenuDetailModel+PrepPlanEditing.swift`: create and update.
- `ChatMenuReviewSheet.swift`: `stepRow` in `ChatPrepPlanReviewSheet`.

**Repo root:** `cloudkit-expected-fields.txt`, the `testflight` gate's field list.

## The slice

### Schema (B1)
- Append a migration: `ALTER TABLE "prepPlanSteps" ADD COLUMN "makeAheadWindow" TEXT`. Never edit a shipped migration.
- Add `makeAheadWindow: String?` to `PrepPlanStepRecord`, and to `PrepPlanStep` with Codable key `makeAheadWindow`,
  decoded with `decodeIfPresent`. Old JSON and old rows decode to nil. Nothing is backfilled.
- Clean it like `serves` (`cleanedPrepPlanText`): blank becomes nil.
- Add `prepPlanSteps makeAheadWindow` and its `sqlitedata_icloud_userModificationTime_makeAheadWindow` line to
  `cloudkit-expected-fields.txt`, in sorted position.

### Carry it everywhere a step goes
- `PrepPlanStepRepository` `create`, `update` and `replace` write it. `Contents` includes it (B1 identity).
- `MenuBringIn` copies it unchanged.
- The export's `PrepStepRecord` gains optional `makeAheadWindow`; `get_menu` shows it when set. Keep the export at
  version 1.
- `MenuChatContext`'s "Current prep plan" adds `  - Make-ahead window: …` under a step that has one, beside `Serves`.

### Producers (B1 source, B2 rule)
Use one shared sentence pair for B2 so the three producers can't drift. Put it in Core as a static string and use it in
all three:

> When a dish keeps for days, schedule it so about 3 days of keeping remain after the meal it feeds: a sauce that keeps
> a week is made no more than 4 days before. Follow windows in hours, or of a few days or less, as written. The
> make-ahead preferences can change the 3 days.

- **In-app weave** (`MenuPrepPlanClient.instructions`): each step's JSON gains `"makeAheadWindow": "the recipe's own
  limit in a few words, e.g. \"Up to 3 days ahead\", or null"`. Ground it in the dish's Make-Ahead note, else the
  recipe; null when nothing says. Add the B2 sentences.
- **Copy Prep Prompt** (`prepPrompt`, and the review text below): ask for the window line and add the B2 sentences.
- **`stage_prep_plan`:** the step schema gains optional string `makeAheadWindow`; the staged `Step` carries it; apply
  inserts it. `same(_:_:)` compares it too, so a changed window is Removed plus New. Add one short clause to the tool
  description for the field and the B2 rule. The description has no hard budget, but keep the addition under about 300
  characters.

### Editable review text
A step with a window renders a second line under its bullet, indented two spaces: `  Keeps: <window>`. When parsing, a
line that trims to `Keeps:` followed by text and comes right after a bullet sets that step's window. Anywhere else it's
an unparsed line, as today. A plan with no windows renders byte-identical to today.

### App
- **Step row:** when `makeAheadWindow` is set, show it above the task as a caption in secondary color, with a clock
  symbol (`clock`). Nothing when nil.
- **Editor:** a "Make-ahead window" text field after Task, with placeholder "e.g. Up to 3 days ahead". Create and update
  write it.
- **Chat review sheet:** `stepRow` shows the window under the task when present, so a Removed-plus-New pair from a
  window change reads plainly.

## Tests

**Core**
- Old JSON and old rows decode with no window. The migration adds the column to a database with rows.
- Weave JSON with `makeAheadWindow` stores it; blank stores nil.
- `replace`: the same step with a different window gets a new id; with the same window, keeps its id.
- Bring-in copies the window.
- Review text: round-trips a window; a plan with no windows is byte-identical to today; a `Keeps:` line with no bullet
  above it is unparsed.
- `stage_prep_plan`: a staged window is inserted; a window change shows Removed plus New; the export carries the field
  and decodes without it.
- The B2 string appears in the weave instructions, the copy-out prompt and the tool description (one assertion each, on
  the shared constant).
- Backup → restore keeps the window, if the backup path has table-level coverage.

**Helper:** the schema accepts `makeAheadWindow` and rejects a non-string one.

**App (`YesChefTests`):** saving the editor with a window writes it. This touches `YesChefApp/` model code, so the target
runs (guardrail #9).

## Done when

- A step stores, shows and edits its make-ahead window, and every producer fills it when grounded.
- All three producers carry the same B2 rule.
- Tests above. Verification per [`verification.md`](../../verification.md), including the generic app build and
  `YesChefTests`. Then closeout (ADR-0005 D16).
- The PR body gives Jon the install order: the app on both devices, then the helper.
- **Gate, before any TestFlight upload:** create `prepPlanSteps.makeAheadWindow` (STRING) in Development, confirm the
  schema export differs from Production only by that field, and deploy. The `testflight` expected-fields gate blocks
  the upload until then.
- **Jon's device gate:** on Thanksgiving Week, Rebuild with Yes Chef. Steps for dishes with Make-Ahead notes show their
  windows above the task. A long-keeping sauce lands about 3 days inside its window. Edit one window and save. Then
  restage one dish's prep plan from ChatGPT: windows arrive, and a changed window shows Removed plus New.
