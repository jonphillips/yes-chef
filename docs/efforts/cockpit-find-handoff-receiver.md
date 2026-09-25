# Effort — Cockpit → Yes Chef recipe Find handoff (receiver side)

Status: Built: S-y1 + S-y2 compute (#322) and S-y3 transport (#325). The two-app round trip is owed (Cockpit S-c2, then Jon's S-join device pass); multi-admit queued in [`cockpit-find-multi-admit.md`](cockpit-find-multi-admit.md)
Summary: Receive raw Cockpit Find referrals through a pair-scoped App Group mailbox opened by a single-purpose `yeschef://find-referral` door, isolate 0/1/N recipes for Create Recipe review, and return a typed verdict silently through the same mailbox.
Related: [ADR-0058](../decisions/ADR-0058-cockpit-find-referral-transport.md) (transport) ·
[ADR-0053 Amd 2](../decisions/ADR-0053-create-recipe-destination.md#amendment-2--a-headless-transport-shortcuts--app-intent-into-create-recipe-2026-08-10)
(Create Recipe door; Amd2-D3 amended by ADR-0058 D2) · Cockpit M6 Gate 5 slice plan
(`/Users/jon/code/cockpit/docs/milestones/M6-gate5-find-handoff-slice-plan.md`, ratified in
[jonphillips/cockpit#81](https://github.com/jonphillips/cockpit/pull/81))

> **Receiver half of Cockpit's M6 Gate 5**, the first specialist Find handoff. Authored 2026-09-21 from
> the Cockpit side and revised 2026-09-24, after #322 showed App Intents cannot carry it and Jon ratified
> the mailbox transport. **The contract below is the only coupling.** It is frozen jointly and copied,
> never shared by package, so do not drift it unilaterally. Everything else is Yes Chef's to build, and
> Yes Chef owns all recipe intelligence. This doc is self-contained: the S-y3 executor does not need to
> read the Cockpit repo.

## What this proves (and the boundary)

Yes Chef becomes the **first real receiver** of a cross-app Find referral. Cockpit sends **raw text +
provenance + a fallible "this looks like a recipe" hint** and nothing more. **All** domain intelligence
is yours: parsing, LLM extraction, recipe cardinality (0/1/N), dedup, merge, admission, and — critically —
the **decline**. A decline (including "duplicate") is a first-class, valuable outcome, not an error: it is
the quality signal extraction has never had. Cockpit never learns recipe schema and never pre-trims to
"the recipe" — you receive the whole readable body (newsletter chrome and all) and decide what's in it.

## The contract (frozen jointly — ADR-0058)

- **Channel: the `group.com.jonphillips.cockpit-yeschef` App Group mailbox** (ADR-0058 D1). This is a
  new group; Yes Chef's existing `group.com.jonphillips.yeschef` stays share-extension-only.
  - `find-referrals/<referralID>.json` — written by Cockpit, consumed by Yes Chef.
  - `find-verdicts/<referralID>.json` — written by Yes Chef, consumed by Cockpit.
  - Writers write atomically (temp file + rename). The consumer deletes each message. Messages only,
    never records; custody stays per-app (ADR-0002 D8 across the app line).
- **Initiate (Cockpit → Yes Chef).** Cockpit writes the referral, then opens
  **`yeschef://find-referral?id=<referralID>`** (ADR-0058 D2). Yes Chef stages it into Create Recipe
  review, and the cook finishes **now**, in the moment, with context fresh (not a queue drained later).
  - `rawText` — the whole readable body. **Never assume it is one clean recipe.**
  - `provenance` — every field is an advisory display hint **except** `contentPieceToken`, which is
    opaque Cockpit custody state to round-trip untouched.
  - `referralID` — opaque correlation token. **Machine-only. Never surface it to the cook.**
- **Return (Yes Chef → Cockpit), silent.** At admit or decline, write the **set-valued** verdict to
  `find-verdicts/`. Cockpit reads it on its next foreground; nothing opens Cockpit, and the cook does
  zero housekeeping on either side.
- **Wire format (ADR-0058 D4).**
  - UTF-8 JSON, `"version": 1`, dates **ISO-8601** (never the default `.deferredToDate`).
  - **Hand-written `Codable`**; synthesized enum coding is banned.
  - Pin both fixtures with golden-JSON tests. Cockpit pins the identical text.

  ```json
  { "version": 1, "referralID": "…", "rawText": "…",
    "provenance": { "sender": "…", "publisher": "…", "arrivalDate": "2026-09-24T12:00:00Z",
                    "seriesID": "…", "contentPieceToken": "…", "note": "…", "hints": {} } }
  ```
  ```json
  { "version": 1, "referralID": "…",
    "outcomes": [ { "kind": "admitted", "recipeRef": "<UUID string>" },
                  { "kind": "declined", "reason": "noRecipeFound" },
                  { "kind": "declined", "reason": "extractionFailed", "detail": "…" } ] }
  ```
  - `reason` ∈ `noRecipeFound | duplicate | dismissed | extractionFailed`.
  - `detail` appears only on `extractionFailed`; it is diagnostic and never shown to the cook.
  - Encoders omit absent optional fields; decoders accept either an omitted field or `null`.
- **How Cockpit reads the outcomes (for context; not yours to enforce).**
  - `noRecipeFound` / `duplicate` are the quality signal: the Find is resolved as declined.
  - `dismissed` / `extractionFailed` mean "not admitted." The Find becomes re-sendable, and neither is
    counted against the hint.
  - Under v1's one-of-N review UI, **one admitted outcome is a complete verdict**.

## Deltas

### S-y1 — Extractor accepts messy/large input and isolates 0/1/N recipes — ✅ done (#322)

### S-y2 — Receive the referral + produce the verdict (compute) — ✅ done (#322)

`FindReferral` is staged through `CreateRecipeCoordinator.stage(referral:)` with provenance shown in
review. The coordinator produces exactly one `FindVerdict` per referral through the `FindReturnEmitter`
seam, whose live value is still the logging stub.

This receiver deliberately admits **one selected candidate per referral**. The `FindVerdict` shape
remains set-valued for the eventual multi-admit contract, but the Create Recipe review UI is
pick-one-of-N and clears the referral after the first admitted save. Unselected candidates are
intentionally not reported as declines.

### S-y3 — The transport (ADR-0058) — ✅ done (#325)

1. **Entitlement.** Add `group.com.jonphillips.cockpit-yeschef` to the **app** target
   (`YesChefApp/YesChef.entitlements` + `project.yml`), alongside the existing group. The share
   extension is unchanged. **The group must be registered on the developer portal once.** If automatic
   signing can't do that from the command line, stop and ask Jon to add it in Xcode's Signing &
   Capabilities; don't work around it.
2. **Wire format (D4).**
   - Hand-write `Codable` for `FindReferral` / `FindProvenance` / `FindVerdict` in `YesChefCore` against
     the fixtures above.
   - Golden-JSON tests in `YesChefCoreTests`: decode the referral fixture; encode a verdict and compare
     it to the fixture; round-trip every `reason`.
   - Keep pure encode/decode and mailbox path logic in `YesChefCore`, not the App layer.
3. **The door (D2).**
   - Register the `yeschef` URL scheme. The root `onOpenURL` recognizes **only** `find-referral?id=…`
     and ignores everything else, with a log line and no navigation.
   - The handler runs in order: read the file → decode → `stage(referral:)` → persist the outstanding id
     (step 5) → delete the file.
   - A missing or undecodable file is logged and ignored.
   - **Cold launch:** URL handling must run after `prepareDependencies`. Test that a URL delivered at
     launch still stages.
4. **The live emitter (D6).** `FindReturnEmitter.liveValue` atomically writes
   `find-verdicts/<referralID>.json`. On a write failure, log it and leave the outstanding id in place.
   The seam and its call sites are unchanged.
5. **Process-death guarantee (D5).**
   - Persist the outstanding `referralID` in `UserDefaults` (device-local, id only) when staging, and
     clear it when its verdict is written.
   - At launch, an outstanding id with no live session → emit `.dismissed`.
   - **Remove the `scenePhase == .background` abandonment** in `RecipeLibraryView`. Keep leaving Create
     Recipe and a superseding intake.
6. **Trim the Shortcuts intent (D3).** Remove `provenance` / `referralID` from `CaptureRecipeFromText`;
   it takes text only again (Amd2-D1). Delete `CaptureRecipeError.invalidProvenance` if nothing else
   uses it.

**Done when:**
- the fixtures are pinned;
- a `yeschef://find-referral` URL stages a referral from a mailbox file, including on cold launch;
- admit and decline each write exactly one verdict file;
- a simulated relaunch with an outstanding id emits `.dismissed`;
- backgrounding no longer abandons;
- the intent is text-only.

## Guardrails

- **ADR-0053 Amd 2 still binds everything except its "no URL scheme":**
  - Create Recipe is the destination and `save(draft:)` the sink;
  - no new parser and no second text→recipe model call (ADR-0051);
  - staging never clobbers unsaved work (Amd2-D4).
- **The URL door is one host, one parameter.** It is not a deep-link router; ADR-0046's "no new
  navigation stack" holds.
- **Do NOT reach for the `AIHandoff` token types** (`AIHandoffToken` / `AIHandoffReturnContract` /
  `AIHandoffIntentImport`) or route through `HandoffReviewCoordinator`. That is the
  outboard-to-external-chat axis; this is app-to-app.
- **Custody stays per-app:** never move, mutate, or delete anything of Cockpit's. The only files you
  delete in the mailbox are the referral messages you consumed.

## Verification (house style)

- `swift test`, `swiftlint lint --strict`, and the generic device build.
- Run the `YesChefTests` app target: this effort touches `YesChefApp/` model code, meaning the
  coordinator, URL handling, and the launch reconcile.
- The fixtures, door parsing, staging order, emitter write, and relaunch reconcile are all deterministic;
  test them rather than asserting them on device.
- **Device-only, and Jon's (Cockpit's S-join):** the real round trip between two installed apps, which
  needs Cockpit's S-c1/S-c2. Name that in the PR as owed; don't simulate it from an agent.

## History — the transport fork (resolved 2026-09-24)

- **2026-09-21 original contract:** App Intents both ways.
- **Codex's finding in #322:** no public API lets a peer app invoke another app's intent. The architect
  re-review applied it to the return only.
- **2026-09-24 Cockpit review:** it applies to the initiate too, so there was no path in at all. Jon
  ratified Option A, the pair mailbox (cockpit#81). Option B, URLs both ways, was rejected: it has an
  unverified body-in-URL size limit, and verdicts emitted in the background can't open a URL. Full
  record in ADR-0058.

## Explicitly out of scope

- **Auto-routing** or any non-user-initiated intake. Cockpit's first handoff is one deliberate act.
- **Any generalized receiver framework or second receiver.** A second receiver does not join the pair
  group.
- **Multi-admit** (N admitted from one referral) — queued as its own effort,
  [`cockpit-find-multi-admit.md`](cockpit-find-multi-admit.md); the verdict shape is ready.
- **A "Back to Cockpit" hop** after save — a convenience on top of the silent return, not now.
- **Yes Chef publishing Current Context *back* to Cockpit** — a separate direction, not this effort.
