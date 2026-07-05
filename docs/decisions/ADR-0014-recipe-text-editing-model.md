# ADR-0014 — Recipe text editing model (header toggles vs. rich text)

**Status:** Accepted (direction) — 2026-07-04. Scope resolved with Jon; implementation not yet dispatched.
**Owner:** Claude (architect) · Jon (product).

## Context

Jon, dogfooding 2026-07-04:

> "The header on/off editing functionality is pretty crazy from a UI perspective. Why are we avoiding
> allowing me to just set text to Bold, Italics, etc.?"

The structured editor (ADR-0004) models a recipe as typed rows — ingredient lines, instruction steps, and
**section headers** that are a *structural row kind*, toggled on/off, rather than inline text styling. So
"make this a header" is a row-type switch, not "select text → bold." That structural model is what powers
auto-numbering of instructions, ingredient scaling, grocery/pantry canonicalization, and the whole
parse/scale/render pipeline. Free-form rich text would sever those affordances from the text.

### What grounding the code revealed

The schema already contains **two competing grouping mechanisms** that don't agree:

- `IngredientSection` / `InstructionSection` (`Models.swift`) — real structural groups, each with a `name`,
  UUID PK, already sync-safe, already rendered as grouped sections and reasoned over by the app.
- `isHeader: Bool` on a line (`Models.swift`) — a *label row* that lives inside a section but owns nothing
  below it. This is the "toggle" Jon is fighting.

Critically, the editor only surfaces the **first** section (`RecipeEditorDraft.init(detail:)` →
`firstIngredientSectionID`). Multi-section recipes are flattened on edit, and the `isHeader` toggle was the
consolation affordance for expressing structure the editor otherwise threw away. **That flattening is the
root of the "crazy UI" complaint** — not the structural model itself.

## Decisions (resolved 2026-07-04)

The pain was the **editor UI**, not the structured model. We keep structure; we fix the affordances. Three
independent changes, sliceable separately:

### D1 — Grouping: promote headers to real sections; make the editor section-aware

Chosen behavior (Jon): a header must **own the rows beneath it** — reorder / collapse / delete as a unit,
not just show a label.

- The editor becomes multi-section: it reads and writes all `IngredientSection` / `InstructionSection`
  rows, using each section's `name` as its header.
- A "header" in the flat-text authoring flow becomes a **section boundary**, not an `isHeader` line.
- **Retire `isHeader`** as an authoring concept. Migration: existing `isHeader` rows are promoted to a new
  section whose `name` = the header row's text, owning subsequent lines until the next header. Keep the
  column readable during transition; stop writing new `isHeader=true` rows.
- Downstream is unaffected: scaling, numbering, and grocery canonicalization operate per-line and are
  already section-agnostic. Sections already round-trip through CloudKit (UUID PKs), so this is additive.

### D2 — Inline styling on free-text fields only (Markdown-in-string)

- Applies to **free-text fields the app does not parse**: `summary`, notes, tip blocks. Ingredient and
  instruction rows stay structural — no inline styling there.
- **Encoding: Markdown stored inline in the existing text columns** (`**bold**`, `*italic*`). Render with
  `AttributedString(markdown:)`. Rationale: purely additive (columns are already `String`), CloudKit-safe,
  human-legible in the raw store, no attributed-run/BLOB model to sync. Rejected the attributed-run model
  as heavier with no round-trip benefit.
- Editor affordance: a minimal bold/italic control (or just let raw Markdown through initially).

### D3 — `[square bracket]` = author note, rendered lighter

- Convention: text in `[…]` inside an ingredient line is a **Jon note**, rendered at a lighter weight /
  de-emphasized.
- **Pure render rule + parser-ignore** — no schema change. The ingredient parser must treat bracketed spans
  as annotation, not item/quantity/unit; it can land the text in the existing `comment` field. The bracket
  stays in `originalText` so the round-trip is lossless.

## Sequencing / cross-cutting

- **`normalize-recipe` (de-caps imported all-caps) must be markup-aware**: it must not strip `**`/`*` runs
  (D2) or `[…]` spans (D3), and must not up/down-case inside them. Normalization runs on import before user
  styling exists, so the live conflict is small, but any re-run pass has to respect the markup.
- All three are **additive** and land after sync is live — no migration risk beyond the D1 `isHeader`
  promotion, which is a one-time forward transform.
- Suggested slice order: **D3** (smallest, render-only) → **D2** (free-text styling) → **D1** (editor
  section rework, the meatiest).

## Consequences

- Retires the `isHeader` toggle and the single-section editor flattening — net reduction in concept count.
- The editor gains multi-section authoring, which the data model has always supported but never exposed.
- Free-text fields carry Markdown; anything that displays `summary`/notes must render through the Markdown
  path or it will show literal `**`.
- `normalize-recipe` picks up a markup-awareness requirement.
