# ADR-0004 — The recipe editor edits structured rows, not text blobs

Status: Accepted

## Context

Codex's first implementation pass modeled the editor as flat text: ingredients,
instructions, and notes were each a single `String` in a draft, and **every save**
re-parsed that text and `DELETE`d + re-`INSERT`ed all child rows with fresh UUIDs
(`RecipeRepository.save` → `replaceChildren`). Side effects of that shape:

- structured/parsed ingredient fields (quantity, unit, item, preparation,
  shoppingCategory, doNotShop, confidence) are regenerated from a crude parser on
  every edit — manual corrections are lost;
- multi-section structure collapses to one ingredient section + one instruction
  section;
- every `RecipeNote` type (makeAhead, freezing, substitution, …) squashes into a
  single `general` note;
- fresh UUIDs on every save mean every edit re-creates every child row — once
  CloudKit private-DB sync lands (ADR-0002), that is maximal sync churn and
  conflict surface.

This contradicts the settled data model: preserve original + structured data
(DATA_MODEL §2.1/§2.2), stable IDs (§2.5, §31), and "structure where useful." It
also contradicts the house data-preservation priorities (AGENTS.md #1, #9).

We considered keeping the blob-entry UX and only fixing the persistence
(identity-preserving diffing of free text), and keeping the blob UX while
explicitly accepting the data loss as MVP debt. Both were rejected: diffing free
text to recover row identity is fiddly and still lossy at the edges, and accepting
the loss bakes the most expensive mistake (sync churn from unstable IDs) into the
foundation the whole app is supposed to be built on.

## Decision

**The editor edits structured rows with stable identity, not text blobs.**

- Ingredient lines, instruction steps, and notes are edited as real rows that keep
  their UUIDs across edits. Saving updates/inserts/deletes by identity — it does
  **not** wholesale delete-and-reinsert.
- Parsed ingredient fields are preserved; the parser only fills fields it can
  improve, and never overwrites a field a prior parse/import or the user already
  set.
- Section structure (`IngredientSection`/`InstructionSection`) and `RecipeNote`
  type are preserved through an edit; the editor never collapses them.
- Free-text "paste a block of ingredients/steps" remains a fine *input affordance*
  for new content, but it produces structured rows that then persist with stable
  IDs — it is not the storage model.

## Consequences

- More editor UI/model work up front than the blob shape, but it's the truest fit
  to the data model and the only shape that keeps sync churn low.
- The functional core Codex already built (`IngredientParser`, `InstructionParser`,
  `IngredientScaler`, `ServingParser`) is kept — it feeds row creation, not a
  destructive re-parse on save.
- Orchestration moves into an `@Observable` feature model that owns the draft state
  and a `@Fetch`/`FetchKeyRequest` load, calling the pure `RecipeRepository`
  functions (house pattern, jon-platform `swift-style.md`). See review docs in
  `docs/reviews/`.
- General persistence/observation rules this leans on are house-level
  (jon-platform): live-query reads (no `database.read` in `.task`) and persisted
  enums over `String` columns.
