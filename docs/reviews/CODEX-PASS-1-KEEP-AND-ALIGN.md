# Code Review — Codex Pass 1: Keep & Align

Companion to [CODEX-PASS-1-CHANGES.md](CODEX-PASS-1-CHANGES.md). This doc covers
two things:

1. **Keep** — what Codex did well and we should preserve as the exemplar.
2. **Align** — choices Codex made that aren't clearly covered by the current
   docs. These are the candidates to discuss; some may become edits to
   `~/code/jon-platform` (shared) or the app decision log (app-only).

---

## Keep — get this right, preserve it

### K-1. Clean functional core, separated and tested
`IngredientParser`, `InstructionParser`, `IngredientScaler`, `ServingParser`,
`RecipeRepository.totalTime` are pure static functions over value types
(`RecipeCore.swift:422-559`), with unit tests that use `expectNoDifference` and
deterministic UUID sequences (`RecipeCoreTests.swift`). This is exactly the
"functional core, observable shell" stance (swift-style §2/§6). The parsing and
scaling behavior matches DATA_MODEL §27 examples (parsed lines scale, unparsed
lines pass through unchanged).

### K-2. Schema as explicit, STRICT, UUID-PK SQL migrations
`Schema.swift` writes hand-authored `#sql` migrations with `STRICT` tables, UUID
text PKs, sensible indexes on FK columns, and `eraseDatabaseOnSchemaChange` gated
to DEBUG. This matches persistence-and-sync.md (UUID PKs everywhere; no unique
indexes beyond PK) and is the right migration discipline.

### K-3. Correctly applied the private-library relational model
Codex did **not** over-apply the CloudKit single-FK sharing law. Join tables
(`recipeTags`, `recipeCategories`, `recipeEquipment`) carry real FKs to both
sides with `ON DELETE CASCADE` — exactly what DATA_MODEL §2.6 / ADR-0003 call for
in a single-owner private library. It read the "this is *not* a co-edited shared
library" decision and modeled accordingly. Good sign it absorbed the ADRs.

### K-4. Dependencies, not singletons
`@Dependency(\.date.now / \.uuid / \.defaultDatabase)` throughout;
`prepareDependencies` bootstrap in the app and in previews; sample data seeded via
a dependency-scoped, idempotent (`fetchCount == 0`) write with a deterministic
UUID sequence. No singletons, no `*Current`. Matches swift-style §4 and gives
testable, previewable code.

### K-5. `markCooked` as a targeted atomic UPDATE
`RecipeCore.swift:302-309` increments `timesCooked` with a single
`UPDATE … SET timesCooked = timesCooked + 1` rather than read-modify-write. Race-
free and correct — exactly the lightweight "mark cooked" slice AGENTS.md /
DATA_MODEL §34 asked for, without introducing `CookingSession`.

### K-6. Write-once `originalSnapshot` capture logic
The `if recipe.originalSnapshot == nil { capture }` guard (`RecipeCore.swift:264`)
correctly makes the snapshot write-once on first save and preserves it across
edits — the §2.4 behavior. (The *format* is wrong — see CHANGES P1-4 — but the
capture *semantics* are right.)

### K-7. Mechanics
2-space indentation, small focused view files, sample data for previews, value-
type models, `Sendable`/`Equatable` conformances. The house mechanics are
followed.

---

## Align — decisions to discuss (then maybe doc edits)

These are the "things it did that we should talk about so everyone's aligned."
For each: the question, and where the resolution likely lands.

### A-1. Bless the stateless `RecipeRepository` as the persistence core?
Codex centralized all transactional save/load into `enum RecipeRepository` with
pure `static func …(in db: Database)` methods. That's genuinely good and testable
— arguably better than inlining DB code into each `@Observable` model. But the
current swift-style doc frames the choice as "logic in the View vs. logic in the
`@Observable` model" and doesn't mention a repository layer.

**Proposal to discuss:** ratify "pure repository functions that take a `Database`
are the *functional core of persistence*, called **by** feature models, never by
views." That keeps Codex's repository (just move the call sites off the views,
per CHANGES P1-1) and gives us a cleaner testability story than DB-in-the-model.
→ If we agree, this is a **jon-platform `swift-style.md` edit** (it's a general
pattern, not app-specific).

### A-2. How structured must the MVP editor be? (the blob question)
Codex's editor is text-blob in / re-parse out. CHANGES P0-2 flags the destructive
*persistence* as a real problem, but the *UX* — type ingredients as plain lines,
parse on save — may be the right MVP entry experience. DATA_MODEL as written
implies a more structured editor.

**Decision to make:** do we (a) accept blob-entry UX for MVP but fix the
persistence to be identity-preserving and non-lossy, or (b) move to a more
structured editor sooner? Either way the current code contradicts DATA_MODEL, so
this needs a written answer.
→ This is an **app decision-log entry** (app-specific product/UX call), and may
add a sentence to DATA_MODEL §27/§35 about the editing model.

### A-3. Reaffirm enums-over-strings for persisted columns, with the SQLiteData recipe
Codex reached for `String` columns (CHANGES P1-3). Two agents diverging here
suggests the docs don't make the *mechanism* obvious: the house wants enums, and
the SQLiteData way is `enum X: String, QueryBindable`. The stance exists
(swift-style §3) but the how-to for persisted enum columns isn't spelled out.

**Proposal:** add a short "persisted enums" note (enum + `String` raw +
`QueryBindable`) to the `pfw-sqlite-data` skill or persistence-and-sync.md so
neither agent reaches for `String` again.
→ Likely **jon-platform / skill** edit.

### A-4. Make the observation pattern impossible to miss
Codex — a capable agent — still hand-rolled `database.read`-into-`@State` and got
bitten by `CancellationError` (CHANGES P0-1). That's the single biggest failure
in the pass, and it's a *discoverability* problem: the docs say "use `@FetchAll`/
`@FetchOne`" but don't say loudly "**never** put `database.read` in a `.task` to
populate `@State` — that's the anti-pattern, and here's why (cancellation +
staleness)."

**Proposal:** add an explicit anti-pattern callout to persistence-and-sync.md (or
the skill): "Reads are observed via `@Fetch`/`@FetchAll`/`@FetchOne`. A manual
`database.read` in `.task` storing into `@State` is a bug, not a style choice — it
surfaces `CancellationError` and goes stale on writes." Cheap insurance against
the most expensive mistake in this review.
→ **jon-platform** edit (general, bites every app on this stack).

---

## Suggested next step

Walk A-1…A-4 together and decide which become jon-platform edits vs. app
decision-log entries. Then I can do the P0/P1 changes in CHANGES as a single
focused pass (the `@Fetch` conversion + feature models is the backbone; the rest
hangs off it).
