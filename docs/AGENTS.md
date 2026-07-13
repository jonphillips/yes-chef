# AGENTS.md

## Project Identity

This project is an Apple-first personal recipe management and cooking-planning app.

It is inspired by Paprika-style recipe management but is not intended to be a direct clone. The goal is to build a modern, private, local-first app for serious home cooks who collect, adapt, plan, shop, cook, and remember what worked.

## House Style and Guidelines
Shared style and architectural guidelines are available in ~/code/jon-platform directory. Start with AGENTS.md there. Nothing in this document should override those guidelines unless we discuss. If you cannot access this directory and information, you must alert me.

**Progress reporting:** narrate exceptions, not routine. Default to silence while an expected build/test/command runs — no per-phase heartbeats. Speak up for blockers, surprises, decision points, deviations, and failures. See `~/code/jon-platform/docs/agent-workflow.md` § "Progress reporting".

## Work Intake & Dispatch

There is **one front door** for "what do I work on": `docs/CURRENT_HANDOFF.md`. Work flows
through a single funnel, not two competing plans:

```
docs/open-questions.md  → ideas, unscoped (e.g. comment ingestion)
docs/milestones/*.md    → the strategic arc/plan (milestones + ordered slices; the sync gate)
docs/efforts/*.md       → scoped, ready-to-build briefs (a milestone slice OR an off-arc item)
docs/CURRENT_HANDOFF.md → the dispatcher: Next Up (one item) + Ready Efforts (the queue)
a pull request          → the handoff out
```

An **"effort"** is the executable unit of work. It is the generalization of a milestone-slice
handoff to also cover work the milestone arc cannot express (defects, spin-offs). A milestone
slice, when approved to build, *becomes* an effort — usually a thin pointer
("M3 Slice 6 — build per the milestone doc §Slice 6, plus these deltas"), never re-specced.

`CURRENT_HANDOFF.md` has two distinct parts:

- **Next Up** — the single dispatch target. Usually one designated effort with a pointer to its
  brief, but it **may bundle several cohesive slices** into one dispatch (one PR) — see the batching
  rule below. Either way it is *one* dispatch. Jon and the architect curate it; the coding agent
  never chooses it.
- **Ready Efforts** — the ordered queue of scoped, ready briefs. Not a dispatch target; it is
  where Next Up is drawn from.

Rules:

1. **Dispatch trigger.** Jon dispatches with: *"Do the Next Up effort in `docs/CURRENT_HANDOFF.md`."*
   The coding agent reads `Next Up`, opens the referenced brief, and implements that — nothing else.
2. **Never infer the next task.** If `Next Up` is empty, missing, or ambiguous, **STOP and ask
   Jon.** Do not pick from Ready Efforts, the milestone doc, or anywhere else on your own.
3. **Curation is the architect's job.** When an effort merges or a slice is approved, the
   architect proposes the promotion and writes the new `Next Up` pointer + brief. Detail lives in
   the effort brief (or the milestone slice it points to), not in chat.
4. **The handoff points, it does not duplicate.** For slices already specced in a milestone doc,
   the brief references that section rather than copying it, so there is one source of truth.
5. **Batch cohesive slices by default.** Each dispatch pays a large fixed tax — cold-start, reading
   the house rules, re-exploring the codebase, and PR ceremony — that scales with the *number of
   dispatches*, not the amount of work. So the architect's default when curating Next Up is to
   **bundle cohesive slices into one dispatch/PR**, decoupling review granularity (stay fine) from
   dispatch granularity (amortize). Bundle when slices **share files and a mental model**; keep them
   separate when a slice has a real chance of being wrong or of changing direction based on a prior
   slice's outcome (batching is amortization — only a win when the whole batch is likely right). When
   a dispatch bundles slices, Next Up lists them in order and the agent does all of them under one PR.
   The architect still thinks and reviews at slice resolution.
6. **Keep the handoff lean; archive the rest.** `CURRENT_HANDOFF.md` holds only Next Up, the Ready
   queue, and the Verification Pattern. Completed-slice history, the implemented-behavior checkpoint,
   and strategic background live in `docs/DONE-LOG.md` (append-on-approval, read-rarely). No dispatch
   instruction points at `DONE-LOG.md` — it is a human archive, kept out of working context on purpose.
7. **On approval, MOVE — don't mark.** "Mark done" is the leak that bloats the handoff into a
   changelog. When a slice/effort is approved, the completed write goes to `DONE-LOG.md` (newest
   first) **and the corresponding block is deleted from `CURRENT_HANDOFF.md`** — both riding the same
   approved PR branch. The handoff only ever gains a **forward** edit (advance Next Up, draw the next
   effort from Ready); it never gains a backward one. **Litmus test:** *if the sentence you're adding
   to `CURRENT_HANDOFF.md` describes finished work, it belongs in `DONE-LOG.md` instead.* A "✅ DONE"
   line, a celebratory header, or an "earlier and logged" PR recitation left in the handoff is a
   process bug, not a record. The one exception: an **owed-but-non-blocking** verification (a device
   or CloudKit gate) stays as a single-line debt under Next Up until Jon clears it — not as a
   done-narrative.

## Development Priorities

Follow these priorities in order:

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

## Current Product Scope

The initial app should support:

- Recipe list
- Recipe detail
- Recipe creation/editing
- Ingredients
- Instructions
- Notes
- Tags
- Categories
- Search
- Recipe scaling
- Cooking mode
- Sample data
- Future import from Paprika export

Do not build the following unless explicitly requested:

- User accounts
- Server backend
- Social sharing network
- Public recipe feed
- Nutrition tracking
- Subscription/payment infrastructure
- Android app
- Web app
- Complex AI recipe generation
- OCR
- Voice assistant

## Architecture Guidance

Use the house Apple-native stack defined in `~/code/jon-platform` (read
`docs/ios/swift-style.md`, `persistence-and-sync.md`, and `ui-and-platforms.md`
before proposing architecture). In short:

- SwiftUI multiplatform for UI
- `@Observable` feature models + swift-navigation enum `Destination` for
  navigation/sheets (no `isShowingX` boolean soup)
- SQLiteData (Point-Free) for persistence — local SQLite is the source of truth.
  **Not SwiftData, not Core Data.**
- swift-dependencies (`@Dependency`) for clock/date/UUID/database — no singletons
- Value-type domain models; make impossible states unrepresentable with enums
- Functional core (pure functions), thin views; non-trivial save/load logic lives
  in a model, never in a View
- Sample data for previews
- Separation between model, persistence, parsing/import, and UI
- swift-testing + CustomDump for tests of non-trivial logic
- Use the installed `pfw-*` skills (sqlite-data, dependencies, swift-navigation,
  modern-swiftui, testing) for library mechanics

Avoid:

- Massive SwiftUI view files
- Hidden global state
- Unnecessary abstractions
- Unexplained dependencies
- Networking unless required
- Backend assumptions
- Destructive data transformations

## Implementation Guardrails Learned From Pass 1

These are now project rules, not preferences:

1. Composite detail reads must use SQLiteData observation (`@Fetch` with a
   `FetchKeyRequest`) in a feature model. Do not do one-shot async
   `database.read` calls from `.task` just to populate view `@State`; that can
   surface normal task cancellation as user-facing errors and leaves detail
   screens stale after edits.
2. Non-trivial feature behavior belongs in `@Observable @MainActor` models.
   Views bind to model state and delegate actions; repository functions remain
   pure database operations that accept an explicit `Database`.
3. Editor text blobs are an MVP input surface, not permission to flatten the
   stored model. Until the editor has section-aware UI, it owns only the first
   editable/default ingredient section, the first editable/default instruction
   section, and general notes. It must leave extra sections and typed notes
   untouched.
4. Saves must preserve stable child IDs whenever content is unchanged. Do not
   delete-all/reinsert ingredient lines, instruction steps, notes, or join rows
   as a routine edit strategy; this creates avoidable sync churn and future
   conflict risk.
5. Finite persisted domains must be real Swift enums (`RawRepresentable`,
   `Codable`, `QueryBindable`) rather than strings or static string namespaces.
6. `Recipe.originalSnapshot` must use the canonical recipe-transfer bundle
   shape: full Recipe row plus structured children and tag/category names. Do
   not introduce a separate lossy display-only snapshot format.
7. Add regression tests when a review identifies a data-preservation bug. At a
   minimum, test stable IDs and preservation of out-of-scope structured data.
8. Codex owns compiler/package verification and should not spend project time on
   brittle simulator-driving or screenshot automation unless explicitly asked.
   Jon will do the primary UI testing pass, even when that makes the loop slower.
9. Verify lean by default: build once + `scripts/check-drift.sh`, then hand off. Do **not**
   install/launch on simulators as a routine step — that build/install loop is the main time
   cost and Jon does the device pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`
   regardless. Only boot/install a simulator when a change can't be confirmed from build +
   tests, and say why. See the Verification Pattern in `CURRENT_HANDOFF.md`.
   **Fail fast — one attempt, then stop.** A simulator that won't boot/install, or any Xcode/
   toolchain trouble, is **never** a reason to retry with alternate incantations (different
   `-destination`, `simctl erase`/`boot`, flag permutations). Make **one** attempt at the
   required build; if it fails, paste the error and **stop** — do not try to repair the
   toolchain or the simulator. Booting/installing sims is Jon's device pass, not a Codex problem
   to grind on. Endless build/install retries are the specific token-and-time sink this rule exists
   to prevent.

## Data Preservation Rules

Recipe import and editing must preserve source fidelity.

Rules:

1. Never discard original imported text.
2. Ingredient parsing should preserve the original ingredient line.
3. Instruction cleanup should preserve original instruction text or source.
4. Imported source URLs should be retained.
5. Import warnings and errors should be visible.
6. If data cannot be parsed confidently, store it as text rather than inventing structure.

## Persistent Model Change Rule

Before changing persistent model types, explain:

- What model is changing.
- Why it needs to change.
- Whether existing data could be affected.
- Whether a migration is required.
- Whether there is a simpler alternative.

Do not casually rename or remove persisted fields.

## Testing Expectations

Before committing code changes, run `scripts/check-drift.sh` from the repository root
when feasible. It runs the focused SwiftLint drift gate from jon-platform's
`docs/ios/drift-control.md` and the Swift package tests. Use it instead of scheduled
or broad "hunt for drift" sweeps; code review should stay scoped to the diff.

`check-drift.sh` runs `swift test` and covers the default slice — most work needs no
`xcodebuild` at all (see guardrails #8/#9). Only run an app build when a change carries
real app/UI compile risk, and when you do, run it through `scripts/xcodebuild-summary.sh`
(same args as `xcodebuild`), never raw `xcodebuild` in chat. The wrapper writes the full
log to a file and surfaces only errors/warnings/verdict, so build noise stays out of
context. Reach for the raw, unfiltered log only while actively diagnosing a compiler
failure.

When completing a milestone slice as the coding worker, finish the handoff by committing,
pushing the branch, and opening a pull request for Jon as architect unless explicitly told
not to. Keep unrelated working-tree changes out of the slice PR. Use direct `gh` commands
for GitHub operations, run them with network escalation immediately, and prefer
`gh pr create --body-file` over shell-wrapped multiline `--body` arguments so saved
permission prefixes match cleanly.

Add tests for:

- Recipe model creation.
- Ingredient parsing.
- Recipe scaling.
- Search behavior.
- Import parsing.
- Shopping-list aggregation when implemented.

For import tests, use fixtures in a dedicated test fixture directory.

## Recipe Model Philosophy

Ingredient lines should support both original text and parsed fields.

Example:

Original:

`2 tablespoons finely chopped fresh rosemary`

Parsed:

- quantity: 2
- unit: tablespoon
- item: fresh rosemary
- preparation: finely chopped

But the original text must remain available.

Do not over-normalize early. Recipe data is messy. Prefer a tolerant model.

## UI Philosophy

The app should feel:

- Modern
- Calm
- Fast
- Serious
- Kitchen-friendly
- Private
- Personal

Cooking screens should prioritize readability and low friction.

Useful qualities:

- Large typography
- Clear ingredient sections
- Clear instruction steps
- Easy notes access
- Minimal clutter
- Screen awake during cooking mode

Avoid gimmicky UI.

## Import Strategy

The app should eventually import user-owned Paprika data.

Before implementing full import:

1. Inspect a real sample export.
2. Document the file structure.
3. Build a parser for a small fixture.
4. Preserve all original data.
5. Add tests.
6. Report import warnings.

Do not assume Paprika’s format before inspecting a sample.

## AI Strategy

AI features are future enhancements, not MVP foundation.

Good future AI features:

- Clean imported recipe text.
- Parse ingredients.
- Extract prep tasks.
- Suggest make-ahead plan.
- Generate cooking timeline.
- Identify shopping categories.
- Flag equipment conflicts.
- Suggest substitutions based on explicit user preferences.

Bad early AI features:

- Generic recipe generation.
- Unreviewed automatic rewriting.
- Confident nutrition guessing.
- Destructive normalization.
- Hidden transformations.

## Coding Style

Prefer:

- Clear names
- Small files
- Small views
- Explicit model relationships
- Simple functions
- Tests for logic
- Preview data
- Comments where they clarify non-obvious choices

Avoid:

- Cleverness
- Framework churn
- Unnecessary packages
- Large architectural rewrites
- Silent behavior changes

## First Implementation Target

Build a minimal but real recipe library:

1. Define core models (plain structs, UUID PKs — a single owner's private library, no
   shared graph; see DATA_MODEL.md §2.6):
   - Recipe (plain `favorite`/`rating` columns; a write-once `originalSnapshot` blob
     captured on first save — see DATA_MODEL.md §2.4)
   - RecipeSource (separate table linked by `recipeID`, not flattened onto Recipe)
   - IngredientSection
   - IngredientLine
   - InstructionSection
   - InstructionStep
   - RecipeNote
   - RecipePhoto
   - Tag
   - Category
   - Equipment
   - RecipeTag, RecipeCategory, RecipeEquipment (joins, real FKs both sides)

2. Add sample data.

3. Build screens:
   - Recipe list
   - Recipe detail
   - Recipe editor

4. Add:
   - Search
   - Tag/category display
   - Favorite flag (a plain column on the recipe)
   - Tagging
   - View original version, read-only (from the frozen `originalSnapshot`)
   - Basic scaling display
   - Cooking mode shell
   - Meal-planner-ready cooking memory: keep `lastCookedAt`/`timesCooked` in the
     schema, but do not expose a manual "mark cooked" or retrospective-note flow
     in the first slice. The meal calendar will later update/derive last-cooked
     history from planned meals whose dates have passed.

Do not implement CloudKit sync, recipe transfer (send/Family Cookbook), production
import UI, grocery list, meal planning, pantry, or AI in the first coding pass unless
specifically requested. A Paprika fixture spike may happen early to validate the schema,
but it is not a shipped import flow.

There is no `Household`/`Cook`/sharing schema to build — the core is a single owner's
private library (ADR-0003).
