# Effort — Cockpit → Yes Chef recipe Find handoff (receiver side)

Status: Compute slice complete; return transport and multi-admit deferred
Summary: Receive raw Cockpit Find referrals, isolate 0/1/N recipes for Create Recipe review, and emit a typed verdict through the deferred return-transport seam.
Related: Cockpit M6 Gate 5 slice plan (`cockpit/docs/milestones/M6-gate5-find-handoff-slice-plan.md`)

> **Ready-to-build brief for the Yes Chef executor.** Authored 2026-09-21 from the Cockpit side as the
> receiver half of Cockpit's M6 Gate 5 (first specialist Find handoff). The **contract is the only
> coupling** and is frozen jointly; everything else here is Yes Chef's to build and Yes Chef owns all
> recipe intelligence. Cockpit-side companion: `cockpit/docs/milestones/M6-gate5-find-handoff-slice-plan.md`
> (rationale in `…/M6-gate5-find-handoff-design.md`). Fit this into `docs/CURRENT_HANDOFF.md` /
> `docs/efforts/` per the normal intake funnel — it is plausibly ADR-worthy (App-Intent contract with an
> external app); assign a number if you agree.

## What this proves (and the boundary)

Yes Chef becomes the **first real receiver** of a cross-app Find referral. Cockpit sends **raw text +
provenance + a fallible "this looks like a recipe" hint** and nothing more. **All** domain intelligence
is yours: parsing, LLM extraction, recipe-cardinality (0/1/N), dedup, merge, admission, and — critically —
the **decline**. A decline (including "duplicate") is a first-class, valuable outcome, not an error: it is
the quality signal extraction has never had. Cockpit never learns recipe schema and never pre-trims to
"the recipe" — you receive the whole readable body (newsletter chrome and all) and decide what's in it.

## The contract (frozen jointly — do not drift unilaterally)

- **Initiate (Cockpit → Yes Chef): a foregrounding App Intent.** Extend the existing
  `CaptureRecipeFromText` (`YesChefApp/AppIntents/CaptureRecipeFromTextIntent.swift`,
  `allowedExecutionTargets: .main`) — **do not fork a parallel intent** — to also accept:
  - `rawText: String` — the whole readable body. **Never assume it is one clean recipe.**
  - `provenance` — source sender/publisher, arrival date, `List-ID`/series, an **opaque** Cockpit
    ContentPiece token (round-trip it untouched), Cockpit's why-it-mattered note, lightweight hints.
  - `referralID: String` — opaque correlation token. **Machine-only. Never surface it to the cook.**
  It opens into your Create Recipe / review UI with the context loaded, and the cook finishes **now**,
  in the moment, with context fresh (not a queue drained later).
- **Return (Yes Chef → Cockpit): a background App Intent that Cockpit exposes and you invoke** at the
  moment of admit/decline, keyed by `referralID`. It is the reverse of your own `ImportHandoffResult`
  pattern, cross-app. It carries a **set-valued** verdict:
  - for each recipe you admit: `admitted(recipeRef)`;
  - or, for the whole referral: `declined(reason)` / `duplicate`.
  One referral may yield **N admitted + M declined**. No id is ever shown to the cook. Cockpit resolves
  its Find from this on its own — the cook does zero housekeeping on either side.

**Not** a `ReturnsValue` App Intent (the verdict lands minutes later, after the cook finishes — it can't
ride the initiating intent's synchronous return). **Not** a shared store, App Group, CloudSyncKit, or any
family HandoffKit — this is receiver #1; shared infra waits for repeated consumers.

## Deltas to build

### S-y1 — Extractor accepts messy/large input and isolates 1..N recipes
Today `RecipeExtractionClient.extract(text:)`
(`YesChefPackage/Sources/YesChefCore/RecipeExtractionClient.swift`) takes one `String`, returns **one**
`RecipeExtraction`, and throws `.emptyRecipe` when it finds no ingredients/instructions. Upgrade it from
"paste one clean recipe" to "**find the recipe(s) in a big block**":
- 0 recipes → clean decline (feeds the return's `declined`), not a thrown failure that strands the cook.
- 1 → extract as today.
- N → isolate each; the cook picks/confirms in the review UI.
This is a capability upgrade you want regardless — it improves the manual paste path too.

### S-y2 — Receive the referral and emit the verdict
- Extend `CaptureRecipeFromText` with `provenance` + `referralID`; thread them through the Create Recipe
  coordinator so review has the context and the `referralID` is retained for the return.
- On save (per admitted recipe) and on decline/dismiss, invoke Cockpit's return App Intent with the
  set-valued verdict keyed by `referralID`.
- **Custody stays per-app (ADR-0002 D8 across the app line):** the referral is an *admission request, not
  shared ownership*. Never move, mutate, or delete anything on Cockpit's side; the Yes Chef recipe is a
  wholly separate record with its own custody.

This receiver slice deliberately admits **one selected candidate per referral**. The `FindVerdict` shape
remains set-valued for the eventual multi-admit contract, but this Create Recipe review UI is pick-one-of-N
and clears the referral after the first admitted save. Cockpit must not depend on receiving N admitted
outcomes until a follow-up multi-save UI slice lands; unselected candidates are intentionally not reported
as declines.

## Guardrails / first checks

- **Reuse, don't reinvent:** the foregrounding `.main` pattern (`CaptureRecipeFromText`) and the
  keyed-ingest pattern (`ImportHandoffResult` in `YesChefApp/AppIntents/HandoffIntents.swift`) are the
  right templates.
- **Do NOT reach for the `AIHandoff` token types** (`AIHandoffToken` / `AIHandoffReturnContract` /
  `AIHandoffIntentImport`). That machinery is your **outboard-to-external-chat** axis (copy prompt / paste
  result); this is app-to-app and must not be entangled with it.
- **Highest-risk unknown — prove it early on device:** can a background App Intent invoked *from* Yes Chef
  *into* Cockpit deliver the verdict **silently** (no Cockpit foreground, no cook action)? If the platform
  won't, the fallback is still not a shared store — it's a brief foreground hop the cook dismisses — but
  confirm the silent path first, because the whole "no id, no housekeeping" promise rests on it.

## Verification (house style)

`swift test`, `swiftlint lint --strict`, unsigned build. The set-valued verdict, the 1..N isolation, the
decline/duplicate path, referralID round-trip, and exactly-one-verdict abandonment guarantee are all
deterministic behavior — test them in `YesChefCoreTests` (extraction) and around the intent's coordinator,
not on device. The one genuine device-only risk (silent cross-app return delivery) is named above; flag it
as an unverified risk in the handoff report rather than closing it from an agent.

## Architect re-review (2026-09-21, Yes Chef side) — transport seam is blocked, effort is not

Codex correctly found that **no public API lets one app invoke another app's registered App Intent by
bundle/identifier** — App Intents surface to *system* experiences (Shortcuts/Siri/Spotlight/widgets), not to
peer apps. Confirmed against the code: `ImportHandoffResult` and `CaptureRecipeFromText` are both `.main`
foregrounding intents published via `HandoffAppShortcuts`; nothing calls them cross-app. So the "**reverse
background App Intent that Cockpit exposes and you invoke silently**" (contract, Return bullet) is **not
implementable as written**. This does **not** block the effort — it blocks exactly one seam, the return
transport. Do not write this up as a blocked design review; build the unblocked majority now.

**What Codex builds now (no transport dependency):**
- **S-y1 in full.** Deterministic 0/1/N isolation + clean-decline-on-0. Highest-value slice regardless of
  transport; improves the manual paste path too. Test in `YesChefCoreTests`.
- **S-y2 compute half.** Thread `provenance` + `referralID` through `CaptureRecipeFromText` → Create Recipe
  coordinator; produce the **set-valued verdict** (N admitted + M declined/duplicate) at admit/decline.
  Deterministic, test around the coordinator.
- **The return seam (drafted, on `main` prep — do not re-invent).** Shipped as `FindReturnEmitter`, a
  closure-struct dependency client (house idiom, mirrors `RecipeExtractionClient`), **not** a `protocol`
  and renamed off `HandoffReturnEmitter` to stay clear of the `AIHandoff*` outboard machinery the brief
  warns against. Files, all in `YesChefPackage/Sources/YesChefCore/`:
  - `FindReferral.swift` — inbound `FindReferral` (`referralID` + `rawText` + `FindProvenance`); provenance
    fields advisory except the opaque `contentPieceToken` (round-trip untouched).
  - `FindVerdict.swift` — the frozen return *shape*: `FindOutcome` = `.admitted(FindRecipeRef)` /
    `.declined(FindDeclineReason)`, `FindDeclineReason` = `.noRecipeFound/.duplicate/.dismissed/.extractionFailed`,
    and the set-valued `FindVerdict(referralID:outcomes:)` (N admitted + M declined) with `.admitted` /
    `.declines` partitions and a `.declined(referralID:_:)` convenience.
  - `FindReturnEmitter.swift` — `emit(_ verdict:)`; `liveValue` is a **no-op logging stub** (`AppLog.handoff`,
    a new category) that records but does **not** reach Cockpit; `testValue` is silent. Injected as
    `\.findReturnEmitter`.
  - Test: `YesChefCoreTests/FindReturnEmitterTests.swift` pins the shape + the recording-emitter spy S-y2's
    coordinator tests reuse (inject a spy, drive admit/decline, assert the captured verdict).

  **Codex wires the emit sites in S-y2:** `CreateRecipeCoordinator` (`YesChefApp/CreateRecipeCoordinator.swift`)
  gains `@Dependency(\.findReturnEmitter)` and the retained `referralID`; call `emit` once per admitted save
  and on decline/dismiss. Leave `liveValue` as the stub — the real transport is the deferred fork below and
  becomes a one-line `$0.findReturnEmitter = …` override in `YesChefApp.swift`'s dependency prep.

**Resolved risk (was "highest-risk unknown, prove on device"):** silent cross-app return delivery is
**resolved NO at the API level** — Codex's SDK finding *is* that result; no simulator pass owed. Reframe the
guardrail: the fallback is not a device question, it's the transport fork below.

**Deferred decision — return transport (amends the frozen joint contract; Cockpit-side too, so not Yes Chef's
to pick unilaterally).** Jon chose *build-unblocked-first, decide-later* (2026-09-21). The two live options,
both dropping behind the `HandoffReturnEmitter` seam:
- **A — App-Group verdict dead-drop (architect's lean).** Yes Chef writes the verdict to a shared-container
  mailbox keyed by `referralID`; Cockpit reads on next foreground and clears its copy. Same Apple team, so
  free. The **only** mechanism that preserves the brief's stated core value (silent, zero housekeeping). Not
  the "shared infra" the brief warns off — that warning targets *shared ownership* (CloudSyncKit / family
  HandoffKit); a one-way mailbox keeps custody per-app (ADR-0002 D8 intact).
- **B — foreground-hop return (brief's own fallback).** On leaving review, Yes Chef opens a `cockpit://`
  URL once, carrying the whole N/M verdict in one hop. No shared container; costs one Cockpit foreground
  blink per referral; "zero housekeeping" weakens to "one dismiss."

Pick A or B before wiring the emitter's real conformance. The transport choice is what makes this ADR-worthy;
assign the number when the fork resolves, not before.

## Explicitly out of scope

- Auto-routing / any non-user-initiated intake (Cockpit's first handoff is one deliberate act).
- Any generalized receiver framework or second receiver.
- Yes Chef publishing Current Context *back* to Cockpit — separate direction, not this effort.
