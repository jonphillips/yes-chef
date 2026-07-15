# ADR-0038 — External-LLM handoff: a trackable session, routed by App Intents

> **Vocabulary:** an *external-LLM handoff* is a durable, trackable working session that starts in Yes
> Chef, moves the exported context of one source object (a recipe, menu, or meal-plan) into a *native*
> LLM app (ChatGPT today), lets the human discuss/refine across many turns, and lands the finalized
> artifact back on the originating object. The unit of work is the **session**, not a single
> prompt→response transaction. This generalizes the menu-only, manual, plain-text *copy-paste* round-trip
> that already ships ([ADR-0034 D5/Amd1](ADR-0034-prep-plan-work-session-timeline.md)) into a reusable,
> session-tracked, App-Intents-routed feature over every source surface.

Status: **Proposed** — 2026-07-13. Origin: Jon's 2026-07-13 brainstorm (a ChatGPT design he brought to
review). Design capture: the approved plan `was-thinking-about-our-keen-hellman.md`. **Extends
[ADR-0034](ADR-0034-prep-plan-work-session-timeline.md)** (the menu Copy-Prep-Prompt / Paste-Prep-Plan
escape hatch this generalizes), **rides [ADR-0011](ADR-0011-actionable-chat-make-ahead.md)/[ADR-0024](ADR-0024-editable-proposal-preview.md)/[ADR-0026](ADR-0026-review-collection-sheet.md)**
(the `(extract → review → commit)` apply-action, the editable-preview-with-human-as-final-author
principle, and the review-collection sheet — all reused unchanged), and holds the
[[llm-vs-determinism-surface-boundary]] line (external help is advisory; the human edits before it
matters). The economic thesis: spend a **flat-rate ChatGPT subscription** on heavy multi-turn reasoning
instead of the app's own metered LLMClientKit cloud tier. Cross-platform-friendly by construction — App
Intents run on macOS too, aligning with [[macos-longterm-target]].

## Context

Four observations, in Jon's framing:

1. **The workflow already earns its keep — but only for menus.** The menu prep-plan escape hatch
   ([ADR-0034 D5](ADR-0034-prep-plan-work-session-timeline.md)) — `MenuChatContext.prepPrompt()` out, a
   free-form conversation in ChatGPT, paste the result back, re-parsed by
   `MenuPrepPlan.applyingEditableReviewText` — let Jon "talk freely without feeling like I was burning API
   $$$." He wants that same loop from **any** source, and he wants it to feel like a first-class feature,
   not a pair of buttons on one screen.

2. **The transaction is the wrong unit; the session is the right one.** Today the round-trip is
   stateless: you copy, you paste back *on the same screen*, and nothing tracks that a session is open. Jon
   wants to *leave* and come back — a durable job that knows its source, its task, and whether a result has
   landed. This is the one genuinely new idea in the brainstorm and it is worth building.

3. **Two modes, one mechanism.** Sometimes Jon wants an *immediate* answer ("shortcuts all the way down");
   sometimes he wants to *discuss* for several turns before sending a finalized artifact back to the right
   spot. These are **not** two systems — they are one handoff where the human chooses *when* to finalize
   (turn 1 or turn 20). (Note: the in-app LLM verbs are *already* the free/instant immediate path via the
   on-device tier per [[yeschef-onbard-model-tier]]; the external path exists specifically for flat-rate
   multi-turn thinking.)

4. **The routing problem is real but small.** Once the return happens somewhere disconnected from the
   source, Yes Chef must route the artifact to the correct object without the human navigating there. A
   random handoff ID that maps to a local session record solves it — and App Intents make the ID a typed
   parameter rather than a string to parse.

The brainstorm's own proposal reached for a **JSON payload + a widened share extension** as the transport.
Both are rejected below in favor of what the codebase and platform already make cheap.

## Decisions

### D1 — A transport-agnostic handoff **core**; transports are thin shells over it

The core is three pieces, built once:

- **`AIHandoff` session record** — `id: UUID`, `sourceType` (`.recipe`/`.menu`/`.mealPlan`),
  `sourceID: UUID`, `taskType`, `createdAt`, `importedAt: Date?`, `status`, `schemaVersion`,
  `exportedPrompt: String` (a snapshot of what left). New `@Table` in `Models.swift` + migration in
  `Schema.swift`.
- **Serializer** — the outbound context builder (D3).
- **Parser + commit** — the inbound artifact handler, which *reuses* the existing plain-text editable
  round-trip and the `AnyChatApplyAction` → `RecipeCollectionReviewSheet` staged-review machinery (D2).

The in-app paste button, App Intents (D4), and a future share extension are all shells over this core.
This is why the core is worth isolating first: it is the reusable 80%, and the transport question becomes a
policy choice, not an architecture.

### D2 — Format is **plain-text editable**, not JSON; routing token is a header line the parser strips

The return artifact is the same paste-ready review text the app already round-trips
(`MenuPrepPlan.editableReviewText` / `applyingEditableReviewText`; the `Recipe.makeAhead` blob path),
prefixed with a single routing-token header line (e.g. `YC-HANDOFF: <uuid>`) that the parser strips. The
outbound prompt instructs: *"discuss freely; when I say finalize, return paste-ready review text and
preserve this token line exactly; no code fences."*

Rejecting the brainstorm's JSON-with-delimiters: JSON is **brittle through copy/paste** (its own proposal
had to warn against markdown fences and export artifacts), **less hand-editable**, and it fights the
load-bearing [ADR-0024](ADR-0024-editable-proposal-preview.md) principle that *the human is the final
author* of anything committed. Plain text already round-trips structured data — including `sourceDish` FK
re-matching — and survives the messy realities of clipboard/share transport. Plain text wins.

**Validated 2026-07-13 (live `Ask ChatGPT` round-trip on a real beach-house menu).** The returned artifact
came back as structured review text unprompted — free-form session headers ending in `:` ("Whenever
convenient before departure:", "Final evening before departure:") and `- task → serves` bullets
("→ Day 1 dinner", "→ Travel", "→ Days 1, 4, and 5"). Traced against `MenuPrepPlan.swift`: headers hit
`isEditablePrepPlanSessionHeader` via the trailing colon (`editablePrepPlanSession` accepts *any*
colon-terminated line, not just literal `Session:`), bullets strip `- ` and split on `→`, and the
meal-reference `serves` labels carry as plain non-tappable text (no `sourceDish`) per ADR-0034 OQ2. So the
paste-back parses into three prep bands with **no structural prompt-tightening needed**. The one hardening
item: pin the exact `→` glyph in the outbound prompt, or teach `editableReviewLine` to also accept `->`.

### D3 — Generalize the serializer to Recipe and MealPlan (Menu already has it)

Only `MenuChatContext` exists today. Add Recipe and MealPlan context builders on the same pattern, reusing
`serialized(for: .frontier)` budgeting and the ADR-0034 Amd1 "self-contained runnable prompt" shape
(frontier budget, full method, uncapped ingredients, an adapted intro prompt tuned from `tasteProfile` /
AI settings, asking for the **review-text** output format the paste-in path re-imports). Commit shapes per
source: recipe → `Recipe.makeAhead` blob (and adjust/variation per ADR-0021/0023); menu → `Menu.prepPlan`;
meal-plan → the make-ahead-strategy shape ([ADR-0013](ADR-0013-meal-planner-actionable-chat.md), classify
per [[chat-verb-commit-shapes]]).

### D4 — **App Intents** is the primary transport (deployment target is iOS 27.0 — all APIs available, no gating)

The app has **zero** App Intents today; this is greenfield, but it is the modern automation surface and it
is also the foundation stone for the `FUTURE_INTELLIGENCE_AND_PLANNING.md` "culinary chief of staff" vision
(Siri / Spotlight / Action Button addressability of recipes and menus).

- **`AppEntity` for Recipe / Menu / MealPlan**, marked **`SyncableEntity`** (iOS 27) — our IDs are stable
  iCloud UUIDs, so cross-device Siri continuity comes for free and cleanly answers "hand off on iPad,
  return on iPhone."
- **`ExportHandoffContext(source:)`** — `source` as an **`@UnionValue`** (iOS 27) of the three entity
  types. Creates the `AIHandoff` record, returns the prompt string. Exposed to Shortcuts / Siri / Action
  Button / Spotlight.
- **`ImportHandoffResult(handoffID:, result:)`** — routes by ID, runs the parser, and **`OpensIntent`**s
  into the in-app `RecipeCollectionReviewSheet` for the discuss case (or commits directly for the immediate
  case).

Rejecting share-extension-first: the extension is URL/web-page-only today (a plain-text answer wouldn't
even surface "Save to Yes Chef"), it only ever *creates* a new recipe row, and `open-questions.md` already
ruled it stays lean with rich review in-app ([[extension-sync-construct-not-run]]). App Intents run
in-process with typed parameters, no share-card memory/lifetime limit, and are strictly better routing.

### D5 — One mechanism, two modes, mapped to concrete ChatGPT Shortcuts actions

On-device verification (2026-07-13, iPadOS 27) confirms the ChatGPT app ships a rich Shortcuts action set:
**`Ask ChatGPT`** (headless — distinct from the app-opening `Start conversation with ChatGPT`),
**`Start chat in project`** (surfacing the user's real projects — *Food*, *Emerald Isle Beach*, …),
`Ask ChatGPT about an image`, `Voice Mode`, `New Chat Configuration`, plus Apple's own **`Use Model`**
action (On-Device / Cloud / Cloud Pro / **ChatGPT**). This resolves the make-or-break unknown in the
optimistic direction. The two modes map to distinct actions:

- **Immediate ("shortcuts all the way down"):** `ExportHandoffContext → Ask ChatGPT → ImportHandoffResult`.
  `Ask ChatGPT` runs headless and returns the answer as a value (final 60-second confirmation noted in the
  Cost section); `Use Model → ChatGPT` is an Apple-native fallback that also returns a value.
- **Discuss:** `ExportHandoffContext → Start chat in project` (seed the context into a *persistent* project
  so it accumulates across sessions — the durable-session thesis extended onto the ChatGPT side; the
  beach-house / a per-menu project is the natural home) → converse N turns → a "Return to Yes Chef"
  shortcut (or the share sheet) → `ImportHandoffResult` → review sheet.

Both branches ship regardless; if a value-returning action were ever unavailable the same intents fall back
to manual paste/share return. **The design does not bet on any single action.**

### D6 — Route by ID first, self-describing payload as the fallback

`ImportHandoffResult` prefers the `handoffID` (from the intent parameter or the stripped token line) →
looks up the local `AIHandoff`, validates `taskType` matches the destination, dedupes on `importedAt`.
Because the record is **device-local (D1)**, a cross-device or record-missing return still routes: the
return text self-describes via the token, and the artifact's commit target is derivable from the source
object's own synced UUID. Validate-then-preview always; **never auto-commit without the review sheet** for
the discuss path (the immediate path may commit directly by design, but still surfaces a result).

### D7 — Commit destinations reuse existing shapes, including "add as new version"

"Replace / Add as new version / Cancel" is not new machinery: *add as new version* = ADR-0021
`recipeVariations` for recipes and the [ADR-0034](ADR-0034-prep-plan-work-session-timeline.md) full-replace
for menu prep plans. Route through the existing commit shapes; do not reinvent versioning.

## Amendment 1 — the return artifact is two-part: **Deliverable + Learnings** (2026-07-14)

**Status: Accepted.** Origin: Jon, after the S2 device pass. Amends D2/D3/D6/D7 and re-splits S3.

### The gap

The handoff as shipped reduces a multi-turn session to a **context-free deliverable**. The prep plan
lands; the *reasoning that produced it* dies in ChatGPT. But a session produces two distinct things:

- **Deliverable** — structured, routes to a field. Prep plan, make-ahead, variation. Built.
- **Learnings** — durable knowledge established *in discussion*. *"Dried bay leaves beat fresh, and you
  can dry your own."* *"Birria benefits from a day or two of sitting, so it's a good travel dish."*
  **Currently discarded.**

Sometimes a session yields **only** Learnings and no deliverable — today that is a dead end, which is
wrong: it is one of the most valuable session shapes.

We cannot preserve the conversation (ChatGPT owns it, and it expires). We should not want to — nobody
rereads transcripts. **Don't preserve the conversation; harvest it** — the vocabulary this codebase
already speaks ([ADR-0027](ADR-0027-note-harvest.md) harvest, [ADR-0025](ADR-0025-reader-feedback.md)
curate-to-notes).

### Decision

**The return contract becomes `(Deliverable?, Learnings?)` — either may be empty.** A learning-only
return is a **first-class outcome**, not a degenerate one.

- **Format.** The finalize instruction (already the discuss prompt's hook) asks for both: the deliverable
  section, then a Learnings section introduced by a **`YC-LEARNINGS:` marker line** (mirroring the
  `YC-HANDOFF:` convention). Learnings come back as a **structured list of distinct bullet items** — never a
  merged blob summary, per [[llm-curation-not-synthesis]]. The model curates its own conversation, which
  beats a raw transcript.

  **⚠️ The parser must split *before* it parses.** `isEditablePrepPlanSessionHeader`
  (`MenuPrepPlan.swift:352`) treats **any non-bullet, colon-terminated line** as a prep-plan session header.
  So a `YC-LEARNINGS:` line handed to `applyingEditableReviewText` would be **swallowed as a prep band** and
  every learning under it would become a prep step. Therefore: **strip the token → split the body on the
  `YC-LEARNINGS:` marker → feed *only* the deliverable half to `applyingEditableReviewText`**, and parse the
  learnings half as bullets. No marker → the whole body is the deliverable (today's behavior, unchanged).
  Marker present with nothing above it → a **learning-only** return.
- **Landing zone — a new synced `Learning` table.** *(Decided with Jon 2026-07-14, after rejecting both
  alternatives.)* **Not** `Menu.notes` / `MealPlanItem.notes` — those are string blobs, and merging distinct
  learnings into one violates [[llm-curation-not-synthesis]] and this amendment's own rule. **Not**
  `MenuItem` note-rows either — those carry **day/placement** semantics, and a menu-wide learning has no day,
  so the row would *mean* something false. And **not** `AIHandoff`, which is device-local, non-synced,
  transient scaffolding (OQ1) — Learnings are durable and must travel with the resource.

  The deciding argument is the project's actual trajectory: **notes are being decomposed, not consolidated.**
  Make-ahead got its own typed home; Chef It Up got its own. "Notes" is the residue being drained, not a
  destination. A `Learning` is another **typed content kind** and gets its own home — which also makes it
  *addressable* by future AI interaction in a way prose buried in a note blob never is.

  **Shape (start minimal — plain text; let the corpus tell us if it wants structure):** `id: UUID`,
  `sourceType` (reuse `AIHandoffSourceType`), `sourceID: UUID`, `text: String`, `provenance`
  (`.externalHandoff` / `.inApp`), `dateCreated`, `dateModified`. **Additive + synced** (add to
  `makeSyncEngine`'s table list *and* the standing prod-schema promotion list).

  **Two consequences that are not free:**
  - **Polymorphic `(sourceType, sourceID)` cannot be a real FK**, so there is **no cascade delete** — deleting
    a menu would orphan its Learnings as synced ghosts. Each source's delete path must **hand-cascade**.
    (`AIHandoff` has the same polymorphic shape but is transient, so orphans there are harmless. Here they are
    not.)
  - **No FK back to `AIHandoff`** — it is device-local, so a synced `Learning` referencing a handoff id would
    dangle on the other device. Provenance is a **marker**, never a link.
- **Review.** `RecipeCollectionReviewSheet` already takes `items: [ChatApplyReviewItem]`; the handoff sheet
  currently passes exactly one. It passes **two** — Deliverable and Learnings — each independently
  editable and independently discardable. The human remains final author of both
  ([ADR-0024](ADR-0024-editable-proposal-preview.md)/[ADR-0026](ADR-0026-review-collection-sheet.md)).
- **New `taskType`** for a learning-only handoff, valid against *any* source.

### Consequence — Learnings are the **universal commit shape**, and S3 re-splits

Every resource has notes, so "harvest to notes" needs **zero per-source commit logic** — while every
deliverable shape is bespoke. **But the *outbound serializer* is still per-source**, and Recipe/MealPlan
serializers do not exist yet (they were the whole of old-S3). You cannot harvest learnings from a recipe
until you can *export* a recipe. So S3 splits along the **de-risking** line S1 already proved — build the
new contract on the surface that already round-trips:

- **S3a — the two-part contract, proven on Menu.** The menu serializer already exists, so there is **no new
  outbound work**. Extend the finalize instruction to ask for both sections; parse both; stage **two**
  review items; commit Learnings to menu notes. This is where the *universal* commit machinery gets built,
  cheaply, on known ground.
- **S3b — generalize the serializer to Recipe + MealPlan.** Each source gains its deliverable shape —
  recipe → `Recipe.makeAhead` + adjust/variation
  ([ADR-0021](ADR-0021-recipe-variations.md)/[ADR-0023](ADR-0023-recipe-edit-proposals.md)); meal-plan →
  make-ahead strategy ([ADR-0013](ADR-0013-meal-planner-actionable-chat.md), classify per
  [[chat-verb-commit-shapes]]) — and **Learnings ride along for free** on the S3a machinery. This is also
  where a learning-only handoff becomes useful on sources with no structured deliverable field.

**Presentation is deliberately not decided here.** *Where* Learnings and deliverables are displayed (the
in-app chat panel's future, a possible "Intelligence" third column) is a separate information-architecture
question with its own ADR. This amendment is the **data contract only** — which is why S3 is not blocked
by that redesign.

## Amendment 2 — the **in-app door** is primary for Recipe + MealPlan; the intent is the hands-free bonus (2026-07-14)

**Status: Accepted.** Origin: Jon, dogfooding the S3b recipe handoff on device. Amends **D4/D5** (which named
App Intents the *primary* transport) and adds an **S3c**. No core or schema change.

### The gap

S3b shipped the **intent half** for Recipe and MealPlan but not the **in-app entry point** Menu already has
(`Copy Prep Prompt` / `Paste Prep Plan`, `MenuViews.swift`). So on device, the only way to get make-ahead for
the recipe you are *looking at* is: leave the recipe → open the Shortcuts app → build (once) and run a
parameterized `ExportHandoffContext` shortcut → round-trip through the ChatGPT `Ask ChatGPT` action → come
back. There is **no button on the recipe**, and the intents aren't registered as an `AppShortcut`, so they
aren't reachable from Action Button / Spotlight / Siri without hand-authoring the shortcut either. The first
honest dogfood question was, correctly, *"is that ever worth it?"*

### Two reasons this is the wrong *primary* door — not just less convenient

- **Make-ahead is a *discussion*, not a one-shot.** The Immediate/autopilot path (`Ask ChatGPT`, D5) answers
  in a single turn with **no conversation** — discarding the back-and-forth (*"I won't have two days ahead —
  what about morning-of?"*, *"I'm doubling it"*) that is the *whole point* of handing off to a frontier model.
  Manual copy/paste keeps the human *inside* the ChatGPT conversation, then harvests the finalized answer.
  [[automation-decays-near-the-stove]]: full autopilot is a gift when there is nothing to decide, a liability
  when the deciding **is** the value.
- **Copy/paste costs nothing structural.** The pasted return still routes through
  `AIHandoffIntentImport.stageReview` → the review sheet — editable at the grain, lossless-or-loud, Learnings
  riding along (Amd 1). You get the discussion **and** the safe structured landing. (Strictly better than
  Menu's *existing* manual path, which predates ADR-0040 and writes more directly — bring Menu onto the same
  review-routed path while here.)

### Decision

- **The primary, everyday door for Recipe + MealPlan is an in-app affordance**, mirroring Menu's Copy/Paste, on
  `RecipeDetailView` and the meal-plan day view. **Copy** emits the same tokenized prompt S3b already builds
  (`YC-HANDOFF:` header + the source's `DeliverableFormat`); **Paste** feeds `stageReview` → the review sheet.
  This is a **new thin transport shell over the S3b core** — exactly D1's model (transports are thin shells;
  the core is reused). **App-layer only: no core, schema, or migration change.**
- **Discuss-first is the default** of the in-app button (seed the prompt, alt-tab, converse, paste the result).
  **Immediate stays available via the intent** for the genuinely hands-free case.
- **D4 is amended, not reverted.** App Intents remain the **hands-free / power / cross-device** transport
  (Action Button, Siri, Spotlight, hand-off-on-iPad-return-on-iPhone). They are **no longer the primary — and
  never the only — door** for a human standing at a recipe. Both transports ship; this re-orders which one the
  everyday case reaches for and fills the in-app gap the new sources shipped without.
- **Discoverability fix for the intent (secondary):** register an `AppShortcut` so export/import are reachable
  from Action Button / Spotlight / Siri without hand-building a shortcut. Worth doing, but subordinate to
  putting a door on the recipe.

### Deferred (explicitly not in this amendment)

- **Per-section prompt scoping** (checkboxes to choose which recipe sections to send). The make-ahead context
  builder already scopes sensibly; add section selection **only if the default context proves wrong** — do not
  front-load the UI.
- The **`Ask ChatGPT` double-fire** Jon hit is a ChatGPT-action / Shortcuts app-switch artifact, **not ours** —
  noted, not owned here. It is one more reason not to make the autopilot path the primary one.

### Slice — S3c (app-layer only)

In-app **Copy-Prompt / Paste-Result** on recipe detail + the meal-plan day, routed through the existing
`stageReview` → review sheet, discuss-first; opportunistically move Menu's manual buttons onto the same
review-routed path. No new core, no schema, no migration; no simulator install ([[lean-verification-default]])
— Jon device-passes the alt-tab flow.

## Deferred (on the record, explicitly not built here)

- **Widened share-extension "Import into Yes Chef."** A polished entry point for when you're already
  looking at a ChatGPT answer and hit Share. Optional, later, and it fights the lean-extension rule —
  App Intents cover the same ground first.
- **`SnippetIntent` interactive review inline in Shortcuts/Siri** (iOS 26/27) — render the
  Replace/Add-version/Cancel choice inside the Shortcut run instead of opening the app. A genuine polish
  win; v1 uses `OpensIntent` to the in-app sheet.
- **`LongRunningIntent` / `performBackgroundTask`** — only needed if an intent ever runs the *in-app* LLM
  past ~30s. Export is string-building; not needed v1.
- **`IndexedEntityQuery` Spotlight self-healing** for the new entities — nice, not core.
- **Provider = Claude** alongside ChatGPT (the app's own Claude/ChatGPT provider picker is a separate
  `open-questions.md` item); the handoff is transport-agnostic to which native app hosts the conversation.
- **Freeform `taskType`** — start with the tasks that have commit shapes today.

## Storage sketch

New `AIHandoff` `@Table` in `Models.swift`, migration in `Schema.swift`. **Device-local — not added to the
synced record set** (transient working state, like selection state; sync-safe by omission). `exportedPrompt`
is a plain `TEXT` snapshot. `status` is a small enum (`.awaitingReturn`/`.imported`/`.discarded`).
`schemaVersion: Int` future-proofs the payload contract. No change to Recipe/Menu/MealPlan schemas — the
handoff only *references* their synced UUIDs.

## Cost, honestly — and the slice plan

The serializer (menu), the parser round-trip, the review sheet, and the commit shapes all exist. What is
new: the `AIHandoff` record, the token emit/strip, the two intents + three entities, and the Recipe/MealPlan
serializers. Sequenced to de-risk by proving the transport on the surface that *already* round-trips:

- **S1 — core, proven on Menu (first dispatch, part 1).** `AIHandoff` record + migration; token
  emit-on-export / strip-on-import folded into the existing menu round-trip; `ImportHandoffResult` routing +
  parse + wire to `RecipeCollectionReviewSheet`. Reuses the menu serializer/parser wholesale — smallest path
  to a working end-to-end loop. Nothing new-surfaced yet beyond the record.
- **S2 — App Intents surface (first dispatch, part 2).** Three `AppEntity`s (`SyncableEntity`),
  `ExportHandoffContext` (`@UnionValue source`), `ImportHandoffResult` (`OpensIntent`). New `AppIntents/`
  group in the app target (intents run in-process; call `RecipeRepository`/`MenuRepository`). Bundle S1+S2
  as one dispatch per [[batch-slices-and-lean-handoff]] — they share the core and a mental model.
- **S3 — generalize the serializer (follow-up dispatch).** Recipe + MealPlan context builders on the D3
  pattern; wire each source's commit shape. Independent; rides after S1+S2.

Build brief to live at `efforts/adr-0038-external-llm-handoff.md` when dispatched. Verify per
[[lean-verification-default]] — build + check-drift for the core; **Jon's device pass** for the App
Intents / Siri / Action Button loop (they need a device, not the simulator), which also settles the
ChatGPT-action question (D5).

## Open questions

- **OQ1 — RESOLVED (2026-07-13): device-local, never syncs.** Transient working state; the return payload
  self-describes (D6), so a cross-device return still routes off the source's synced UUID. *Implementation
  note:* the `AIHandoff` table must be kept **out of the CloudKit SyncEngine's record set** — confirm the
  per-table opt-out mechanism; if there isn't a clean one, a lightweight device-local store (separate
  non-synced store / file / `UserDefaults`) is acceptable for so small and transient a record.
- **OQ2 — `taskType` taxonomy.** Start with prep-plan, adjust-recipe, and meal-plan make-ahead-strategy
  (the shapes that exist). Freeform/advisory-only later. Confirm at S1.
- **OQ3 — RESOLVED (2026-07-13).** `Ask ChatGPT` is headless and returns the answer as a downstream value —
  confirmed by a live round-trip that routed the result into a scratch Note, in the parse-ready format (see
  D2). Immediate mode ships in v1. Latency ~1 min, within [[personal-app-latency-tolerance]];
  `ImportHandoffResult` handles the late return asynchronously.
- **OQ6 — RESOLVED (2026-07-13): per-menu project.** Discuss-mode routes into a ChatGPT project dedicated to
  the menu (the *Emerald Isle Beach* pattern), so context accumulates across sessions on ChatGPT's side.
  Requires a **Menu↔project mapping**: an optional `Menu.externalProjectName` the user sets once, matching a
  project they created in ChatGPT (projects **cannot** be created via Shortcuts — so Yes Chef selects into an
  existing one, never creates). `ExportHandoffContext` returns that name as an output the shortcut feeds to
  `Start chat in project`. Sub-question RESOLVED (2026-07-14, device): fixed-only. Start chat in project
  resolves the project at configure time and does not accept a variable input (no variable bar even with the
  picker's search field focused); it also appears to take no prompt/message input. Per-menu project
  auto-seeding from one generic shortcut is therefore not achievable. This does not break the handoff —
  return→resource routing rides the YC-HANDOFF: token and is project-independent. Fallbacks, in order: (1)
  immediate mode (Ask ChatGPT, headless) as the automated loop; (2) discuss mode via the in-app Copy Prep
  Prompt → paste into the project by hand → Paste Prep Plan; (3) optional hybrid — Export → Copy to Clipboard
  → Start chat in project (fixed project, one shortcut per active project). Menu.externalProjectName is
  demoted from a routing key to an advisory reminder, and ExportHandoffContext gains a mode parameter
  (default **immediate**) so a Shortcut can also start a discussable session. The default is immediate
  because the Shortcuts surface exists for the headless `Ask ChatGPT` chain — a discuss prompt sent
  headlessly returns prose the parser cannot use, while the reverse mispairing is harmless. The
  **in-app Copy Prep Prompt button stays the discuss path** and takes no mode.
- **OQ4 — token in the intent parameter vs. the text body.** `ImportHandoffResult(handoffID:)` gets the ID
  typed for the automated chain; the "Return to Yes Chef" / paste path recovers it from the stripped token
  line. Support both; the parameter wins when present.
- **OQ5 — Action-Button / no-entity invocation.** When `ExportHandoffContext` is fired with no `source`
  (e.g. a bare Action Button), how is the subject resolved — an `EntityQuery` "current recipe", a picker,
  or a "there's nothing selected" prompt? Decide at S2.

## Related

- ADR-0034 (the menu escape hatch this generalizes; the frontier-prompt serializer shape),
  ADR-0011/0024/0026 (apply-action, editable-preview human-as-author, review sheet — all reused),
  ADR-0021/0023 (the variation / adjust commit destinations), ADR-0013 (meal-planner commit shapes),
  ADR-0002 (sync — the handoff is sync-safe by omission), ADR-0022 (the determinism boundary this stays on
  the advisory side of).
- Memory: [[yeschef-onbard-model-tier]] (the in-app immediate path), [[personal-app-latency-tolerance]]
  (why external multi-turn is worth the friction), [[llm-vs-determinism-surface-boundary]],
  [[chat-verb-commit-shapes]], [[extension-sync-construct-not-run]] (why not the share extension),
  [[macos-longterm-target]] (App Intents are cross-platform), [[batch-slices-and-lean-handoff]],
  [[lean-verification-default]].
