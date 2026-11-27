# AGENTS.md

## Project Identity

An Apple-first, private, local-first recipe management and cooking-planning app for serious
home cooks who collect, adapt, plan, shop, cook, and remember what worked. Paprika-inspired,
not a clone. The core is a single owner's private library (ADR-0003), with no
`Household`/`Cook`/sharing schema. Product and style background (recipe model, UI feel, import, AI,
original MVP scope) is in [`docs/product-principles.md`](docs/product-principles.md); read the
section the work touches.

## Working mode

Architect / executor, per jon-platform `AGENTS.md`.

## Read first

1. `~/code/jon-platform/AGENTS.md`: the house stack and rules. Nothing here overrides it unless we
   discuss it. If you can't access it, stop and tell Jon.
2. [`docs/README.md`](docs/README.md): the map of this repo's docs. Closed decisions live in
   `docs/standing-guards.md`; read it when a dispatch touches what it guards.

## Development Priorities

In order:

1. Preserve user data.
2. Keep the data model clear and migration-friendly.
3. Build the core recipe library before clever features.
4. Prefer simple, idiomatic Swift and SwiftUI.
5. Avoid premature server/backend complexity.
6. Avoid premature AI features.
7. Add tests for parsing, import, scaling, and data transformations.
8. Keep UI code readable and decomposed.
9. Preserve original imported recipe text.
10. Ask before making persistent model changes that imply migration complexity.

Do not build, unless explicitly requested: user accounts, a server backend, social sharing or
a public feed, nutrition tracking, subscription/payment infrastructure, Android or web apps,
complex AI recipe generation, OCR, or a voice assistant.

Keep model, persistence, parsing/import, and UI separate.

## Implementation Guardrails Learned From Pass 1

Project rules, not preferences. ADRs cite them by number, so the numbers are fixed. Items that are
now house law are one-line pointers to where the rule lives.

1. Composite detail reads are observed, never read once from `.task` into view `@State`
   (jon-platform `persistence-and-sync.md` § Reads are observed, never hand-pulled).
2. Behavior lives in `@Observable @MainActor` models, and repository functions are pure database
   operations taking an explicit `Database` (`swift-style.md` § Thin views, § Persistence core).
3. Editor text blobs are an input surface, not permission to flatten the model. Until the editor
   is section-aware it owns only the first default ingredient section, the first default
   instruction section, and general notes. Extra sections and typed notes stay untouched.
4. Saves preserve stable child IDs (`persistence-and-sync.md` § Edits preserve row identity).
5. Finite persisted domains are real Swift enums (`persistence-and-sync.md` § Schema hygiene).
6. `Recipe.originalSnapshot` uses the canonical recipe-transfer bundle shape (full Recipe row +
   structured children + tag/category names). There is no separate, lossy snapshot format.
7. A review that finds a data-preservation bug gets a regression test, covering at least stable IDs
   and the preservation of out-of-scope structured data.
8. Codex owns compiler and package verification, not simulator-driving or screenshot automation
   unless asked. Jon does the primary UI testing pass.
9. Verify lean, per [`docs/verification.md`](docs/verification.md).

## Data Preservation Rules

Import and editing preserve source fidelity (the general rule is jon-platform
`semantic-fidelity.md`):

1. Never discard original imported text: the `originalSnapshot` and each line's original text. The raw page
   HTML is not kept ([ADR-0010 Amd 1](docs/decisions/ADR-0010-cloudkit-sync-enablement.md#amendment-1--raw-import-html-is-not-kept-in-any-build-2026-10-13)).
2. Ingredient parsing preserves the original ingredient line.
3. Instruction cleanup preserves the original instruction text or source.
4. Imported source URLs are retained.
5. Import warnings and errors are visible.
6. Data that can't be parsed confidently is stored as text, not invented structure.

## Persistent Model Change Rule

Before changing persistent model types, explain what is changing and why, whether existing data
could be affected, whether a migration is required, and whether there is a simpler alternative.
Never casually rename or remove persisted fields. Yes Chef is on Production (`docs/PROD-CUTOVER.md`),
so jon-platform `persistence-and-sync.md` § Once an app is on Production applies too.

## Testing Expectations

Test logic: model creation, ingredient parsing, scaling, search, import parsing (fixtures in a
dedicated directory), shopping-list aggregation.
