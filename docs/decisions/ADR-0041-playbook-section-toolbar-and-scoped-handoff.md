# ADR-0041 — Playbook sections become self-serve units: a per-section toolbar and a section-scoped hand-off

> **Vocabulary:** a *Playbook section unit* is a single Enrichment-column section (Make-ahead, Chef It Up,
> Serve With) treated as a **self-contained, independently-actionable unit**: its own state-aware toolbar,
> its own **section-scoped** external hand-off verb, its own editable content + provenance + optional
> live-conversation URL, edited in **its own sheet** — pulling per-section editing off the monolithic
> recipe edit sheet. The organizing move is to stop treating the Playbook column as one blob of sections
> with a single whole-recipe hand-off, and start treating each section as a small addressable object.

Status: **Accepted** — 2026-07-17 (Jon greenlit **S1** for dispatch; **all open questions resolved**
2026-07-17, incl. OQ3 by a live ChatGPT paste-back taste — S2 un-gated). Origin: Jon's 2026-07-17 design
discussion (toolbar-efficiency per section + the conversation-URL want). **Lives inside [ADR-0039](ADR-0039-playbook-column-thinking-vs-doing.md)**
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
- **Retire the column-top whole-recipe "Hand off to ChatGPT" button** (OQ5, resolved): the existing
  whole-recipe export (`.recipe` → `.recipeMakeAhead`) becomes **Make-ahead's section hand-off**, explicitly
  `.makeAhead`. Whole-recipe-from-Chat is **not** a section action — it routes through the
  [ADR-0023](ADR-0023-recipe-edit-proposals.md) *"Adjust this recipe"* surface instead.

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

## Amendment 1 — a return never stomps existing content, and the toolbar collapses into the overflow (2026-07-18)

Two findings from the S2 review (PR #205) + Jon's device look at the shipped column. Both are corrections to
D2/S2 as built, not new scope.

### Amd1-D1 — A section return is **merge-or-choose**, never a silent replace

**The defect.** S2 pairs two decisions that are individually right and jointly lossy. Outbound, a section
hand-off **excludes the current section** so it regenerates fresh ([[handoff-stateless-both-directions]]) —
so the model *cannot* echo your existing content back. Inbound, the commit **replaces wholesale**
(`updateChefItUp` / `commitMakeAheadText` for the blobs; `replaceServeWithPlan` for the list, which drops
every row absent from the return). Fresh-out + replace-in means a `Hand off again` on a **filled** section
silently discards hand-authored content. Serve With is the worst case: whole user-curated rows vanish.

**The fix belongs on the return side.** Do *not* solve it by putting the current section back in the prompt —
that reverses the regenerate-fresh rule for the wrong reason. Refinement belongs in the live chat.

- **List sections (Serve With) — lossless union prefill.** The review sheet's `editableText` is seeded with
  **existing lines first, then returned lines**, exact-dedup on `title: note`. The human deletes what they
  don't want; nothing is lost unless they delete it. `reconciledServeWithItems`
  (`RecipeEnrichment.swift:310`) already matches on `title == && note ==`, so surviving rows **keep their
  existing UUIDs** — no row churn, no sync thrash. Replace-on-commit stays the only write path; it is simply
  no longer lossy, because the box now starts out containing everything.
- **Blob sections (Make-ahead, Chef It Up) — an explicit commit choice, no default.** Two prose blobs cannot
  be unioned meaningfully, and concatenating two make-ahead plans is a mess to edit. On an **empty** section
  the commit is just *Save*. On a **filled** section the review item offers **Replace** *and* **Append**,
  with **no pre-selected default** — the human picks. This is the one place a section commit is destructive,
  so it is the one place we make the destruction an explicit act.
- **Both — show what's at risk.** `ChatApplyReviewItem` already carries `supportingEvidenceTitle` /
  `supportingEvidenceRows` (`RecipeChat.swift:603`), unused on this path. Populate them with the section's
  current content under *"Currently saved."* Surfacing the stakes in the review sheet is what would have
  made this visible before it was a defect.

Governed by [ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md): the list section merges **at row
grain** because that is the grain it is stored at; the blob sections cannot merge and therefore must **ask**
rather than guess.

### Amd1-D2 — The section toolbar collapses into a single `•••`; this **supersedes D2**

**D2 is reversed on prominence.** D2 made *Hand off* a prominent, filled-tint primary in the empty state to
honor external-first. On device that renders as three sections each showing two filled buttons — the column
shouts on **every view** for actions taken a few times a week. Jon's rule decides it: *these buttons are
viewed far more often than they are clicked.* The calm column outranks the nudge; you already know the verb
exists.

- **Every section action lives in one `•••` menu** — Hand off, Paste, Edit / Write manually, Ask, Clear.
  The button row is **removed entirely** (reclaiming its vertical space).
- **The `•••` moves into the section header row**, right of the fill-dot: `Chef It Up ○ ••• ⌄`. It renders
  **only when the section is expanded** — collapsed sections keep D2's `title + fill-dot + chevron` calm.
- **`PasteButton` is retired here, and this is a real trade.** `PasteButton` is a system-rendered
  `UIPasteControl`; its whole bargain is *implicit* pasteboard access with no permission alert, which Apple
  grants only for a control the user visibly and unambiguously taps. **It therefore cannot render inside a
  `Menu`** — that is precisely what the API is designed to prevent. Paste becomes a plain `Button` reading
  `UIPasteboard.general.string`, which raises the system *"Allow Paste?"* alert. **Accepted by Jon
  (2026-07-18):** the grant is scoped to the current pasteboard contents, so it is roughly **one alert per
  hand-off round-trip**, not per tap — one extra tap on a weekly action, in exchange for removing a cost paid
  on every view. Gate the row on `UIPasteboard.general.hasStrings` (which does **not** prompt) so it is
  disabled when there is nothing to paste.

The [[automation-decays-near-the-stove]] restraint D2 claimed is what Amd1-D2 actually delivers.

## Amendment 2 — destructive section actions are explicit, and Serve With rows use the native gesture (2026-07-19)

Jon's device pass found two destructive affordances too close to routine navigation, plus one list interaction
that did not match the rest of the app. These are focused refinements to the recipe Playbook column; they add
no storage and do not change the section hand-off contract.

- **Clear confirms before writing.** Every filled section's `Clear` menu item now presents one section-scoped
  destructive confirmation dialog. It names the section and states that there is no undo, because clearing is
  a permanent write reachable from the shared `•••` menu.
- **Clear leaves the section editor sheet.** This is a deliberate **partial reversal of D4**: D4 put Clear in
  the editor sheet so every section action had a home, but the proximity to Cancel made it too easy to
  fat-finger. Clear now lives only in the overflow menu, behind its confirmation; the editor remains a
  review-and-save surface.
- **Serve With adopts swipe-to-delete.** The always-visible red `x` is replaced with the platform delete
  gesture, matching the app's list rows and keeping the content column visually quiet. The action remains
  accessible by the item's name.

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
  recipe hand-off to `.makeAhead`. Serve-With's list paste-back is the existing editable-round-trip shape
  (**OQ3 resolved** — pin the `title: note` format in the outbound prompt, strip `**`/`*` emphasis from the
  parsed title, else unchanged); wire any harvest verb with `requiresSubject:false`
  ([[harvest-verb-requires-subject-false]]).
- **S2.5 — non-destructive returns + the collapsed toolbar (app + core, no schema).** Amendment 1: the
  Serve With union prefill, the blob Replace/Append choice, `supportingEvidenceRows` showing what's at risk,
  and the D2-superseding collapse of every section action into one header `•••` (retiring `PasteButton`).
  Follows S2's merge; independent of S3.
- **S3 — the synced section meta + the conversation URL (schema + app).** `PlaybookSectionMeta` table +
  migration + sync-set; the `conversationURL` field in the review sheet *and* the edit sheet; the
  **"Reopen in ChatGPT"** deep-link; refine ADR-0038 Amd 3. **Gated on the same live-`/c/`-link device
  check Amd 3 already owes** — if the ChatGPT app only exposes the `/share/` snapshot, S3's URL half is a
  no-op until that changes (the meta + provenance still ship).

Verify per [[lean-verification-default]] — build + check-drift for the core; **Jon device-passes** the
per-section round-trip and the reopen deep-link.

## Open questions

- **OQ1 — RESOLVED (2026-07-17, Jon): the synced `PlaybookSectionMeta` sidecar (D6b)**, not inline columns.
  Sub-question left open — does `provenance` want more than `{ chatGPTExternal, inApp, handAuthored }` (which
  model, date-of-generation)? Decide at S3 once the corpus says whether it's needed.
- **OQ2 — RESOLVED (2026-07-17, Jon): one `conversationURL` per section**, not per item — the *session*
  produced the whole set. Falls out of the D6b key `(recipeID, sectionKind)`: Serve With gets **one** meta
  row, not one per suggestion.
- **OQ3 — RESOLVED (2026-07-17, Jon's live ChatGPT taste): the Serve With list round-trips cleanly; S2
  un-gated.** *Method:* a hand-run of the S2-shaped outbound prompt (recipe context → accompaniments → pinned
  `title: note` per-line, "no bold, no bullets, no intro") through ChatGPT, then the reply through the **real**
  `cleanedEditableReviewLine` + `suggestion(fromEditableReviewLine:)` — **7/7 items parsed clean, zero junk,
  zero leakage; no cleaning branch even fired.** Two conclusions: **(1) format-pinning is the load-bearing
  fix** — when the outbound prompt names the exact shape, ChatGPT complies; it is prompt text, not parser
  work. **(2) the [ADR-0024](ADR-0024-editable-proposal-preview.md) review sheet is the real junk filter, not
  the parser** — a stray bold title or prose line (should a future run produce one) lands in the editable
  review where the human deletes it before commit, and title-only items are *legal* so the parser cannot
  auto-reject colon-less lines anyway. **S2 hardening is therefore minimal:** strip markdown emphasis
  (`**` / `*`) from the parsed title; otherwise reuse the existing `editableReviewText()` /
  `applyingEditableReviewText()` round-trip unchanged. The list uses the editable-round-trip commit shape that
  already exists ([[chat-verb-commit-shapes]]).
- **OQ4 — RESOLVED (2026-07-17, Jon): the section overflow's in-app affordance is "Ask" (section-scoped) —
  no direct per-section generate button, and the distill verbs stay in Ask's catalog.** *Finding:* there is
  **no** per-section generate button today — make-ahead / chef-it-up / serve-with generation lives **only in
  the Ask panel** as `AnyChatApplyAction`s that **distill a conversation** (they consume chat `selection` +
  `messages` and are **not** `requiresSubject:false`, `RecipeDetailModel+Enrichment.swift:108–124`). So the
  in-app verb is *conversation-distillation*, not standalone one-tap generation — **complementary** to the
  external hand-off (which exports for a *fresh* chat), not redundant, so it is neither retired from Ask nor
  duplicated as a section button. A **direct** per-section generate was rejected: firing a
  conversation-consuming action with no chat open is the [[harvest-verb-requires-subject-false]] dead branch.
  The section overflow **opens Ask**, optionally pre-scoped to that section.
- **OQ5 — RESOLVED (2026-07-17, Jon): retire the column-top button; route whole-recipe through ADR-0023.**
  The whole-recipe hand-off is not a Playbook-section action — a whole-recipe export invites a **whole-recipe
  deliverable**, which is the [ADR-0023](ADR-0023-recipe-edit-proposals.md) *"Adjust this recipe"* verb
  (transient preview → side-by-side → commit as **overwrite-with-undo** *or* **variation** per
  [ADR-0021](ADR-0021-recipe-variations.md)). So the column-top "Hand off to ChatGPT" button is **removed from
  the Playbook column** (D3); *"hand off the whole recipe"* becomes **"Adjust this recipe → via ChatGPT,"**
  landing in the existing ADR-0023 side-by-side review with its two commit destinations — **one verb, one
  review, no new recipe-commit path.** The recipe-vs-variation choice is the human's at review time (already
  ADR-0023's contract), never a routing decision here. **Section verbs stay scoped regardless:** a make-ahead
  hand-off that returns a full rewritten recipe is parsed **lossless-or-loud**
  ([ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md)) to its section and **flags the surplus**, never
  absorbing a recipe into a `makeAhead` blob. **Do not** build a bespoke "recipe back from Chat" landing that
  bypasses 0023/0021; the variation UI's fuzzy edges ([ADR-0021](ADR-0021-recipe-variations.md)) are a
  **separable, non-blocking** hardening item on their own track.

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
