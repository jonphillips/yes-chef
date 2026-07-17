# ADR-0041 — Playbook sections become self-serve units: a per-section toolbar and a section-scoped hand-off

> **Vocabulary:** a *Playbook section unit* is a single Enrichment-column section (Make-ahead, Chef It Up,
> Serve With) treated as a **self-contained, independently-actionable unit**: its own state-aware toolbar,
> its own **section-scoped** external hand-off verb, its own editable content + provenance + optional
> live-conversation URL, edited in **its own sheet** — pulling per-section editing off the monolithic
> recipe edit sheet. The organizing move is to stop treating the Playbook column as one blob of sections
> with a single whole-recipe hand-off, and start treating each section as a small addressable object.

Status: **Proposed** — 2026-07-17. Origin: Jon's 2026-07-17 design discussion (toolbar-efficiency per
section + the conversation-URL want). **Lives inside [ADR-0039](ADR-0039-playbook-column-thinking-vs-doing.md)**
(the persistent Enrichment/Playbook column), **rides [ADR-0038](ADR-0038-external-llm-handoff.md)** (the
hand-off core and its in-app Copy/Paste door, Amd 2) and **refines [ADR-0038 Amendment 3](ADR-0038-external-llm-handoff.md#amendment-3--an-optional-user-pasted-conversationurl-to-reopen-the-live-chat-2026-07-15)**
(relocates `conversationURL` from the device-local, non-synced `AIHandoff` onto a synced, section-addressable
home), **governed by [ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md)** (the section's provenance
and URL become typed fields, never re-parsed from a blob), and **reuses [ADR-0024](ADR-0024-editable-proposal-preview.md)/[ADR-0026](ADR-0026-review-collection-sheet.md)**
(the editable review sheet becomes the per-section edit sheet). Holds the
[[llm-vs-determinism-surface-boundary]] line (external help stays advisory; the human edits before it
matters) and the [[automation-decays-near-the-stove]] restraint (a calm header, a toolbar only on expand).
Extends [[decompose-notes-into-typed-homes]] / [[editable-at-the-grain-stored]].

## Context — the sections are already units; the app doesn't treat them as such

Three observations, grounded in the code as it stands today.

1. **The whole-recipe hand-off is secretly a make-ahead verb.** `HandoffExportSource`
   (`HandoffIntents.swift:133`) is `.recipe` / `.menu` / `.mealPlan` — **no section dimension** — and the
   recipe case maps to `taskType: .recipeMakeAhead` (`HandoffIntents.swift:157`). So the column-top
   "Hand off to ChatGPT" produces **only** a make-ahead prompt. Chef It Up and Serve With have *in-app*
   generate verbs (`makeAheadPlanClient` / `chefItUpPlanClient` / `serveWithPlanClient`,
   `RecipeDetailModel+Enrichment.swift:7–72`) but **no external hand-off at all**. Jon's stated working
   preference — *use flat-rate ChatGPT as often as possible* — is therefore **impossible for two of the
   three sections** today.

2. **Per-section editing lives on the wrong sheet, and the toolbar is incoherent.** Editing make-ahead or
   chef-it-up means opening the **monolithic recipe edit sheet**; meanwhile each section's `Clear` button
   sits *inside* its expanded content (`RecipePlaybookView.swift:150–184`) with its Edit somewhere else
   entirely. Reader Feedback already proves the right shape — **its own inline Edit/Done editor**
   (`RecipePlaybookView.swift:226–267`). The rest of the sections haven't caught up: Clear here, Edit over
   there, no scoped hand-off, and a growing pile of per-section buttons with no organizing rule.

3. **There is nowhere durable to hang a conversation link.** Jon wants to **reopen the ChatGPT thread** that
   produced a section and re-finalize. But `makeAhead` / `chefItUp` are bare `String?` on `Recipe`
   (`Models.swift:31–33`) — no room for provenance or a URL. [ADR-0038 Amd 3](ADR-0038-external-llm-handoff.md)
   put `conversationURL` on the **device-local `AIHandoff`**, which is transient and **not synced** — so a URL
   there neither reliably persists nor travels to the iPhone Jon also cooks from. The want implies a *durable,
   synced, section-addressable* home, which is a different place than Amd 3 chose.

The through-line: **a section is already the natural unit of work** (one generate, one edit, one hand-off,
one conversation), but the app models it as a slice of a whole-recipe blob. Promote the section to a unit.

## Decisions

### D1 — A section is a self-serve unit: define a `PlaybookSection` conformance

A **behavioral / view-model contract** (not one storage table) that Make-ahead, Chef It Up, and Serve With
adopt: read/write its content, expose its fill state, its **scoped** generate verb (in-app *and* external),
its provenance, its optional `conversationURL`, and its clear. The toolbar (D2) and edit sheet (D4) are
written **once** against the conformance; adding a fourth section later is adopting the protocol, not
rebuilding UI.

Sections differ in **content shape** and the conformance carries it: **singular-blob** sections (make-ahead,
chef-it-up) expose one string; the **list** section (serve-with) exposes a collection with per-item remove
(which already exists, `RecipePlaybookView.swift:186–210`). The toolbar and edit sheet adapt on
`contentShape`. **Notes is deliberately not a member** (D5).

### D2 — The toolbar is state-aware, two-visible-plus-overflow, and lives in the expanded content

Not a fixed button row: the efficient toolbar is a function of whether the section has content. It renders
at the **top of the expanded content** (where `Clear` already is), so **collapsed** sections show only
`title + fill-dot + chevron` and stay calm — the [[automation-decays-near-the-stove]] restraint.

| State | Visible (2) | In `•••` overflow |
| --- | --- | --- |
| **Empty** | **Hand off** *(prominent, spark icon)* · Paste | Write manually · Ask in-app |
| **Filled** | Edit · Redo | Paste (replace) · Clear |

Strings are brand-free per **D7** — the spark icon, not the word "ChatGPT," carries the external signal.

- **External hand-off is the primary affordance** in the empty state — honoring Jon's external-first
  preference. The empty section's whole offer is *"fill me from ChatGPT, or paste a result."*
- **`Clear` leaves the always-visible row** for the overflow (and the edit sheet, D4). It's the rarest,
  most destructive action; it does not deserve permanent header real estate. Edit subsumes its *job*
  (select-all-delete), so no capability is lost.
- **Edit** opens the section's own sheet (D4).

### D3 — A section-scoped external hand-off requires `HandoffExportSource` to carry the section, and routing to match on it

To give Chef It Up and Serve With their own ChatGPT round-trip:

- **`HandoffExportSource` gains a section dimension** — e.g. `.recipeSection(Recipe.ID, PlaybookSectionKind)`.
- **`AIHandoffTaskType` gains a case per section** (`chefItUp`, `serveWith`) alongside the existing
  `recipeMakeAhead`.
- **⚠️ `matches(_:)` and the token round-trip must include the section kind.** Today `matches`
  (`HandoffIntents.swift:173–177`) compares **only** `sourceType + sourceID`. Two sections of the same
  recipe share both — so **without a section key, a pasted Chef-It-Up result would route onto Make-ahead**
  (or whichever handoff for that recipe is `awaitingReturn`). The section kind must be part of the match.
- **Rescope the existing whole-recipe hand-off to be explicitly `.makeAhead`** rather than the implicit
  default it is today, so the column-top button and the per-section make-ahead button mean the same thing.

### D4 — Per-section Edit is its own sheet, lifted off the monolithic recipe editor

Reuse the [ADR-0024](ADR-0024-editable-proposal-preview.md) editable review sheet shape — roomy, scrollable,
**human as final author**. Beyond the content, the sheet surfaces **provenance** and the **`conversationURL`**
(view / edit / clear), and hosts `Clear`. This drains make-ahead / chef-it-up / serve-with editing **out of**
`RecipeEditorView` — the same decomposition Reader Feedback already models inline. Editing at the section
grain is [[editable-at-the-grain-stored]] arriving in the UI.

### D5 — Notes is **not** a section unit, and is deliberately excluded

Notes is the heterogeneous residue — 13 `RecipeNoteType` subtypes (`RecipeNoteTypeDisplay.swift`) — and a
single "generate Notes" blob-verb would **flatten distinct items into one summary**, violating
[[llm-curation-not-synthesis]]. Per Jon (2026-07-17): **punt, possibly retire.** The one tempting
repurposing — *"make Notes a Learnings dumping ground"* — is **rejected here**, because the typed home for
harvested knowledge **already exists**: the synced `Learning` table
([ADR-0038 Amd 1](ADR-0038-external-llm-handoff.md#amendment-1--the-return-artifact-is-two-part-deliverable--learnings-2026-07-14)).
Notes gets **no toolbar unit, no scoped verb, no conformance**; it is revisited only under the
notes-decomposition track, not here.

### D6 — `conversationURL` + provenance live on a synced, section-addressable home; this **refines ADR-0038 Amd 3**

To hang provenance and a URL on a section, two options:

- **(a) Inline columns on `Recipe`** — `makeAheadConversationURL`, `chefItUpProvenance`, … Simplest, but
  clutters `Recipe` and scales badly as sections grow (2 fields × N sections).
- **(b) A synced `PlaybookSectionMeta` sidecar**, keyed `(recipeID, sectionKind)`, carrying
  `{ provenance, conversationURL, dateModified }`. **Recommended.** Extensible, keeps `Recipe` clean, and —
  the deciding point — gives the URL the **durable, synced** home it actually needs.

This **refines** [ADR-0038 Amd 3](ADR-0038-external-llm-handoff.md) (still *Proposed*, unbuilt, so this is a
relocation, not a reversal): the URL moves **off** the device-local `AIHandoff` **onto** the synced section
meta, so it persists and reaches the iPhone. The live-`/c/`-vs-`/share/` constraint from Amd 3 carries
**unchanged** (capture the continuable link, never the read-only snapshot). Unlike Amd 1's polymorphic
`Learning` table, `PlaybookSectionMeta`'s `recipeID` is a **real FK to a single parent**, so cascade-delete
works and there are no synced orphans — the [ADR-0038 Amd 1](ADR-0038-external-llm-handoff.md) hand-cascade
problem does not recur here.

Governed by [ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md): the section **content** stays where
it lives (a singular blob is fine — it's *one* value, not a collection needing row-ids), but provenance and
URL become **typed fields**, never re-parsed out of the content blob.

### D7 — Copy: the verb carries the path; the brand noun lives in Settings

The two AI paths are disambiguated by their **verbs**, not a brand noun: **Hand off** (leaves the app to the
flat-rate external provider) vs **Ask** (the in-app on-device/cloud tier). "AI" is rejected as a label
*precisely because both paths are AI* — the noun discriminates nothing; the verb does. Section controls read
**Hand off / Redo / Paste / Open chat**, with a **spark icon** carrying the external signal. The provider
brand ("ChatGPT") appears **once**, as the AI-provider line in Settings (and optionally a one-time
empty-state hint), and is **never** stamped on per-section buttons. This is also **future-proofing**:
[ADR-0038](ADR-0038-external-llm-handoff.md) defers a Claude/ChatGPT provider choice, and brand-free verbs
mean flipping providers never re-strings the column. The live code string to change is the whole-recipe
`Hand off to ChatGPT` label (`RecipePlaybookView.swift:93`).

## Deferred (on the record, explicitly not built here)

- **Menu Playbook sections** ([ADR-0039 Amd 2/3](ADR-0039-playbook-column-thinking-vs-doing.md) — the shared
  Enrichment column) getting the same per-section toolbar. Same pattern; this ADR scopes to the **recipe**.
- **Section-selection checkboxes** on the whole-recipe hand-off ([ADR-0038 Amd 2](ADR-0038-external-llm-handoff.md)
  deferred these too). The scoped per-section verbs make choose-which-sections **less necessary**, not more.
- **A one-tap in-app "Regenerate" as the *visible* primary.** External-first per Jon; the in-app verb stays
  reachable via overflow / Ask (OQ4), not promoted.
- **Clipboard auto-detect of the `/c/` URL** is best-effort convenience; **manual paste is the contract**
  (the model inside a chat can't know its own URL — Amd 3's reasoning holds).

## Storage sketch

- **New synced `@Table PlaybookSectionMeta`** in `Models.swift` + migration in `Schema.swift`: `id: UUID`,
  `recipeID: UUID` (**real FK**, cascade on recipe delete), `sectionKind: PlaybookSectionKind`,
  `provenance` (`.chatGPTExternal` / `.inApp` / `.handAuthored`), `conversationURL: String?`,
  `dateModified: Date`. **Additive + synced** — add to `makeSyncEngine`'s table list *and* the standing
  prod-schema promotion list.
- **New `enum PlaybookSectionKind`** (`makeAhead`, `chefItUp`, `serveWith`).
- **`HandoffExportSource` gains** `.recipeSection(Recipe.ID, PlaybookSectionKind)`; **`AIHandoffTaskType`
  gains** `chefItUp`, `serveWith`.
- **No change to where section content lives** — `Recipe.makeAhead` / `chefItUp` / `serveWith` stay as they
  are; the meta is a sidecar, not a rehoming.

## Cost, honestly — and the slice plan

The in-app generate verbs, the ADR-0024 review sheet, the ADR-0038 Copy/Paste door, and the section render
all exist. What's new: the toolbar IA, the section edit sheet, the section dimension on the hand-off, and
the synced meta table. Sequenced so the IA lands first on existing content and schema comes last.

- **S1 — the toolbar + the section edit sheet (app-layer only, no schema, no new verbs).** State-aware
  per-section toolbar (D2) + per-section Edit sheet (D4) reusing ADR-0024; `Clear` relocated to overflow +
  sheet; wire the *existing* whole-recipe make-ahead hand-off as Make-ahead's section primary. Proves the IA
  on ground that already round-trips. [[lean-verification-default]].
- **S2 — the section-scoped external hand-off (core + app).** `HandoffExportSource` section dimension +
  task types + the **`matches(_:)` routing fix (D3)**; wire Chef It Up + Serve With Copy/Paste; rescope the
  recipe hand-off to `.makeAhead`. Classify Serve-With's list-shaped paste-back per [[chat-verb-commit-shapes]]
  (OQ3); wire any harvest verb with `requiresSubject:false` ([[harvest-verb-requires-subject-false]]).
- **S3 — the synced section meta + the conversation URL (schema + app).** `PlaybookSectionMeta` table +
  migration + sync-set; the `conversationURL` field in the review sheet *and* the edit sheet; the
  **"Reopen in ChatGPT"** deep-link; refine ADR-0038 Amd 3. **Gated on the same live-`/c/`-link device
  check Amd 3 already owes** — if the ChatGPT app only exposes the `/share/` snapshot, S3's URL half is a
  no-op until that changes (the meta + provenance still ship).

Verify per [[lean-verification-default]] — build + check-drift for the core; **Jon device-passes** the
per-section round-trip and the reopen deep-link.

## Open questions

- **OQ1 — inline columns vs sidecar meta (D6).** Recommend the sidecar; confirm at S3. Does `provenance`
  want more than `{ chatGPTExternal, inApp, handAuthored }` (e.g. which model / date-of-generation)?
- **OQ2 — Serve With is a list: one `conversationURL` per section, or per item?** Recommend **per section**
  (the *session* produced the set, not each row). Confirm at S3.
- **OQ3 — external hand-off for a list section (Serve With).** Does the existing editable-review round-trip
  carry a list cleanly, or does it need an ADR-0034-style bullet parse? Classify per
  [[chat-verb-commit-shapes]]; confirm at S2.
- **OQ4 — the section's existing in-app generate verb** (the `ChatApplyAction`s): keep reachable in overflow,
  or retire from the section UI in favor of external + Ask? **Lean: keep in overflow — don't delete working
  verbs.**
- **OQ5 — the column-top whole-recipe hand-off.** It *looks* redundant with per-section make-ahead, but it
  is not the same **kind** of thing: a whole-recipe export invites a **whole-recipe deliverable** back — which
  is the [ADR-0023](ADR-0023-recipe-edit-proposals.md) *"Adjust this recipe"* verb (transient preview →
  side-by-side → commit as **overwrite-with-undo** *or* **variation** per
  [ADR-0021](ADR-0021-recipe-variations.md)), **not** a Playbook-section verb. So the real fork is: **retire it
  from the section grid** and let whole-recipe-from-Chat live on the ADR-0023 adjust surface (which already
  owns the recipe-vs-variation commit choice), **or** keep a whole-recipe door here that routes into that same
  side-by-side review. **Either way, section verbs stay scoped:** a make-ahead hand-off that returns a full
  rewritten recipe must be parsed **lossless-or-loud** ([ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md))
  to its section and **flag the surplus**, never silently absorb a recipe into a `makeAhead` blob. Jon
  contemplating; the variation UI's fuzzy edges ([ADR-0021](ADR-0021-recipe-variations.md)) are a real but
  **separable** hardening item, not a blocker here. Decide at S2.

## Related

- [ADR-0039](ADR-0039-playbook-column-thinking-vs-doing.md) (the Enrichment column this lives in),
  [ADR-0038](ADR-0038-external-llm-handoff.md) + Amd 1/2/3 (the hand-off core, the in-app door, the
  `Learning` typed home, the `conversationURL` this relocates), [ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md)
  (the grain principle governing the section content + meta), [ADR-0024](ADR-0024-editable-proposal-preview.md)/[ADR-0026](ADR-0026-review-collection-sheet.md)
  (the review sheet reused as the section edit sheet), [ADR-0011](ADR-0011-actionable-chat-make-ahead.md)
  (the in-app generate verbs being scoped), [ADR-0021](ADR-0021-recipe-variations.md)/[ADR-0023](ADR-0023-recipe-edit-proposals.md)
  (commit destinations, if a section hand-off ever targets a variation/adjust).
- Memory: [[decompose-notes-into-typed-homes]] (why Notes is excluded and Learnings has its own home),
  [[editable-at-the-grain-stored]] (per-section edit + typed provenance), [[llm-curation-not-synthesis]]
  (why no blob-verb for Notes), [[automation-decays-near-the-stove]] (toolbar restraint),
  [[llm-vs-determinism-surface-boundary]] (external stays advisory), [[chat-verb-commit-shapes]],
  [[harvest-verb-requires-subject-false]], [[lean-verification-default]].
