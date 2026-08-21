# LLMHandoffKit convergence recon — yes-chef

**Question:** should yes-chef adopt `jon-platform/packages/LLMHandoffKit` (the shared
external-LLM handoff spine, landed on jon-platform `main` at `7e5b3d4`), the way galavant
does — the "consumer #1 convergence" flagged in galavant ADR-0036?

**Read-only design pass.** No yes-chef Swift changed. Author: architect recon, 2026-08-16.

## Resolution — Path A shipped ([PR #309](https://github.com/jonphillips/yes-chef/pull/309), 2026-08-16)

The gate below (§4, "is graceful stale-marker tolerance wanted in yes-chef?") resolved **yes**;
Jon dispatched the build and **Path A** landed exactly as scoped — only `HandoffContractMarker`
was lifted, nothing else:

- **Marker engine only.** `AIHandoffReturnContract` now wraps
  `LLMHandoffKit.HandoffContractMarker(prefix: "YC-CONTRACT", version: "v3")`. The router
  (`AIHandoffToken.stripping`), the `AIHandoff` `@Table`, `Learning`, and every domain type are
  untouched — the persistence fork (§2) and the return-model fork (§3) were left alone, as the
  recon recommended. The package's galavant router / UserDefaults store / `HandoffCandidateLink`
  never entered yes-chef's build.
- **Version normalized decimal `2.1` → integer `v3`.** The package compares the *leading integer*
  of the marker, so the old decimal was folded to an integer token; an old `YC-CONTRACT: v2.1`
  return now parses as `2 < 3` (older ⇒ import-with-warning), and a future bump stays integer `vN`.
- **Tolerance semantics.** Missing/older marker ⇒ import anyway, carrying a non-blocking warning to
  the review surface (App Intents, in-app review, reader-feedback capture, new-recipe path); current
  `v3` ⇒ silent; *newer* marker ⇒ hard stop (the one case where decoding could misread a future
  schema — consistent with [ADR-0040](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md)
  lossless-or-loud, the JSON decode being the real guard).
- **Blocker #1 (galavant identity) handled at the seam, not in the package.** yes-chef passes the
  marker's *default neutral* `remediation` copy for warnings, and **translates** the package's
  galavant-worded `HandoffContractError` into its own `AIHandoffReturnContractError.instructionsOutOfDate`
  — so no "Galavant"/"Settings" copy reaches a yes-chef user. The package itself is still
  galavant-named internally (router, store, `unsupportedMarker` copy); **Path B (full de-galavant)
  stays deferred** per §4 — revisit only if a third consumer appears.

Recorded as [ADR-0042 Amendment 5](decisions/ADR-0042-workbench-handoff-and-the-return-block.md#amendment-5--the-return-contract-marker-is-the-first-lift-from-llmhandoffkit-tolerant-not-strict-2026-08-16).
**One consequence to watch (flagged to Jon):** the tokenless bare-JSON reader-feedback shortcut now
always shows the "missing contract marker" footnote, because that path by design carries no marker —
a mild false-positive on an otherwise-legitimate paste. Left as-is pending a dogfood read.

## Headline (read this first)

**The package is not the domain-free spine its own doc comment claims — it is
galavant-shaped and galavant-*named*.** So "yes-chef adopts LLMHandoffKit" is not a
WebExtractorKit-style rewire. It is really **two** projects: (1) *generalize the package*
so it is genuinely app-neutral, then (2) adopt the thin slice that actually overlaps. And
the overlap is **smaller than the ADR-0036 framing implies** — after you set aside the
galavant-specific bits, the only piece yes-chef would genuinely *gain* is one ~40-line
version-tolerant contract-marker stripper.

Three hard blockers, each proven below:

1. **The package hardcodes galavant identity.** `GV-HANDOFF:` / `GV-CONTRACT:` tokens,
   user-facing error copy that says "Galavant" and "Settings", and — the smoking gun — a
   literal `tripIdeaID: UUID?` field on `HandoffCandidateLink`. A package with a trip field
   in it is not domain-free.
2. **The persistence substrates fork.** The package persists sessions as a **UserDefaults
   JSON blob** (`HandoffSessionStore`). yes-chef persists `AIHandoff` as a **SQLiteData
   `@Table("aiHandoffs")`** with a real migration and indexes. Adopting the package's store
   would *downgrade* yes-chef's storage.
3. **The return model differs.** The package models a **candidate-row import**
   (`candidatePayload` + `[HandoffCandidateLink]`, `status.imported` = "row touched") — that
   is galavant's "return candidate places as TripIdeas" semantics. yes-chef's return is a
   **prose deliverable + a synced `Learning` distillation**; it has no candidate-import
   concept at all.

**Recommendation up front: Path A (lift only the pure text helpers) or defer.** Do not
force a shared record type — it would leak *both* domains into the package (it already leaks
galavant's). Detail and alternatives below.

## 1. Type-by-type mapping

| LLMHandoffKit (package) | yes-chef equivalent | Verdict |
|---|---|---|
| `HandoffSession` (Codable value, UserDefaults-persisted) | `AIHandoff` (`@Table`, SQLite-persisted, **not** synced) | **Semantically different** — near-identical *fields* (id/sourceType/sourceID/taskType/createdAt/importedAt/status/schemaVersion/exportedPrompt), but different persistence substrate and yes-chef adds `dayOffset`, `variationID: RecipeVariation.ID`, `regenerates`. |
| `sourceType: String` / `taskType: String` (opaque tokens) | `AIHandoffSourceType` (5 cases) / `AIHandoffTaskType` (13 cases), both domain enums w/ `title` | **Superset (yes-chef).** The package generalized these to `String`; that is the *one* real generalization it made. yes-chef's are richer and typed. |
| `HandoffStatus` { awaitingReturn, imported } | `AIHandoffStatus` { awaitingReturn, imported, **discarded** } | **Superset (yes-chef).** |
| `HandoffCandidateLink { candidateID, tripIdeaID }` | *(none)* | **No equivalent — and galavant-domain.** `tripIdeaID` is a trip field. yes-chef has no handoff-candidate concept (the `candidateLinks` in `WorkbenchCore` is an unrelated workbench feature). |
| `HandoffSession.candidatePayload: String?` | *(none)* | **No equivalent.** yes-chef returns deliverable prose + `Learning`s, not a candidate payload. |
| `HandoffRouting.route(_:)` → `RoutedText` (strip `GV-HANDOFF:` line, extract UUID) | yes-chef's own router + `AIHandoffToken.header`/token parsing | **Overlapping concept, forkable.** Same shape; generalizable *iff* the `GV-HANDOFF:` prefix is parameterized. |
| `HandoffContractMarker.strippingMarker(from:)` — **version-tolerant** (missing/older ⇒ advisory warning; newer ⇒ hard stop) | `AIHandoffToken.strippingMarker(from:)` — **strict** (any non-exact marker ⇒ `nil`) | **Real overlap, package is better.** This is the one place the package offers yes-chef something it lacks: graceful version tolerance. ~40 lines, pure. |
| `HandoffContractResult` / `HandoffContractError` / `HandoffRoutingError` | inline `nil`/bool returns | **No equivalent** (yes-chef uses lighter signaling). Would come along with the marker helper. |
| `HandoffSessionStore` (UserDefaults blob, `save`/`session`/`sessions` closures) | direct SQLite reads/writes on `aiHandoffs` | **Semantically different / regression risk.** See §2. |
| *(none)* | `Learning` (`@Table`, **CloudKit-synced**) + `LearningProvenance` + `LearningOrdering` (sparse-rank reorder) | **No equivalent — yes-chef-only.** The durable, synced output of a handoff. The package has no "learnings" notion. |
| *(none)* | `AIHandoffToken.DeliverableFormat`, the `YC-LEARNINGS:` section parser, `PlaybookSectionKind`, ~20 `AIHandoff*` review files | **No equivalent — yes-chef domain.** |

## 2. The persistence question (the crux)

This is where a naive "adopt it" goes wrong.

- **Package:** `HandoffSession` is a hand-rolled `Codable` value; `HandoffSessionStore.liveValue`
  serializes a `[UUID: HandoffSession]` dictionary into a **single UserDefaults key**
  (`"GalavantDeviceLocalHandoffSessions"`). Device-local, not synced, not queryable.
- **yes-chef:** `AIHandoff` is `@Table("aiHandoffs")` with a migration (`Schema.swift:845`),
  altered twice since (`:996`, `:1080`), and is **device-local but not CloudKit-synced** —
  confirmed: `aiHandoffs` is *absent* from `makeSyncEngine`'s `tables:` list
  (`CloudSync.swift:132`), while `Learning.self` *is* present (`:168`). So yes-chef already
  made the same "sessions are ephemeral/device-local, the distilled output syncs" call —
  it just implemented the session side as a proper SQLite table, not a blob.

**They agree on the semantics (session = device-local, output = synced) and disagree on the
substrate.** Reconciling means one of:

- **(a)** yes-chef swaps its `aiHandoffs` table for the package's UserDefaults store — a
  **regression** (loses SQL queryability, migrations, the existing rows) for zero benefit.
  Reject.
- **(b)** yes-chef keeps its table and provides a *SQLite-backed* `HandoffSessionStore.liveValue`.
  Feasible — the store is a struct of closures — **but** then the stored value must be
  `HandoffSession`, whose fields are a subset of `AIHandoff` (no `dayOffset`/`variationID`/
  `regenerates`), so yes-chef either (i) drops those fields, or (ii) wraps/side-cars them.
  Net: real friction, thin payoff.
- **(c)** the package stops shipping a concrete store and instead defines a store *protocol*
  (or leaves the store entirely to the app). Cleanest, but it is a **package redesign**, i.e.
  a jon-platform PR, not a yes-chef PR.

There is no shim that makes (b) clean while yes-chef keeps its richer `@Table`. The
persistence fork is genuine.

## 3. Domain boundary — what could ever be shared

**Irreducibly yes-chef (must stay in `YesChefCore`):** `AIHandoffSourceType`,
`AIHandoffTaskType`, `dayOffset`, `variationID`, `regenerates`/`prepPlanIntent`,
`DeliverableFormat`, `Learning`/`LearningProvenance`/`LearningOrdering`, the `YC-LEARNINGS:`
parsing, `PlaybookSectionKind`, and every `AIHandoff*Review` type.

**Irreducibly galavant (must leave the package if it is ever truly neutral):**
`HandoffCandidateLink.tripIdeaID`, `candidatePayload`, the `GV-` token strings, the
"Galavant"/"Settings" error copy, the `"GalavantDeviceLocal…"` storage key.

**The genuinely neutral intersection — the only real lift target:**
1. Token routing: "find the token line, pull the UUID, return the body without it" —
   parameterized by prefix.
2. **Version-tolerant contract-marker stripping** (`HandoffContractMarker` +
   `HandoffContractResult` + `HandoffContractError`) — parameterized by prefix/version.

That intersection is ~2 small pure types. Everything else is one app's domain or the other's.

## 4. Recommended slicing

**Path A — lift only the pure text helpers (recommended first move, if any).**
1. jon-platform PR: make `HandoffRouting` and `HandoffContractMarker` **prefix-parameterized**
   and strip galavant copy out of them (`route(prefix:_:)`, marker already takes prefix/version;
   move the "Galavant/Settings" strings out to caller-supplied text). Delete `tripIdeaID` and
   `candidatePayload`/`HandoffCandidateLink` from the neutral core — those belong to galavant's
   *consumer*, not the spine. (This also repays galavant's own tech debt: its "shared" package
   is currently not shareable.)
2. yes-chef PR: replace `AIHandoffToken.strippingMarker`/router internals with the neutral
   helpers, **gaining version tolerance** (missing/older marker ⇒ import with a warning instead
   of hard `nil`). Keep `AIHandoff` `@Table`, `Learning`, and all domain types exactly as-is.
   Behavior change is limited and *improving* (more forgiving paste handling) — but it touches
   the return-parse path, so it wants the existing handoff round-trip tests green + a manual
   paste-a-stale-contract check.

   *Risk note:* yes-chef's current strict behavior (stale marker ⇒ reject) may be
   **intentional**. Confirm with Jon that "import anyway with a warning" is desired before
   swapping — this is a product call, not a mechanical one.

**Path B — properly generalize the package, both apps consume the neutral core.**
The "real lift": prefix-parameterize tokens, remove galavant domain, turn `HandoffSessionStore`
into a protocol both a UserDefaults *and* a SQLite backing satisfy, keep `HandoffSession` a pure
value each app can blob or table. This is the honest end-state but it is a **jon-platform
package-redesign project**, disproportionate to a session-tracking record two ~200-person-hour
apps each already have working. Only worth it if a *third* consumer appears.

**Path C — do not converge (also legitimate).** The shared value is one marker-stripper. The
record shapes rhyme but their substrates and domains differ enough that a forced shared type
leaks both domains into the package. Accept two parallel spines; revisit if the roster grows.

**My call:** **Path A, gated on the product question** (is graceful stale-marker tolerance
wanted in yes-chef?). If yes, it is a tidy two-PR dedup that *also* de-galavant-ifies the shared
package. If the honest answer is "the strict reject is intentional and the marker helper is the
only overlap," then the payoff is a single pure function and **Path C (defer) is the right call**
— say so and stop, rather than manufacturing a convergence. This is *not* the WebExtractorKit
rewire; the ADR-0036 "consumer #1" framing over-promised, because the package was lifted from
galavant with galavant's idioms intact rather than as a neutral spine.

## Appendix — evidence pointers

- Package galavant-isms: `LLMHandoffKit/Sources/LLMHandoffKit/HandoffSession.swift` — `GV-HANDOFF:`
  (`header`, `route`), `tripIdeaID` (`HandoffCandidateLink`), "Galavant" copy (errors),
  `"GalavantDeviceLocalHandoffSessions"` (store key), UserDefaults store (`liveValue`).
- yes-chef persistence: `AIHandoff.swift:4` (`@Table("aiHandoffs")`); `Schema.swift:845/996/1080`
  (migrations); `CloudSync.swift:132–168` (`aiHandoffs` absent from synced `tables:`, `Learning.self`
  present).
- yes-chef tokens/return: `AIHandoff.swift:531` (`YC-HANDOFF:`), `:619` (`YC-CONTRACT: v{version}`),
  `:637` (strict `strippingMarker`), `:163` (`Learning` synced `@Table`), no `candidatePayload`.
