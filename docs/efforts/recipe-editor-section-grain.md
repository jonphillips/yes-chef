# Effort — recipe sections are stored, read, and edited at three different grains

**Status:** scoped 2026-07-27 from Jon's device pass of PR
[#245](https://github.com/jonphillips/yes-chef/pull/245) (the ADR-0047 capture fallback): *"the turkey
zucchini recipe came across with sections defined around the sauce and the meatballs, but my edit recipe
sheet only showed the first section,"* then *"it's strange that the ingredients are sectioned off, but the
instructions are not … it definitely requires me to think about it."* Dispatch-ready after the one open
question below is answered. **No schema** — the tables this needs already exist and already sync.

**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).

**Related:** [ADR-0040](../decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) (**governs** — this is
that thesis inverted: storage is *finer* than the edit affordance) ·
[ADR-0048](../decisions/ADR-0048-playbook-edit-grain.md) (the same argument, made for playbook sections) ·
[ADR-0047](../decisions/ADR-0047-llm-capture-fallback.md) (**why it surfaces now**, not its cause).

---

## The finding

**Nothing is lost, and the recipe is not broken.** Say this first because the symptom looks like data loss.
A recipe stores real `ingredientSections` / `instructionSections` rows — each with a `name` and `sortOrder`,
each owning its lines or steps — and every *reading* surface iterates all of them: the playbook's
`ingredientGroups` ([`RecipeVariationDisplayModel.swift:48`](../../YesChefApp/RecipeVariationDisplayModel.swift)),
the variation editor, Compare, grocery generation, the chat context. The Samin recipe's two ingredient
sections and three instruction sections are all in the database and all on screen when you read it.

**The editor is the one surface that isn't.** `RecipeEditorDraft(detail:)`
([`RecipeEditorDraft.swift:112`](../../YesChefPackage/Sources/YesChefCore/RecipeEditorDraft.swift)) takes
`.sorted { $0.sortOrder < $1.sortOrder }.first` of each and filters the lines/steps to that one section.
`RecipeEditorView` renders exactly one "Section title" field, one ingredients box, one instructions box.
Sections 2..n are invisible and uneditable.

**Saving does not destroy them.** `RecipeRepository.save(draft:)` reconciles through
`mergedSections(_:replacing:)` and `mergedIngredientLines(_:replacingSectionID:with:)`
([`RecipeCore.swift:399`](../../YesChefPackage/Sources/YesChefCore/RecipeCore.swift)), which replace **only
the edited section's** rows and carry the rest through untouched. This was checked, not assumed. So the
defect is "you cannot edit most of your recipe," not "editing eats your recipe" — bad, but not urgent in the
way it first looks.

## The second finding: instructions are stored in sections and displayed without them — and the flat display is load-bearing

**Instruction sections exist and are populated.** The Samin capture stored three (`Make the sour cream
sauce` / `Shape the meatballs` / `Cook the meatballs`), and they reach the model: `RecipeChatContext`
serializes `instructionSections` with their names
([`RecipeChat.swift:455`](../../YesChefPackage/Sources/YesChefCore/RecipeChat.swift)). **The cook is the one
party that never sees them.** `RecipeDetailView.instructions`
([`:768`](../../YesChefApp/RecipeDetailView.swift)) renders `model.instructionSteps` — a flat list, sorted by
`sortOrder` alone, numbered 1..n continuously — while `ingredients` two functions above renders
`model.ingredientGroups`, grouped with section names. Same recipe, two grains, one screen. Compare
([`WorkbenchCompareView.swift:495`](../../YesChefApp/WorkbenchCompareView.swift)) and the adjustment review
flatten the same way; the **variation editor already groups by section**
([`RecipeVariationEditor.swift:321`](../../YesChefApp/RecipeVariationEditor.swift)), so the shape to copy is
already in the codebase.

**The order is not scrambled today — but only because one function is careful.** `makeInstructionSteps`
([`ParsedRecipePage.swift:290`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/ParsedRecipePage.swift))
walks the sections in order and assigns a **single running global counter** across all of them, so sauce →
shape → cook survives into a flat list. Jon's "maybe one section's instructions come before the other's" is
that ambiguity being *felt* rather than a real transposition: five steps run together with nothing marking
where a phase ends.

**The hazard is one editor save away.** `InstructionParser.steps(from:…)`
([`RecipeCore.swift:848`](../../YesChefPackage/Sources/YesChefCore/RecipeCore.swift)) numbers from `0` for
the section it is given, and the editor only ever gives it section 1. So saving an edit renumbers section
1's steps `0…k` while sections 2..n keep their import-time **global** values — on the Samin recipe, section
1 step 0 and section 2 step 1, then a single added step collides at `1`. A flat sort keyed only on
`sortOrder` then has ties, and the order of two adjacent steps becomes unstable. **The display asymmetry and
the ordering hazard have the same fix**: group by section and sort by `(section.sortOrder, step.sortOrder)`,
and global uniqueness stops being load-bearing at all.

**Reader and Compare number within sections** — restart at 1 under each section name, which is how the source
page reads and how the model returned it. The adjustment review is the deliberate continuous-numbering
exception, recorded with S1 below.

## Sections vs. headings — the distinction the symptom exposed

There is no "heading" concept in the schema. A heading is the **in-band wire format** the flat-text channels
use to express a section, and only *one* of the two channels reads it back:

| Channel | Shape | Heading → section? |
|---|---|---|
| **Capture / import** — every deterministic extractor plus the ADR-0047 model path feeds `RecipeParseBuilder` a flat line list | flat `[String]` | **Yes.** `IngredientSectionHeading.sections(in:)` promotes a colon-terminated or ALL-CAPS line carrying **no parsed quantity** to a section name. This is where Samin's two sections came from. |
| **Editor** — `RecipeEditorDraft.ingredientText` → `IngredientParser.lines(from:…sectionID:…)` | flat `String` + one section-title field | **No.** Every line is stamped with the single editable section's ID. Type `For the meatballs:` in the editor and you get an ingredient *line* reading "For the meatballs:". |

So the same text means two different things depending on which door it comes through — and the door with the
section-title field is the one that can't make a section. That asymmetry is the real bug behind the symptom.

**Why now.** This is pre-existing and has nothing to do with the LLM fallback — but before ADR-0047, the
no-contract category produced **zero** sections, and most JSON-LD recipes ship one flat `recipeIngredient`
list. The fallback returns *typed* named sections from a category of page that reliably uses them, so
multi-section recipes go from rare to routine. The fallback didn't break the editor; it made the editor's
grain visible.

## Slices

**S1 first and on its own.** It is the smallest slice, it is the one Jon can see, and it removes the
ordering hazard before the editor work has a chance to trip it.

- **S1 — instructions read at the grain they are stored.** An `instructionGroups` projection mirroring
  `ingredientGroups`, ordered by `(section.sortOrder, step.sortOrder)`, numbered from 1 **within** each
  section, with the section name as a subhead; applied to the detail view, Compare, and the adjustment
  review. **Put the grouping and ordering rule in Core over `RecipeDetailData`, not in the app's display
  model** — it is the thing production reads, so a Core test pins the tie-breaking case (two sections whose
  steps share a `sortOrder`) instead of restating the mapping. Sections with no name render their steps
  without a subhead, so a single-section recipe looks exactly as it does today — that is the canary.

**Amendment — adjustment numbering (2026-07-27).** The exception to per-section numbering is the adjustment
review: `RecipeMethodStepReplacement.stepNumber`, `adjustmentContext`, and the unresolved-instruction-step
error all refer to a global step number. Reader and Compare restart at 1 per section; the adjustment review
keeps continuous numbering so that those references match what the cook sees.

- **S2 — Core: the editor draft carries every section (no UI).** `RecipeEditorDraft` grows an ordered array
  of section drafts (id, name, text) for ingredients and instructions instead of the four flat fields;
  `save` reconciles each by section ID and handles renames, adds, reorders, and removals — a section deleted
  in the draft must delete its rows, which the current merge-only path never had to express. Tests: a
  two-section recipe round-trips draft → save → detail **unchanged** (the pin that would have caught this),
  plus edit-second-section, rename, add, delete. With S1 shipped, per-section step renumbering on save is
  correct rather than a collision.
- **S3 — App: the editor renders the sections it now carries.** Per-section ingredient and instruction
  blocks with add / rename / delete, following the ADR-0048 grain rule — *the affordance is a readout of
  storage, and storage here is rows*. Needs the elevated `generic/platform=iOS` build.

## Open question — one, and it needs Jon

**Does the editor's text box promote typed headings to sections, the way capture does?**

The recommendation is **no**: per ADR-0040 D2 the human edits fields, never the wire format, and a heuristic
that silently converts a line you typed into a structural section is exactly the hidden-state re-derivation
that ADR forbids. S2's explicit "Add section" control is the honest affordance. But it is Jon's call, because
the cost is real — pasting a whole recipe with `For the sauce:` headings into the editor would produce one
long section, where capture would have produced two, and that inconsistency is *also* confusing. A middle
option exists: promote on **paste only**, visibly, with the result editable afterward.
