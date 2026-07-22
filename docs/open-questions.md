# Open Questions

Live ambiguities and recently-resolved decisions. Resolved items stay here briefly
(dated) so the reasoning is durable, then graduate into the relevant doc or ADR.

## Live — 2026-07-21: no inventory of model calls (what's onboard, what's outboard, what context is layered)

**Jon:** *"It takes a lot of forensics to track what we've got, and it's opaque to the user."* Raised after
tracing one question — which model the S4 brief extractor uses, and what context it gets — took half a dozen
greps across Core and the app, by someone with the codebase already open. **Not scoped, not scheduled.**
Recorded because the evidence is concrete right now and re-deriving it later is the expensive part.

**The asymmetry that narrows the work (measured 2026-07-21).** The **outboard** surface is already
self-describing: nine verbs, one enum (`AIHandoffTaskType`). The **onboard** surface is **19
`modelClient.complete` call sites across 14 Core files**, each independently deciding tier resolution,
prompt assembly, context layers, token budget, and reasoning effort. Nobody has ever had to grep for the
external verbs. **So this is almost entirely an onboard problem.**

**"Inventory" is two problems with different fixes — do not let them merge:**

- **Architect forensics** — call site → tier resolution → context layers → budget. Fixes the tracking cost.
- **User opacity** — at runtime the cook cannot tell which model answered, or that it silently degraded.
  A product feature, and it already has teeth: the S4 extractor's silent `.onDevice` fallback turns a
  missing API key into a truncation error on a carefully-argued brief (see the Ready Efforts nit).

A doc does not fix opacity; a status chip does not fix forensics.

**The hardest axis is context layering, and it has the least type support.** Tier is one field; context is
where the hidden variance lives. Proof from the same trace: the outbound hand-off ask sends **taste profile
+ known learnings**, while the extractor sends **neither** — a deliberate and correct split (judgment vs.
transcription, see the Ready Efforts entry) that was nonetheless **invisible until someone grepped for it.**
Highest surprise per unit of code.

**Design constraint, learned here already: a hand-maintained inventory would be stale within two slices.**
That is exactly why `YC-CONTRACT: v<n>` exists — an artifact maintained outside the thing it describes
drifts silently. A markdown table of 19 call sites would become a *second* thing to do forensics against.
**If this is built, it must be derived or test-enforced.** *Lean:* the 19 sites all construct a
`ModelRequest`, so that is the natural chokepoint — route construction through one place that records
`(surface, tier resolution, context layers, budget)` and the inventory generates itself, while the same
record feeds the user-facing "which model answered this, and with what." Both halves then fall out of one
change instead of two features. Related: [[reasoning-budget-starves-output]],
[[personal-app-latency-tolerance]] (effort/tier belong in user settings, not code constants),
[[yeschef-onbard-model-tier]].

## Resolved — 2026-07-04 (dogfood pass)

- **Kill the ingredient-substitution feature entirely, column included.** The AI suggestion path was a
  bust (suggested vegetable broth for whole milk in a baking dish). Removal spans the AI verb, the noisy
  per-ingredient menu, the review sheet, the manual editor field, **and** the synced
  `IngredientLine.substitution` column via a destructive `DROP COLUMN` migration. **Full removal is only
  acceptable because iCloud sync is not yet live** — the additive-only CloudKit discipline protects
  *deployed* schema, and there's no production deployment to protect; the same drop would be off-limits
  post-launch. Substitutions were stored **per-recipe** (column on `IngredientLine`, non-optional
  `recipeID`, no shared ingredient catalog), so nothing cross-recipe is affected. → Dogfood batch 4, Slice 3
  ([`efforts/dogfood-fixes-batch-4.md`](efforts/dogfood-fixes-batch-4.md)).
- **Two design questions promoted to ADRs (discussion open, not decided):** recipe text editing model —
  header toggles vs. inline bold/italic ([`decisions/ADR-0014-recipe-text-editing-model.md`](decisions/ADR-0014-recipe-text-editing-model.md));
  and chat persistence/history — chat is ephemeral today ([`decisions/ADR-0015-chat-persistence.md`](decisions/ADR-0015-chat-persistence.md)).

## Live — recipe normalization ("normalize recipe" function)

- **Unscoped.** Jon (dogfood 2026-07-04): a one-tap "normalize recipe" that de-caps old all-caps Milk Street
  imports and strips manual instruction numbers (we now auto-number). No natural existing effort home; parked
  here until scoped. **Sequence with [ADR-0014](decisions/ADR-0014-recipe-text-editing-model.md)** — both
  touch the same recipe text, and normalization's interaction with any future user styling must be decided
  together. Likely an LLM enrichment/one-tap action rather than a chat verb; classify before slicing.

## Dogfooding — 2026-07-21 (ADR-0042 S4 pass): the "why" dies at the commit boundary

**Jon, after the first real S4 round-trip:** the model expresses *why* each change is being made
"pretty succinctly," and none of it survives. Confirmed in code — the why has no home in any of three
places at once:

1. **The brief is transient by design** (Amd1-D5, "no new storage"). It is the only artifact carrying
   the reasoning, and it is discarded on commit.
2. **Learnings are explicitly forbidden from holding it.** The S4 ask says record *"only what was
   considered and rejected, or established as a constraint — never restate a change that already
   appears in the brief"* (Amd1-D7). So the why-of-changes-made is deliberately routed *away*.
3. **The variation payload is ops-only** — `ingredientOps` + `methodStepReplacements`, no rationale.

The one rationale deposit that exists (`RecipeDetailModel+Adjustment.swift`) is `guard let workbenchID
else { return }` — workbench-only — and writes `proposal.reviewSummary()`, a restatement of the **ops**,
not the model's prose. **This is [ADR-0042 D6](decisions/ADR-0042-workbench-handoff-and-the-return-block.md)
with a hole in it:** D6 says an outboarded session that deposits nothing "is a conversation that never
happened." Lower stakes than the workbench — you still get the changed recipe — but the why is the
scarce output of an unmetered session and the one thing that cannot be reconstructed from the result.

**The fork to decide (do not build before ADR-0021 Amds 1+2 are ratified — this wants to ride with them):**

- **(a) Variation-level `note`.** Free — `RecipeVariation.note: String?` already exists. But the brief
  carries **one why per change**, so squashing N rationales into one note makes them regenerate-only,
  never repairable one at a time — the [[editable-at-the-grain-stored]] failure and the same shape as
  the `Menu.prepPlan` blob. Also runs at [[decompose-notes-into-typed-homes]] (notes are being drained,
  not filled).
- **(b) Retain the brief verbatim as provenance** on the artifact the commit produced. *Architect's
  lean.* Prose terminating in a text field a human reads → per D3 nothing to parse and nothing to lose,
  no invented format, no new grain problem, and it preserves the model's phrasing exactly — which is
  what Jon liked. `RecipeVariation.origin` already exists as a provenance seam. Note this reverses
  Amd1-OQ2's *lean* ("discarded"), which was recorded before the first real round-trip.
- **(c) Per-change rationale inside the payload.** Matches the brief's grain but is the heaviest, and
  the payload is already a BLOB, so it would be regenerate-only anyway until Amd 1 lands.

**The asymmetry that makes this feel fuzzy, and which any answer must address:** the *variation*
destination has an obvious artifact to hang a why on. **Overwrite does not** — it mutates the recipe and
leaves nothing behind. Overwrite's only existing home is the workbench `.rationale` log, which does not
fire outside a workbench. An answer that only covers variations leaves half the flow silent.

**Timing:** pre-prod, so per [ADR-0042 OQ2](decisions/ADR-0042-workbench-handoff-and-the-return-block.md)'s
lesson this is the moment to fix the shape — and ADR-0021 Amd 2's *promote / split-off* makes it sharper,
since a variation promoted to its own recipe really ought to carry why it exists.

## Dogfooding — 2026-07-11 (two-device pass): variation ↔ Workbench overlap

The mechanical fixes from this pass are sliced in `docs/efforts/` (chrome bundle, workbench polish, meal-planner
affordances, fraction accessory). These three are the **design residue** — decide with Jon before any build.
The through-line Jon named **twice** in this pass: *individual-recipe workspaces and the Workbench "secretly
overlap."*

- **[Design fork — the umbrella] Variation workspace vs. Workbench convergence.** Jon keeps hitting the seam
  between "editing/evolving one recipe in place" (variations, adjust-proposals) and "the Workbench as a durable
  design workspace over several recipes." Both the two items below are instances. **Open question:** is the
  per-recipe variation/adjust surface a *lightweight Workbench-of-one*, and should they share machinery — or do
  they stay distinct (Workbench = multi-candidate synthesis; variations = single-recipe deltas)? Likely a future
  ADR crossing [ADR-0019](decisions/ADR-0019-recipe-design-studies.md) × [ADR-0021](decisions/ADR-0021-recipe-variations.md)
  × [ADR-0023](decisions/ADR-0023-recipe-edit-proposals.md). Don't unify prematurely — but stop treating the two
  reports below as unrelated one-offs; they're evidence for this decision.
  **NARROWED 2026-07-21:** both instances below are answered by ADR-0021 Amendments 1 + 2 **without sharing
  Workbench machinery** — hand-editing is a derived diff, promotion is two destinations. **Position: distinct
  surfaces, shared primitives** (the diff engine and the promote writer), not a "Workbench of one." The
  umbrella stays open only if a *third* instance appears that neither amendment covers.

- **[Design — feeds ADR-0014 × ADR-0021] Edit a variation, not just the original.** *(Already noted 2026-07-09
  below; reaffirmed here.)* Looking at a variation, Jon wants to **edit the variation itself**. Variations are
  LLM-created then shown **read-only** ([ADR-0021](decisions/ADR-0021-recipe-variations.md)), so hand-editing a
  variation has no home. Jon explicitly flagged the **Workbench collision** — see the umbrella fork above. Needs
  the header/text-editing model decision ([ADR-0014](decisions/ADR-0014-recipe-text-editing-model.md)) plus a
  call on whether variation-editing reuses Workbench machinery.
  **ANSWERED 2026-07-21 — [ADR-0021 Amendment 1](decisions/ADR-0021-recipe-variations.md#amendment-1--a-variation-is-hand-edited-through-the-resolved-view-the-ops-are-derived-never-authored-2026-07-21)
  (Proposed):** the human edits the **resolved** recipe and the delta is **re-derived** on save, so editing
  and the overlay were never in tension. Schema-free, no Workbench machinery. **The ADR-0014 dependency
  survives** but narrows to section headers only — they are the one edit the op vocabulary cannot express.

- **[Future — ADR-0021 territory] Promote a variation to a standalone recipe.** Jon (2026-07-11): eventually a
  way to promote a variation into its own top-level recipe. Again flagged as **Workbench/recipe-workspace
  overlap** — the Workbench already has a "promote working recipe to `main`" flip (`libraryPlacement`), so
  variation-promotion and workbench-promotion may want the same primitive. Not scoped; part of the umbrella fork.
  **ANSWERED 2026-07-21 — [ADR-0021 Amendment 2](decisions/ADR-0021-recipe-variations.md#amendment-2--promotion-is-the-release-valve-a-variation-can-become-the-base-or-its-own-recipe-2026-07-21)
  (Proposed):** two promotions — **split off as its own recipe** (B1) and **promote to base**, with the old
  base auto-derived into a variation (B2). **No probation machinery** (ratified: Jon — no cook counts, no
  verdict prompts; you promote when ready). Schema-free, and no `derivedFromRecipeID` column until something
  actually reads one.

## Resolved — 2026-06-28

- **Web recipe capture is its own milestone (M2), before sync.** A share extension is
  another write path; it must be idempotent before the iCloud one-way gate. See
  [milestones/M2-web-recipe-capture.md](milestones/M2-web-recipe-capture.md).
- **Harvest Galavant's capture engine, don't reinvent.** Same-stack, proven (JSON-LD/
  microdata votes, headless rendered-DOM). Re-target to schema.org/Recipe in YesChefCore.
- **In-app browser capture → M3.** Perfect it in Galavant first, then harvest.
- **App-group shared store now** (M2 Slice 3), coordinated with the sync CloudKit container.
- **Fallback is OpenGraph/meta + preserve-raw for M2;** photo → LLM recipe capture is the
  intended successor (its own later milestone) and the fallback for sites that resist
  structured extraction.

## Live — web-capture engine convergence

- **Converge YesChef + Galavant onto a shared capture-engine package (ADR-0007).** YesChef
  is already the second consumer; harvest-first only defers the abstraction until two working
  implementations exist. **Trigger: M2 close** (or Galavant's next capture-engine change).
  Tracked so it isn't forgotten — do not let the two engines drift permanently.

## Resolved — 2026-06-27

- **Rebaseline cleanly, don't retro-fit.** The roadmap §11 numbering is retired;
  forward work is renumbered from current reality. See
  [implementation-plan.md](implementation-plan.md).
- **Audit before forward.** The first architect act is a re-baselining review of
  current `main` for conformance to the now-codified house rules, before any new
  build order. It gates the M1 build order.
- **Order of the big three: stabilize → import → sync.** Architecture-debt paydown
  first, then import hardening, then CloudKit sync. Sync is last by design: it is a
  one-way gate, and enabling it before import is trustworthy would propagate
  throwaway re-imports across all devices and the private iCloud zone.
- **Menus are ratified product, not speculation.** Yes Chef is a next-gen Paprika:
  reach recipe-app parity, then differentiate. Paprika is the source for many
  baseline features (user files / formats: https://www.paprikaapp.com/help/ios/).
  The Menus subsystem stays; it likely earns its own ADR for the
  menu / meal-plan / grocery provenance model.
- **jon-platform did not drift.** The Pass-1 alignment items (repository core,
  persisted enums, observed-reads anti-pattern, identity-preserving saves,
  snapshot-as-interchange-format) all landed in jon-platform's `docs/ios/`. The open
  risk is whether Yes Chef's *code* conforms — which the audit settles.

## Foundation / audit

- Did the Pass-1 P0/P1 fixes actually land in the code before grocery/menu/
  meal-planning were built on top, or is that debt still present under the newer
  features? (The audit answers this.)
- Are the grocery, menu, and meal-plan reads observed (`@Fetch`/`@FetchAll`) or
  hand-pulled into `@State`? Are their saves identity-preserving?
- How much feature logic lives in views vs. `@Observable` models in the newer
  subsystems?

## Import / Paprika parity

- What is the concrete Paprika feature-parity gap list, derived from the live app
  rather than memory? (To be built when authoring Phase B.)
- Which Paprika export path is canonical for the real library import — HTML export,
  `.paprikarecipes` backup, or both reconciled? Which preserves the most fidelity
  (dates, categories, image resolution)?
- Does any high-value source need authenticated capture (ATK, Milk Street), and if
  so, when does that enter scope vs. the manual-HTML fallback?

## Comment ingestion — top-ranked tips as recipe enrichment

Feature interest noted 2026-06-30 (Jon), surfaced while sanitizing the ATK capture-DOM
fixture. The want: pull a source's comments, sort by **Most Liked (ATK) / Most Helpful
(NYT)**, and surface the top few for their *valuable advice* (e.g. "they spread too much —
cut the sugar", "came out flat") — not the whole thread.

- **The capture-DOM does not give us this — confirmed from the real artifact.** ATK
  server-renders only the **first ~4 comments** into the page, in default **Newest** order;
  the other ~1488 lazy-load via a JS/API call. So a static page capture yields neither the
  volume nor the *ranking* the feature needs. "Most liked" is a different query than what
  the DOM hands us.
- **Two separable axes — don't conflate them:**
  1. *How to obtain ranked comments.* Either **(a) user-driven in the in-app browser** —
     tap "Most Liked," let it load, then a capture scrapes the rendered comment DOM (manual
     sort + automated extract; brittle against hashed CSS-module classes like
     `comments_commentText__3vCsW`), or **(b) per-site comments API** with a sort param
     (reliable ranking, but per-site integration, possible auth/ToS gating, and *not*
     generalizable the way `schema.org` JSON-LD is). Extraction itself is automatable —
     same shape as the editorial-prose scrape.
  2. *How to judge "valuable."* **Jon-reviews** (a review/share-sheet pass over the top N)
     vs **LLM triage** that distills the top comments into a recipe note. Connects to the
     already-noted photo→LLM fallback and the existing review-before-commit flow.
- **Which surface can even do the sort+load (clarified 2026-06-30).** Three capture
  surfaces, and only one can run the interactive "sort → Most Helpful → tap Load More ×N →
  scrape" flow:
  1. *In-app `WebPage` browser* (`YesChefApp/RecipeModels.swift:288` `WebPage.browser()`,
     `BrowserViews.swift`) — the app owns this WebKit view and can inject JS to drive controls,
     await lazy-loads, and read the resulting DOM. **This is the only surface where automated
     ranked-comment loading can ship.** It is option (a) below, done properly.
  2. *iPad share extension* (`YesChefShareExtension`) — passive. `SharePreprocessor.js` runs
     **once** in the host Safari page and returns `{url, document.documentElement.outerHTML}`;
     `ShareViewController` imports no WebKit and cannot click/sort/scroll. The **only** way
     loaded comments reach it is if Jon manually sorts + taps Load-More *in Safari first*, then
     shares the expanded DOM. Weaker, human-in-the-loop variant of (a).
  3. *Claude-in-Chrome MCP (Jon's Mac)* — desktop prototyping only; does not ship. Useful to
     drive a real NYT page and **harvest a "Most Helpful, fully loaded" DOM fixture** — exactly
     the artifact this question says we lack.
- **NYT is the strong first target (clarified 2026-06-30, Jon).** Capture is always
  **authenticated** — Jon captures as a logged-in subscriber, never a logged-out scrape (the
  logged-out-still-exposes-data quirk is trivia, not a strategy). That makes option (a)
  user-driven the natural fit for NYT: in the in-app authenticated browser he can tap "Most
  Helpful," let the full thread load, and scrape the ranked comment DOM — the ranking and
  volume the feature needs are available *because* he's signed in. So the auth-gating worry in
  axis 1 largely dissolves for the sites Jon actually uses; the ToS/PII storage concern below
  still stands.
- **Constraints:** comments are third-party user content — PII (display names/initials),
  plus copyright/ToS questions for *storing and re-displaying* them, and a sanitization
  step on ingest (the ATK capture already pulled in 4 commenters' names and Jon's own `JP`
  avatar). Post-M3 enrichment idea; not in the current milestone arc.

## In-app capture — per-site behavior playbooks & review-UX sturdiness

Two linked threads Jon raised 2026-06-30, both anchored to the **in-app `WebPage` browser**
(the only ship-able interactive surface — see the comment-ingestion question above and
ADR-0009). Post-sync; **do not front-load over the iCloud gate** (see
`[[post-browser-sync-vs-features-tension]]`).

- **Per-site "capture playbooks" as a superpower (Jon's framing).** Turbocharge the in-app
  browser with small, named, per-host behaviors: Milk Street → DOM print-template fallback
  (`docs/efforts/parser-hardening-truncated-structured-data.md`); NYT → sort comments to Most
  Helpful + Load-More + scrape; ATK → editorial-prose scrape (`docs/efforts/editorial-prose.md`).
  These are the **same site-specific-DOM brittleness class** as the editorial-prose and
  comment-ingestion ideas — hashed CSS-module classes the publisher can rotate, lazy-load
  timing, layout shift. So the design constraint is: keep them a **registry of declarative,
  named, fixture-tested playbooks that degrade gracefully to schema-first**, not a pile of
  imperative per-site hacks. The Milk Street DOM fallback is effectively playbook #1 — build
  the seam so #2 (NYT) slots in without a rewrite. JS injection runs as the authenticated user;
  note the ToS/automation questions alongside the existing comment PII/storage ones.
- **Is the review surface sturdy/large enough? (verified concern, 2026-06-30).** Both
  review-before-commit surfaces are **dismiss-fragile today**: `interactiveDismissDisabled`
  appears **nowhere** in the app or extension, and `ShareViewController` never sets
  `isModalInPresentation`. So an in-progress capture/review can be lost to a swipe-down or an
  errant backdrop tap — and the share payload is one-shot (recovering means re-navigating in
  Safari). As scrape+review grows (comments, per-site playbooks, multi-section edits, image
  pick), a swipe-away half-sheet is the wrong container.
  - *Cheap near-term hardening (sync-agnostic, could land anytime):* guard the review sheet
    with `interactiveDismissDisabled(true)` / `isModalInPresentation` while there are unsaved
    edits, plus an explicit Cancel-with-confirm.
  - *Richer future:* graduate the in-app review from `.sheet` to a full-screen
    `NavigationStack` presentation (precedent exists — `RecipeLibraryView.swift:40`
    `.fullScreenCover` for `presentedRecipeID`).
  - *Division of labor:* the share extension is inherently space/lifetime/memory-constrained
    (system card, one-shot payload, no long-running work per
    `[[extension-sync-construct-not-run]]`), so keep it **lean — capture + quick confirm +
    hand off** — and put the **rich interactive review and the per-site playbooks in the
    in-app path**. Don't fight the platform by building the complex review inside the extension.

## Recipe ingredient authoring — formatting fidelity (dogfood, 2026-07-02)

Jon, first dogfooding pass: ingredient entry has **no formatting flexibility**. Section
headers automatically get bullet points too; there's no bold/italic; and pasting a
formatted ingredient list from ChatGPT loses its structure. Open design fork — pick a
direction before anyone builds:

- **Markdown-authored ingredients?** Let the ingredient/notes fields accept Markdown and
  render it — cheapest, but collides with the structured `IngredientLine`/`IngredientSection`
  model (headers are already a first-class concept; bullets are applied by the renderer, which
  is why headers wrongly get one).
- **A tiny inline formatter** (bold/italic, and a "this line is a header, not an item" toggle)
  over the existing structured model — keeps structure, adds emphasis, fixes the header-gets-a-
  bullet bug directly.
- **Smart paste** — when text is pasted (esp. from ChatGPT), detect and preserve its
  structure (headers vs. items vs. emphasis) into the structured model rather than flattening.
  Overlaps the parser / canonical-ingredient work but is an *authoring* concern, not a
  shopping-merge one — keep them separate.

The immediate, uncontroversial sub-bug (headers rendering with a bullet) may be worth pulling
out as a small fix even before the larger direction is chosen. Not in the current arc; needs a
decision first.

## Dogfooding — AI chat + recipe reader (2026-07-03)

First dogfooding pass over the shipped make-ahead chat (PR #68) and the recipe reader (screenshots:
full-screen Paprika as the density reference; Yes Chef full-screen "Done" view). Six items, sorted
bug → cheap → effort. **Sequencing decision (Jon, 2026-07-03):** the dense reader and the slide-in
chat are **one unified "cooking workspace" effort**, not separate slices — they both rewrite how
`RecipeDetailView` presents, so design them together (needs a layout sketch before dispatch).

- **[Bug] Scale multiplier falls off the bottom in full-screen.** The scale control lives in the
  `Menu` ("Scale Ingredients", `RecipeDetailView.swift` `ScalePanel`, ~line 674) anchored bottom-
  right; in the full-screen presentation it clips below the viewport and becomes unusable. Small
  Codex fix — folds into a dogfood batch, no design needed.

- **[Cheap — backend already exists] Provider picker: Claude *or* ChatGPT, both keys in Settings.**
  Galavant has this. The Slice 1 lift already gave us `OpenAIModelClient`/`OpenAIWire` and a
  multi-provider `APIKeyStore` in LLMClientKit — `AISettingsView` only *surfaces* `.anthropic` today
  (`AISettingsView.swift:58`). So this is: add an OpenAI key field + a stored per-conversation
  provider preference that `RecipeChatModel`'s frontier tier reads. No new backend; mirror Galavant's
  UI. Dispatch-ready alongside the multiplier bug as **dogfood batch 2**.

- **[Effort — the cooking workspace, unified] Dense reader + chat inspector on one draggable split,
  used simultaneously.** Design converged with Jon 2026-07-03 (sketches in chat). Three coupled wants,
  plus the resolved presentation model below.
  1. *Dense cooking reader.* When actually cooking, Jon wants Paprika's information-density
     (everything visible/scannable, photo displayed smaller) — not the current photo-forward reader.
     The deliverable is **density**: tight ingredient/step layout, scale always reachable, no wasted
     vertical space.
  2. *Chat as a side inspector worked **alongside** the recipe, never modal, never full-screen.* Chat
     is `.sheet(item:)` today (`RecipeDetailView.swift:98`) — modal, so you can't touch the recipe
     underneath. The reader must stay visible for the whole interaction, or it's "chatting about a
     recipe" rather than "cooking with an assistant."
  3. *"Start Cooking" is deliberately **not** the primary affordance (design principle, bank it).*
     Jon: "no one actually cooks with blinders on" — you look ahead, re-check ingredients, think two
     steps out. Step-by-step is at most a secondary mode; the reader is a dense *reference* surface,
     not a wizard.

  **Resolved design decisions (2026-07-03):**
  - **Scale control → toolbar** (pinned, always reachable). This is the *structural* fix for the
     full-screen clip bug; batch 2's fix is only tactical.
  - **Reader is width-responsive, not device-responsive.** Two-column (ingredients | directions) in
     **both** iPad orientations; below a width threshold it flips to the **iPhone layout — a
     Paprika-style segmented ingredients/directions toggle** (Jon confirms Paprika's segmented control
     is acceptable on iPhone). Keying the layout off *current width* (not device class) is what makes
     the draggable split cheap — the narrow layout already has to exist for iPhone.
  - **Detented draggable split (Jon's idea, 2026-07-03), not two modes.** A draggable grabber (the
     divider) snaps to detents — *balanced* (default) / *chat-dive* (chat wide, reader collapsed to the
     segmented compact layout so its content stays usable) / *reader-only* (chat closed, reader
     full-width). This dissolves the earlier inspector-vs-focus-mode fork into one continuous control.
     **Discipline: snap-to-detents, not free continuous resize** — free-drag split panes aren't an iOS
     idiom; detents share the sheet-`presentationDetents` muscle. Persist the last detent. **iPad only**
     (landscape + portrait); iPhone has no room to split, so there chat is a separate push/sheet and the
     reader is its normal segmented self. Needs a **visible grabber** (discoverability) and a **VoiceOver
     alternative** that cycles detents (a custom divider isn't self-evident to assistive tech).
  - **Provider picker lives in the chat header** ("Claude ▾"), per-conversation, one tap — richer than
     batch 2 strictly needs (batch 2 only adds the keys + a stored preference); this surfaces it in the
     workspace.
  - **The apply-action "control center" is inspector-resident, not a separate screen.** Selection arms a
     compact action bar; tapping an action stages the extracted result as a **transient review card**
     in the inspector (Commit / Discard) — the one surface that may borrow extra room (grow taller / pop
     as a popover over the reader) because it's momentary. **The commit lands in the reader on the left**,
     in place. The tap on Commit is the only write (ADR-0011 invariant + Amendment 1 selection-scoping).

  **Spec'd:** [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) (Slice A = split +
  width-responsive reader; Slice B = selection-scoped apply-actions). Starts after batch 2 merges;
  awaiting Jon's dispatch greenlight.

  **Same window on Menu + Meal Planner (Jon, 2026-07-03) — shapes the host now, built later.** Jon wants
  the chat window on a **Menu** ("full make-ahead plan for this menu", "what dish is this menu missing?",
  "good apps with this menu") and the **Meal Planner**. This is the forcing function for building the
  workspace host **context-general** (a `RecipeChatContext.menu(...)`/`.mealPlan(...)` case + a
  screen-supplied verb catalog), not welded into `RecipeDetailView`. The menu verbs map onto the two
  motions ADR-0011 already named: **cross-dish make-ahead** (distill → a menu-level commit target, a
  Menus-model decision) and **"missing dish"/"good apps"** (suggestion cards → one-tap add menu item —
  the second motion + second context). So the review surface is designed to stage a **list** of
  committable results (N=1 for recipe make-ahead today). Named/deferred as **separate efforts** in the
  cooking-workspace effort doc; not built in the recipe workspace slice.

- **[Effort — revises ADR-0011] Selection-scoped apply-actions.** See the drafted **Amendment 1** on
  [ADR-0011](decisions/ADR-0011-actionable-chat-make-ahead.md) (Proposed 2026-07-03, awaiting Jon).
  The shipped design feeds the *whole conversation* to `extract`; Jon's dogfooding insight is that
  models don't answer in discrete commit-able units (one reply may hold three side dishes), so the
  apply-action input should be a **highlighted text span** (conversation as context, selection as the
  payload) and the buttons react to what's selected. A genuine evolution of the actionable-chat
  invariant — Yes Chef is the proving ground that feeds jon-platform, so it's an ADR amendment, not a
  silent code change.

## Dogfooding — menu-planner pass (2026-07-09)

Source: `~/code/cooking/menu_planning_llm_questions_and_responses-1.md`. The mechanical fixes from this
pass are scoped in `docs/efforts/dogfood-fixes-menu-planner-2026-07-09.md`; the review-area fix is
[ADR-0026](decisions/ADR-0026-review-collection-sheet.md). These two are the **design** residue — decide
with Jon before any build:

- **[Design — per-bubble selection constraint] Multi-bubble / whole-transcript selection.** Chat
  selection can't cross bubbles because each assistant message renders as an independent `UITextView`
  (`SelectableAssistantText`), so a verb's payload is capped at one bubble's worth of highlighted text.
  Jon confirmed the limit while dogfooding. Lifting it needs either the transcript rendered as a **single
  text view** or an explicit **"select messages" mode** (per-message checkboxes feeding a combined
  payload). A rework, not a tweak; interacts with the drafted ADR-0011 Amendment 1 (selection-scoped
  apply-actions) above.
- **[Design — feeds ADR-0014 × ADR-0021] Hand-editing a variation (define a header / edit content).**
  Variations are LLM-created (`keepAdjustmentProposalAsVariation`) then shown **read-only**; there is no
  manual editing of variation content, so "add a section header to a variation" has no home. A section
  header can only appear implicitly today, when an add-ingredient delta names a new section. Lands on the
  open [ADR-0014](decisions/ADR-0014-recipe-text-editing-model.md) (header/text-editing model) crossed
  with [ADR-0021](decisions/ADR-0021-recipe-variations.md) (variations as named deltas): does a variation
  become hand-editable, and does that reuse the recipe header-editing affordance? (Variation **rename** is
  *not* here — it is a scoped quick fix in the effort above.)

## Menus / planning model

- Does the Menus subsystem need its own ADR, and what is the canonical provenance
  model linking recipe → menu → menu placement → calendar item → grocery source?
- Is "menu" vs "meal plan" vs "cooking plan" a clean three-concept split, or do two
  of them collapse?
- **Dated menus + upcoming/previous + on the planner (dogfood, 2026-07-02).** Jon wants to
  apply a **date** to a menu; the Menus list should split into **upcoming** vs **previous**;
  and dated menus should appear on the meal planner. Foundation partly exists — `menuPlacements`
  already put a menu on the calendar — but a first-class menu **date** field + list sectioning is
  net-new. Net-new feature, not designed yet.
- **Menu guests, searchable (dogfood, 2026-07-02).** Jon wants to record a menu's guests and
  have them searchable. Decision needed: a dedicated `guests` field (enables future guest
  search/reuse — favored) vs. stuffing it into free-text notes. Net-new, needs a small model
  decision.
- **Multi-add groceries by tapping a calendar day (dogfood, 2026-07-02).** Tap a day on the
  meal calendar and add *all* that day's items to the grocery list at once. **Verify against
  existing behavior first** — add-from-calendar-range/day generation already exists
  (`GroceryModels`/repository); this may be a UX-surfacing gap rather than net-new. Scope after
  confirming what the current add-from-calendar-day flow already does.

## Sync

- What is the trigger that says "import is trustworthy enough to enable sync"? A
  concrete data-quality checklist, or Jon's judgment call on a real library?
- Can the private CloudKit zone be reset cheaply if a bad import does sync, or must
  we treat first-sync as effectively irreversible?

## Recipe relationships — suppression vs. variation vs. collection

Design discussion 2026-06-30. The thesis: these are **three distinct primitives that
differ on *who does the managing***, and the tempting unification is the classic
premature-abstraction trap. This **challenges §22A `RecipeFamily`** in
[DATA_MODEL.md](DATA_MODEL.md), which currently bundles the first two into one entity
(an optional `preferredRecipeID` + a role-discriminated `RecipeFamilyMember` join).

1. **Suppression / preferred-canonical** — *rivals* (substitutes): the "one true
   chocolate-chip cookie" with the also-rans hidden but kept. **Asymmetric**: one real
   winner that lives in the main library, losers suppressed yet available for
   comparison. Parent **is a real recipe**. Managed: *you, once* (crown the winner).
2. **Variation cluster** — *siblings* (complements) on a shared base: Cook's Illustrated
   "Sugar Snap Peas with {almond+orange / pine-nut+lemon / sesame+ginger}". **Symmetric**:
   all members stay visible, **no winner**. Membership asserted **manually** (multi-select
   → "group as variations") — precise, never auto-derived, so no false clusters across
   2,115 recipes. Parent is a **synthetic display header, NOT a real recipe and NOT a
   `preferredRecipeID`** (don't mint a phantom recipe / pollute the count). Label is
   **LLM-proposed** (the *shared theme* — ingredient **or** technique **or** form, kept
   general), human-overridable, cached once, never re-derived on render. Grouping is
   rendered **at display time** (tall parent row + smaller child links). Managed:
   *nobody ongoing* — the list draws it.
3. **Curated collection** — hand-authored, ordered, sectioned editorial index
   ([ADR-0008](decisions/ADR-0008-curated-collections.md)). Managed: *you, ongoing*.

- **Position: don't unify suppression and variation by default.** They differ in
  cardinality (asymmetric vs. symmetric), parent semantics (real winner vs. synthetic
  header), and lifecycle (crown a winner vs. curate a peer family). §22A's role-enum +
  `preferredRecipeID` shape fits suppression but mis-fits variation. Let whichever ships
  first stand alone; only unify if the second *proves* shared structure. The tell that
  they're secretly one concept: wanting the variation parent to be "the best of the
  three" — that's primacy, i.e. suppression leaking back in.
- **Open — concrete model decision:** split §22A into two entities, or keep one entity
  with two display policies (collapse-to-preferred vs. expand-as-cluster)? Defer until
  the first of the two ships.
- **Shared prerequisite — multi-select in the recipe list.** The list is **single-select
  today** ([RecipeLibraryView.swift:728](../YesChefApp/RecipeLibraryView.swift)
  `List(selection: $model.selectedRecipeID)`). Both suppression (select the losers) and
  variation (select the siblings) need batch selection, as do batch tag/categorize/trash.
  **Build it early and separately**, ahead of and independent from either relationship
  feature. Not in the current milestone arc; sequencing TBD.
- **Sync-safe — these impose zero constraint on doing iCloud first (2026-06-30).** Every
  primitive here is *purely additive*: new tables (family / cluster header / membership
  joins) + at most a nullable column, all keyed on the existing `recipes.id` UUID. None
  touch an existing synced column, recipe identity, or primary key — and CloudKit's
  append-only schema only punishes *destructive* changes (delete/rename/retype/re-key),
  not new record types or nullable fields. So sync can ship first deploying today's
  schema, and RecipeFamily/clusters arrive later as a clean additive migration. The
  synthetic-header decision helps here: the variation parent isn't a recipe, so it can't
  perturb synced recipe records at all. **This is independent of the import-before-sync
  gate** — that gate is about import *trustworthiness*, not relationship modeling.

## Sequencing — after the browser milestone (the "fun features vs. the gate" tension)

Named 2026-06-30, as M3 (authenticated browser capture) approaches close and attention
turns to "what next."

- **The pull:** iCloud sync is a *risk* (a solvable one — see the sync-safety note above
  and [ADR-0002](decisions/ADR-0002-cloudkit-sync-no-server.md)), and risk is less fun
  than building. More features and more data-model build-out (variation grouping,
  families, collections) are the tempting next move precisely *because* they're lower-
  stakes and more gratifying.
- **Why that's a trap:** sync is also **backup**, and in Jon's "new world" durability
  matters *now*, not just multi-device convergence. Every feature built *before* sync is
  more un-backed-up data riding on a single device, and more surface that first-sync has
  to carry into an effectively-irreversible private zone. Deferring the gate to chase
  features increases the cost and risk of the eventually-unavoidable crossing.
- **The counter-discipline:** the modeling work is provably sync-safe and bolts on
  cleanly *after* sync (above), so there's no technical reason to front-load it. The only
  thing that should gate sync is **import trustworthiness** — and if backup is now a
  first-order goal, the honest question is "is import good enough to back up?", not "what
  else can we build first?" Treat post-M3 as a deliberate re-decision of the
  stabilize → import → **sync** order, with eyes open about the fun-vs-gate pull, rather
  than drifting into feature work by default. "Soon-ish done with browser" is the moment
  to make that call on purpose.

## House layer

- Any of these resolutions that generalize beyond Yes Chef (e.g. the
  "import-before-sync gate") — do they belong as a jon-platform note rather than an
  app-only one?
