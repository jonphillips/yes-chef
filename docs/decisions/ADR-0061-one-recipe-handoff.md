# ADR-0061 — One recipe hand-off: one button, one prompt, and the cook picks what comes back at finalize

> **One-line:** A recipe has one outboard door, not four. The toolbar **Hand off** copies one prompt. That
> prompt lists everything Yes Chef can take back: a revision brief, a new recipe, Make-ahead lines, Chef It
> Up lines, Serve With lines, and learnings. The cook talks it through and then says which ones to finalize.
> Each deliverable comes back under its own label, and the router files each one by its label. The task
> type on the row no longer decides it. Each section's `•••` becomes a plain **Edit** button, and **Clear**
> moves to the bottom of the section's editor.

Status: **Proposed** — 2026-11-03.
Origin: Jon, while reviewing the ADR-0060 Amendment 1 plan PR (#431): *"make ahead [and] chef it up both have
prompt creation as well as there is a general prompt creation for the recipe… it can be confusing as to which
one you should hit and it really feels like we should only have one."*
**Supersedes, for recipes on the outboard path:** [ADR-0041](ADR-0041-playbook-section-toolbar-and-scoped-handoff.md)
D3 (section-scoped hand-off). **Widens** [ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) Amd 1-D4
(the Adjust prompt's scope). **Reverses**, for this prompt only, the regenerate-fresh rule in ADR-0041 Amd 1-D1
(see D5). **Partly reverses** ADR-0041 Amd 2's "Clear leaves the section editor sheet": Clear returns to the
editor, in a different spot (see D1a). **Closes** the checkbox item that [ADR-0038](ADR-0038-external-llm-handoff.md) Amd 2 and ADR-0041 both
deferred (see D7). Builds on: ADR-0038 Amd 7 (`YC-LEARNINGS:` lines are format-agnostic; the token is the
authority for scope); [ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) (lossless or loud);
ADR-0041 Amd 1-D1 (a section return is merge-or-choose).

## Context

### How we got four doors

The history runs the other way from how it's remembered:

1. **One whole-recipe hand-off.** ADR-0038 Amd 2 put **Hand off** on the recipe. ADR-0041's Context found it was
   secretly a make-ahead verb: `HandoffExportSource.recipe` mapped to `taskType: .recipeMakeAhead`.
2. **Three section hand-offs** (ADR-0041, 2026-07-17 to 07-19). Each Playbook section got its own `•••` with
   **Hand off** and **Paste**, so Chef It Up and Serve With could use flat-rate ChatGPT too.
3. **A new whole-recipe hand-off** (ADR-0042 Amd 1, 2026-07-21). The toolbar **Hand off** became `adjustRecipe`.
   It takes the whole recipe, including the Playbook, and returns either a revision brief or a new recipe as
   JSON-LD. It decides which from the conversation.

So a recipe now has four outboard prompts, all built in
[`AIHandoffContext.swift`](../../YesChefPackage/Sources/YesChefCore/AIHandoffContext.swift):
`prompt(forTask: .adjustRecipe)` and `prompt(for: .makeAhead / .chefItUp / .serveWith)`. Each mints a
different `AIHandoffTaskType`. The return's parse is chosen by that type in `AIHandoffReviewStager.recipeReview`.

### Why that's confusing, not just redundant

- **The doors overlap where it matters most.** A Chef It Up upgrade ("brown the butter first") is also a
  candidate revision. Today the cook must decide *before the conversation* whether the result belongs in
  the Playbook or should edit the recipe. The conversation is what answers that question.
- **One conversation often wants two outputs.** "Talk me through this braise" ends naturally in a make-ahead
  plan *and* a change to the method. Today that's two hand-offs, two chats, and two copies of the context.
- **The section prompts hide what's already there.** They strip the current section
  (`serialized(excludingPlaybookSections: [section])`), so the chat can't see what the cook already wrote.
  The Adjust prompt includes everything. So the two doors give the model different views of the same recipe.

### What the code already gives us

- **A self-contained prompt with several finalize shapes.** `AIHandoffToken.selfContainedPrompt` exists
  because the Adjust prompt describes its own two return shapes. No contract change was needed then
  (ADR-0042 Amd 1-D6).
- **Shape-based routing.** The in-app paste transport already routes an Adjust return by its shape: JSON-LD
  goes to Create Recipe, prose goes to the brief review
  ([`HandoffInAppTransport.swift:91`](../../YesChefApp/HandoffInAppTransport.swift)). That logic lives in the
  app layer, not in Core.
- **A labeled section in the return.** `YC-LEARNINGS:` is already a header that the parser splits on.
- **Re-paste is already allowed on the paste door.** `stageReview(…, allowRestage: true)` rebuilds the review
  from the same token (`AIHandoffIntentImport.swift:80`). Strict callers reject a second return as `.duplicate`.
- **Learnings already dedupe on ingest** (`normalizedLearningText`, `AIHandoff.swift:306`), so a repeated
  `YC-LEARNINGS:` block doesn't double up.

## Decisions

### D1 — A recipe has one outboard door

The toolbar **Hand off** is the only way to copy a recipe prompt. The toolbar **Paste** is the only in-app way
to paste a recipe return. The section `•••` menus lose **Hand off / Hand off again** and **Paste**, which
leaves only Edit and Clear. D1a replaces the menu. The variation guard stays: the prompt exports the base recipe, so it
asks first when a variation is showing (ADR-0042 Amd 1 OQ3).

The menu, meal-plan day, workbench, and capture hand-offs are out of scope. The meal-plan day has the same
two-door shape (**Make-ahead** / **Complement**), and this pattern would fit it. That's a later amendment,
taken only if the recipe version holds up on device.

### D1a — The section `•••` becomes an **Edit** button, and Clear moves to the bottom of the editor

With D1, the menu would hold only Edit and Clear. A menu with one routine action and one destructive one is
more ceremony than it's worth. Origin: Jon, reviewing this ADR (2026-11-03).

- **One button per section.** It reads **Edit** when the section is filled and **Write** when it's empty, and
  it opens that section's editor.
  - **Make-ahead and Chef It Up** open the text editor sheet they use today.
  - **Serve With** opens its whole-list editor: add, edit, delete, reorder. Today its header carries **two**
    buttons, a **Manage** slider (`slider.horizontal.3`, shown only when filled) that opens that editor, and
    `•••`, which has no Edit. **Edit / Write** replaces both. The per-row **+** and swipe-to-delete stay.
- **Clear goes inside the editor, at the bottom of its content.** It's a full-width destructive row (**Clear
  Make-ahead**), the way iOS Settings places a destructive action at the end of a form. It's shown only when
  the section is filled, and it keeps Amd 2's confirmation, which names the section and says there's no undo.
- **Never in the navigation bar.** This is the part of ADR-0041 Amd 2 that still holds. Amd 2 moved Clear out of
  the editor because it sat next to **Cancel** and was easy to hit by mistake. The defect was where it sat, not
  which sheet it was in. At the far end of the content, behind a confirmation, it's in a different place from
  Cancel in the top bar.
- **No change to what Clear writes.** Each section's clear path stays as it is (`clear(_:)` in
  `RecipePlaybookView`). Only the button moves.

### D2 — The prompt offers a menu of deliverables; the cook picks at finalize

The prompt says, in effect: *discuss freely; when the cook asks you to finalize, return only the deliverables
they ask for.* The menu:

| Label | Deliverable | Format (unchanged from today's prompt) |
|---|---|---|
| `YC-REVISION:` | Targeted changes to this recipe | Revision brief: prose, one change per line, in method order (ADR-0042 Amd 1-D1) |
| `YC-NEW-RECIPE:` | A different dish that should stand alone | schema.org Recipe JSON-LD (`RecipeJSONLDContract`) |
| `YC-MAKE-AHEAD:` | Make-ahead notes | `When: task` lines, canonical timing labels, six at most |
| `YC-CHEF-IT-UP:` | Technique and flavor upgrades | One upgrade per line, six at most |
| `YC-SERVE-WITH:` | Accompaniments | `title: note` lines |
| `YC-LEARNINGS:` | New durable learnings | Unchanged (ADR-0038 Amd 7) |

Rules the prompt states:

- **Only what was asked for.** If the cook says "finalize," with nothing more, and it's ambiguous, the model asks
  one short question. That's the Adjust prompt's rule today. It must never fill every slot by default.
- **A new recipe stands alone.** `YC-NEW-RECIPE:` is never combined with another deliverable, and it skips
  learnings, as today.
- **A revision can travel with section notes.** If both are present, the section notes describe the recipe
  *as revised*. The review shows the section items first, then opens the existing side-by-side for the brief.
- **The per-section preferences all ride along.** The taste profile plus the Make-ahead, Chef It Up, and Serve
  With preferences from AI Settings (ADR-0018). The learnings ask uses the Adjust prompt's revised wording
  (ADR-0042 Amd 1-D7), which already covers notes and revisions.

### D3 — The router files by label; `.recipe` is the new task type

- **New `AIHandoffTaskType.recipe`** ("Recipe"). The toolbar **Hand off** mints it. `AIHandoff` is a local
  table, so the new case is schema-free and needs no migration. The four existing recipe task types stay
  routable, so tokens already in flight and onboard discussions keep working. The outboard path just stops
  minting them for recipes.
- **The stager splits the payload on the labels** and builds one review item per deliverable, using the review
  items that exist today: the section reviews, which keep ADR-0041 Amd 1-D1's merge-or-choose and **Currently
  saved**; the adjustment-brief review; and the new-recipe route. The JSON-LD detection moves from the
  app's paste transport into Core, so every door uses the same routing (see Relation to ADR-0060 below).
- **Lossless or loud.** If the text under a recipe token has no label, the review shows it raw, with a
  **File as…** choice. The router never guesses. A label the build doesn't know is also shown raw, never dropped.

### D4 — A recipe token accepts more than one return

The natural flow is: finalize the make-ahead, paste it, keep talking, then finalize a revision. The paste door
already re-stages under the same token. For `.recipe`, every door does the same: each return is staged as its
own review. `importedAt` records the first import, and a later return doesn't fail as `.duplicate`. Learnings
dedupe already absorbs a repeated block. Other task types keep the strict single-return guard.

### D5 — The prompt carries the whole recipe, current Playbook included

This reverses one earlier call. ADR-0041 Amd 1-D1, and Jon's 2026-07-18 call behind it, said a section hand-off
*excludes* the current section so a re-hand-off starts fresh: *"re-handing-off means something went wrong →
start over."*

That was right for a single-section verb whose only job was regenerating. It's wrong for a conversation about
the dish. A revision needs to see the current make-ahead plan. A good make-ahead plan often comes from refining
the one already there. The Adjust prompt already includes the Playbook for this reason (ADR-0042 Amd 1-D4).

- The prompt labels each filled section **currently saved**, and tells the model the cook may want a section
  replaced, not refined.
- Starting fresh is one sentence in the chat ("ignore the current make-ahead").
- The return side is already safe: Replace or Append with no default, **Currently saved** shown, and the Serve
  With union prefill (ADR-0041 Amd 1-D1).

### D6 — No contract bump

As with the Adjust prompt (ADR-0042 Amd 1-D6), the prompt carries its own return shapes, so
`AIHandoffReturnContract` stays at v3 and nobody re-copies project instructions. The contract's generic rules
already fit: token line, marker, deliverable, `YC-LEARNINGS:`.

**Rejected for now: moving the per-deliverable formats into the contract.** That would shorten the prompt, but
it costs a v4 bump and a re-copy, and the contract would then carry recipe-only rules. Revisit when ADR-0060
Amd 1-D4 moves the contract into the MCP server's instructions. That move is a re-copy anyway, and the
formats could ride along.

### D7 — No checkboxes

A checkbox sheet before **Copy** asks the cook to predict the conversation's outcome before it happens. It also
adds a step to every hand-off, which is the friction ADR-0041 Amd 1-D2 removed from the Playbook. D2's
pick-at-finalize does the same selecting at the moment the cook knows the answer. This closes the item that
ADR-0038 Amd 2 and ADR-0041 both left deferred.

### D8 — Out: the onboard Discuss ▾ starters

The onboard panel's **Discuss ▾** still offers one starter per section (ADR-0045 Amd 3). Collapsing it into one
"Discuss this recipe" starter is the same idea, but its finalize path differs: `stageOnboardReview` and its apply
verbs. It's a follow-on, taken only after the outboard version passes on device. The prompt builder from D2
is shared, so the remaining cost is in the onboard finalize UI.

## Relation to ADR-0060 Amendment 1 (PR #431, open)

**No change is needed there.** Amd 1-D2 says the helper checks only the envelope, and the app checks the body
"because the task type is on the device-local row." Under this ADR the row still says `.recipe`, so the app
still knows to parse labels. The body check still happens in the app, as Amd 1-D2 says.

D3's move of JSON-LD detection into Core matters for one reason: a `stage_handoff_return` call that carries a
`YC-NEW-RECIPE:` block must route the same way a paste does.

## Persistent model impact

- **`AIHandoff.taskType` gains `.recipe`.** It's a local table (not synced), raw-value additive, with no
  migration. Existing rows are untouched.
- **No synced schema changes.** Section commits, the brief commit, and learnings all use their existing write
  paths.
- **Dead data:** the four legacy recipe task types keep minting from onboard (D8) until that follow-on ships.
  Their retirement is that follow-on's job.

## Slices

One dispatch, two parts. S2 has nothing to call until S1 lands, and S1 has no consumer without S2.

- **S1 — Core.** `RecipeHandoffContext.prompt(forTask: .recipe)` with D2's menu and D5's labeled context. A
  labeled-return splitter, plus Core JSON-LD detection. `recipeReview` for `.recipe` returns several review
  items, and unlabeled or unknown text comes back loud. D4's repeat-return rule for `.recipe`.
  Tests: each label alone; make-ahead plus Chef It Up in one paste; revision plus a section; new recipe
  rejected when combined; an unlabeled body; an unknown label; a second return on one token; legacy
  task-type tokens still importing.
- **S2 — App.** The toolbar **Hand off** mints `.recipe`. Each section's `•••` becomes D1a's **Edit / Write**
  button. **Clear** moves to the bottom of each editor, including Serve With's list editor, and keeps its
  confirmation. The review coordinator shows several items from one return, then the brief's side-by-side.
- **Device pass (Jon).** One chat that finalizes Make-ahead and Chef It Up in one block. The same chat
  finalizing a revision afterward. One that riffs into a new recipe. Checking that a filled section shows
  **Currently saved** with Replace or Append. Clearing each section from the bottom of its editor, and
  confirming that Cancel and Clear can't be confused.

## Open questions

- **OQ1 — Do we keep a focused shortcut?** If Jon misses one-tap "make-ahead for this," a section `•••` could
  offer **Hand off** that copies the *same* `.recipe` prompt with a `Focus: Make-ahead` line added. It's the
  same task and the same return, with no new prompt. Recommendation: leave it out of S2 and add it only if
  dogfooding asks for it.
- **OQ2 — Prompt length.** The full recipe, three preference blocks, five format rules, and learnings make a long
  prompt. The bounded context (`bounded(_:)`) caps the recipe part. If ChatGPT starts ignoring the format rules,
  that's the trigger for D6's contract move.
