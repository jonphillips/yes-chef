# AGENTS.md

## Project Identity

An Apple-first, private, local-first recipe management and cooking-planning app for serious
home cooks who collect, adapt, plan, shop, cook, and remember what worked. Paprika-inspired,
not a clone. The core is a single owner's private library (ADR-0003) — no
`Household`/`Cook`/sharing schema.

## House Style and Guidelines

Shared style and architecture live in `~/code/jon-platform` — start with its `AGENTS.md`.
Nothing here overrides it unless we discuss. If you cannot access it, stop and tell Jon.

**Progress reporting:** narrate exceptions, not routine — see jon-platform
`docs/agent-workflow.md` § "Progress reporting". **Token discipline:** noisy commands go
through `quiet-run` (same doc, § "Token discipline").

## Work Intake & Dispatch

The document shape is jon-platform ADR-0005, and the loop is `jon-platform/docs/agent-collaboration.md`.
The dispatch is **`docs/NEXT_UP.md`**: one ticket, and the executor's only planning input. The rest
have a home the executor doesn't load: candidates go in `docs/open-questions.md`, Jon's device passes
and held ops in `docs/device-passes.md`, and history in `docs/DONE-LOG.md`. Closed decisions live in
`docs/standing-guards.md`; read it when a dispatch touches what it guards. The reasoning behind the
rules below is in [`docs/work-intake.md`](work-intake.md).

1. **Dispatch trigger:** "go" (or *"do Next Up"*). Read `docs/NEXT_UP.md`, open the briefs it links,
   and implement that, nothing else. "comments posted" means: run `jon-platform/scripts/pr-verdicts`
   and address every `changes` verdict.
2. **Never infer the next task.** If `NEXT_UP.md` says `Nothing dispatched.` or is missing, STOP and
   ask Jon. Never pick from open questions, efforts, or milestones yourself.
3. **Curation is the architect's job.** The architect sets `NEXT_UP.md` in the plan PR that writes a
   brief or milestone, and the PR that completes a dispatch advances it in plan order. No PR exists
   only to move it.
4. **The ticket points, it does not duplicate.** `NEXT_UP.md` links brief and milestone sections; it
   doesn't re-spec them.
5. **Batch cohesive slices by default** (slices that share files and a mental model), decided at plan
   time. Keep a slice separate when it could be wrong or redirect the next. One dispatch = one PR.
6. **Keep `NEXT_UP.md` a ticket:** the ADR-0005 template, about 300 words, replaced wholesale, never
   appended to.
7. **Move, don't mark.** The completing PR adds a `DONE-LOG.md` entry naming its branch (and ticks
   any ledger box). Litmus: *a sentence describing finished work belongs in DONE-LOG.* Owed device
   passes go to `device-passes.md`, with a one-line pointer under **Owed**.

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

## Architecture Guidance

The house stack from jon-platform (`docs/ios/swift-style.md`, `persistence-and-sync.md`,
`ui-and-platforms.md` — read before proposing architecture): SQLiteData (**not SwiftData or
Core Data**), `@Observable` feature models with enum `Destination` navigation,
`@Dependency` for clock/date/UUID/database, value-type models, functional core with thin
views. Keep model, persistence, parsing/import, and UI separate; use the `pfw-*` skills for
library mechanics. No massive view files, hidden global state, speculative abstractions,
unexplained dependencies, or destructive data transformations.

Product and style background (recipe model, UI feel, import, AI, coding style, original MVP
scope) is in [`docs/product-principles.md`](product-principles.md) — read the relevant
section when the work touches it.

## Implementation Guardrails Learned From Pass 1

These are project rules, not preferences:

1. Composite detail reads use SQLiteData observation (`@Fetch` with a `FetchKeyRequest`) in a
   feature model — never one-shot `database.read` from `.task` into view `@State` (surfaces
   cancellation as errors; leaves detail stale after edits).
2. Non-trivial feature behavior lives in `@Observable @MainActor` models. Views bind and
   delegate; repository functions stay pure database operations taking an explicit `Database`.
3. Editor text blobs are an input surface, not permission to flatten the model. Until the editor
   is section-aware it owns only the first default ingredient section, the first default
   instruction section, and general notes; extra sections and typed notes stay untouched.
4. Saves preserve stable child IDs when content is unchanged — no routine delete-all/reinsert of
   lines, steps, notes, or join rows (sync churn, conflict risk).
5. Finite persisted domains are real Swift enums (`RawRepresentable`, `Codable`,
   `QueryBindable`), not strings.
6. `Recipe.originalSnapshot` uses the canonical recipe-transfer bundle shape (full Recipe row +
   structured children + tag/category names) — no separate lossy snapshot format.
7. A review that finds a data-preservation bug gets a regression test — at minimum stable IDs and
   preservation of out-of-scope structured data.
8. Codex owns compiler/package verification, not simulator-driving or screenshot automation
   unless asked. Jon does the primary UI testing pass.
9. **Verify lean:** `scripts/check-drift.sh` plus the relevant compiler build, then hand off.
   `check-drift.sh` runs SwiftLint, the package tests, and a `build-for-testing` of the app test
   target; a green package build or `swiftc -parse` is never evidence an App-layer change compiles.
   - A PR touching `YesChefApp/` runs the generic device build, **elevated/unsandboxed from the
     start**: `scripts/xcodebuild-summary.sh -scheme YesChef -destination 'generic/platform=iOS'
     -skipMacroValidation CODE_SIGNING_ALLOWED=NO build` (compile-only; no boot, no install).
   - The default Codex sandbox can SIGTERM `xcodebuild` before the compiler starts. That is an
     environment failure, not a result — never paste it as verification or treat it as leave to
     skip. No target permutations, simulator resets, or install attempts. If the elevated build
     still can't reach the compiler, report the log path and make the architect's local build a
     required approval gate; if it reports source errors, fix and rerun the same command.
   - A PR touching `YesChefApp/` **model** code also runs the `YesChefTests` app target on a
     simulator, elevated from the first attempt (never sandboxed first, never falling back to
     `swift test --filter`). Running a test target is not simulator-driving, so this narrows #8
     rather than contradicting it. View-only or copy changes don't need it. Exact commands:
     `docs/verification.md`.

## Data Preservation Rules

Import and editing preserve source fidelity:

1. Never discard original imported text.
2. Ingredient parsing preserves the original ingredient line.
3. Instruction cleanup preserves the original instruction text or source.
4. Imported source URLs are retained.
5. Import warnings and errors are visible.
6. Data that can't be parsed confidently is stored as text, not invented structure.

## Persistent Model Change Rule

Before changing persistent model types, explain what is changing and why, whether existing data
could be affected, whether a migration is required, and whether there is a simpler alternative.
Never casually rename or remove persisted fields.

## Testing Expectations

Run `scripts/check-drift.sh` from the repo root before committing code changes; use it instead of
broad "hunt for drift" sweeps, and keep code review scoped to the diff. Most work needs no
`xcodebuild` at all (guardrails #8/#9). When it does, go through `scripts/xcodebuild-summary.sh`,
never raw `xcodebuild` in chat; open the full log only to diagnose a failure.

Test logic: model creation, ingredient parsing, scaling, search, import parsing (fixtures in a
dedicated directory), shopping-list aggregation.

When completing a slice as the coding worker: commit, push, and open a PR for Jon as architect
unless told otherwise. Keep unrelated working-tree changes out. Use direct `gh` commands with
network escalation immediately, and `gh pr create --body-file` rather than a multiline `--body`
so saved permission prefixes match.
