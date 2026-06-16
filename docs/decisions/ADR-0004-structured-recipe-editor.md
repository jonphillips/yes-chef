# ADR-0004 — MVP editor uses text entry with structured, non-destructive persistence

Status: Accepted

## Context

Codex's first implementation pass modeled the editor as flat text: ingredients,
instructions, and notes were each a single `String` in a draft, and every save
re-parsed that text and `DELETE`d + re-`INSERT`ed all child rows with fresh UUIDs
(`RecipeRepository.save` -> `replaceChildren`). Side effects of that shape:

- structured/parsed ingredient fields (quantity, unit, item, preparation,
  shoppingCategory, doNotShop, confidence) were regenerated from a crude parser
  on every edit, so manual corrections could be lost;
- multi-section structure collapsed to one ingredient section and one instruction
  section;
- every `RecipeNote` type (makeAhead, freezing, substitution, and so on)
  squashed into a single `general` note;
- fresh UUIDs on every save meant every edit re-created child rows. Once CloudKit
  private-DB sync lands (ADR-0002), that would create avoidable sync churn and a
  larger conflict surface.

That contradicted the settled data model: preserve original and structured data
(DATA_MODEL §2.1/§2.2), stable IDs (§2.5, §31), and "structure where useful." It
also contradicted the house data-preservation priorities (AGENTS.md #1, #9).

There are two separate questions:

1. What entry UI is acceptable for the MVP?
2. What persistence semantics are acceptable for the structured model?

We accept a text-entry UI for the MVP because it is fast for real recipe entry and
matches how cooks often paste or type ingredients and instructions. We reject
destructive blob persistence. Text areas may be an input affordance, but the
database remains structured and must not silently destroy structure, types, parsed
fields, or stable identities.

## Decision

**The MVP editor may use text-entry fields, but saving is scoped and
non-destructive.**

- The editor's ingredient text field owns only the first/default
  `IngredientSection`. Additional ingredient sections are preserved until the UI
  has first-class section editing.
- The editor's instruction text field owns only the first/default
  `InstructionSection`. Additional instruction sections are preserved until the
  UI has first-class section editing.
- The editor's notes text field owns only `RecipeNoteType.general` notes. Typed
  notes such as `.makeAhead`, `.freezing`, `.substitution`, `.warning`, and
  `.retrospective` are preserved until the UI can edit them directly.
- Saving reconciles rows inside the editor-owned scope. Unchanged ingredient
  lines, instruction steps, general notes, and tag/category joins keep their
  UUIDs. Removed editor-owned rows are deleted. Newly added rows receive new
  UUIDs.
- Parsed ingredient fields are preserved when the parser cannot improve them.
  The parser can fill newly parsed fields, but a low-confidence parse must not
  erase better existing structure.
- Section structure and note types outside the editor-owned scope are preserved
  through edits; the editor never collapses them into the MVP text fields.
- Free-text paste remains a valid input affordance for new content, but it feeds
  structured row creation/reconciliation. It is not the storage model.

This is not the final editor shape. A later structured editor should carry row
identity in the draft/UI so edited rows can keep UUIDs even when their text
changes. The MVP text editor can only preserve identity for unchanged rows without
guessing.

## Consequences

- The MVP gets a usable editor quickly without compromising out-of-scope
  structured data.
- Sync churn is greatly reduced compared to wholesale delete/reinsert saves, but
  a full row-aware editor is still required before we can guarantee stable UUIDs
  for rows whose text changes.
- The functional core (`IngredientParser`, `InstructionParser`,
  `IngredientScaler`, `ServingParser`) is kept. It feeds row creation and
  conservative field filling, not destructive replacement.
- Orchestration lives in `@Observable` feature models that own draft state and
  observed `@Fetch`/`FetchKeyRequest` reads, then call pure `RecipeRepository`
  functions with an explicit `Database` (house pattern, jon-platform
  `swift-style.md`).
- Regression tests must cover stable IDs for unchanged rows and preservation of
  out-of-scope structured data. The current guardrail is
  `savePreservesUnchangedChildIDsAndNonGeneralNotes`.
- General persistence/observation rules this leans on are house-level
  (jon-platform): live-query reads, no `database.read` in `.task` to populate
  view `@State`, and persisted enums over stringly typed columns.
