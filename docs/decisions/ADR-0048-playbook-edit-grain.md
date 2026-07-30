# ADR-0048 — Playbook edit affordances are a **readout of storage grain**, not chrome drift; Serve With decomposes to rows

Status: **Accepted** — 2026-07-26. Both schema questions (OQ2 provenance, OQ3 sparse ordering) closed the same
day; **all four slices are specifiable and S1/S2 are dispatchable now.** Two implementation checks remain,
folded into the slices that own them (see Still open) — ratification covers the Decision, as with ADR-0032.
Opened from Jon's dogfood pass ("we need to unify the edit capabilities of
the Playbook section. Learnings seems most mature … edit in place, drag and drop to move. Whereas Chef it Up
is a singular edit panel and Reader Feedback requires an explicit edit tap and then strange scrollable Text
Edit windows"). Governed by [ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md); lives in
[ADR-0039](ADR-0039-playbook-column-thinking-vs-doing.md); continues
[ADR-0041](ADR-0041-playbook-section-toolbar-and-scoped-handoff.md), whose per-section edit sheets are the
chrome this is about.

## Context

The report reads as UI inconsistency — three sections, three edit interactions, no reason. **It is not.** Each
section's edit affordance is an accurate readout of how that section is stored, and the "maturity" ranking Jon
intuited is exactly the grain ranking.

| Section | Stored as | Presents as | Edit affordance today |
|---|---|---|---|
| **Learnings** | `@Table("learnings")` rows — `sortOrder`, `provenance`, `dateModified` | list | edit in place, drag to reorder |
| **Reader Feedback** | `@Table("recipeNotes")` rows (`noteType == .readerFeedback`) | list | explicit Edit tap → scrollable `TextEditor` per note |
| **Serve With** | **`Recipe.serveWith: Data?`** — a JSON blob | list | swipe delete (ADR-0041 Amd 2) |
| **Chef It Up** | `Recipe.chefItUp: String?` | list-ish | single edit panel |
| **Make Ahead** | `Recipe.makeAhead: String?` | list-ish | single edit panel |

**Three findings from reading the code, each of which changes what the fix is.**

### Finding 1 — Serve With has row identity and no row

`ServeWithItem` is `Identifiable` with a `UUID` ([`Models.swift:171`](../../YesChefPackage/Sources/YesChefCore/Models.swift)) —
and lives inside `Recipe.serveWith: Data?`, a JSON blob. **The identity exists; the table does not.** This is
the `Menu.prepPlan` defect ADR-0040 was written about, sitting in the Recipe, undetected because the section
is small enough that regenerate-instead-of-repair hasn't hurt yet.

**The codebase is already paying for it, in code.** `reconciledServeWithItems`
([`RecipeEnrichment.swift:380`](../../YesChefPackage/Sources/YesChefCore/RecipeEnrichment.swift)) exists for
exactly one purpose: to carry item UUIDs across a whole-blob rewrite, by matching
`$0.title == suggestion.title && $0.note == suggestion.note`. A row table gives that for free. Worse, the
match is on **content**, so editing an item's title silently mints a new UUID and drops the old identity —
the failure mode is invisible and unrecoverable.

### Finding 2 — Make Ahead and Chef It Up *look* like lists because of a display-time split

`PlaybookEnrichmentDisplayText` documents itself: *"Multi-line paragraphs read as a list in the Playbook,
while a single-line paragraph remains prose."* So two sections render as bulleted lists while being stored as
**one string**, split on newlines at render time. That is why the single-panel editor feels arbitrary to the
cook: the surface promises a list and the editor delivers a paragraph. The editor is telling the truth; the
*renderer* is the thing making a promise the storage can't keep.

### Finding 3 — `ServeWithCoding.decode` loses data silently

```swift
public static func decode(_ data: Data?) -> [ServeWithItem] {
  guard let data else { return [] }
  return (try? JSONDecoder().decode([ServeWithItem].self, from: data)) ?? []
}
```

A malformed or schema-drifted blob presents as **"no Serve With items"** — indistinguishable from a recipe
that never had any. Straight ADR-0040 lossless-or-loud violation, and it is on the read path any migration
would run through.

## Decision (proposed)

### D1 — Do not unify by making the chrome uniform

The instinct the report invites is "make all five sections edit the same way." That would mean building
row-style affordances over blob storage — inline add/delete/reorder that decode, mutate an array, and rewrite
the whole blob. It would look unified and would reintroduce the prep-plan defect in four places at once:
every "row" would still be un-addressable, un-syncable at the item level, and repairable only by rewriting its
neighbours. **Unify the grain, and the affordances follow.**

### D2 — One shared row editor, adopted by the sections that are genuinely row-grain (no schema)

Extract the Learnings interaction — inline `TextField` edit, swipe delete, `onMove` reorder — from
`LearningsSection` ([`MenuPrepPlanEditingViews.swift:157`](../../YesChefApp/MenuPrepPlanEditingViews.swift))
into one shared component. **Reader Feedback adopts it immediately**: it is already `recipeNotes` rows, so its
"explicit Edit tap → scrollable `TextEditor`" is pure UI artifact with no storage justification. This slice
is free of schema and is most of what Jon actually asked for.

### D3 — Serve With decomposes to a `recipeServeWith` table

It is a list of identified items that the cook should be able to add, fix, delete and reorder one at a time —
ADR-0040's definition of a row. Decomposing deletes `reconciledServeWithItems` outright (identity stops
needing reconstruction), lets the shared D2 editor cover a third section, and makes per-item edits
sync-granular instead of whole-blob-last-writer-wins.

**Its own typed table, not a reuse of `learnings`.** `Learning` is keyed by `(sourceType, sourceID)` and would
technically hold these, but a new content kind gets its own typed home rather than being dumped into a
generic one ([[decompose-notes-into-typed-homes]]).

### D4 — Make Ahead and Chef It Up stay prose, and the *renderer* stops implying otherwise

They have no per-item identity, no per-item consumer, and nothing anchored to their lines — decomposing them
would be schema built on a display-time newline split. So: single-panel editor stays, and it is **correct**.
What changes is Finding 2's mismatch — either the section reads as prose, or, if the list rendering is worth
keeping, it is understood as formatting rather than as a promise of row editing.

**The two sections flip on different triggers, and neither has fired.** They are deferred together in S4, but
for unrelated reasons — collapsing them into one "revisit later" hides that Make Ahead is the near case and
Chef It Up is the speculative one:

- **Make Ahead → rows when [ADR-0034](ADR-0034-prep-plan-work-session-timeline.md) composes the menu prep
  plan *structurally*.** This is the near case, and it is the ADR's own named graduation path, not a fresh
  idea: the design *already* asserts the menu prep plan "compose[s] from stored Make-Ahead"
  ([[menu-planner-dogfood-2026-07-09]]), and a Make Ahead line **is** a prep task with a horizon — "make the
  dough 2 days ahead" is `{step, when: 2day}` in [[prep-plan-horizon-redesign]]'s bands. What holds the flip
  today is that the composition is currently **LLM prose** (`AIHandoffContext`, *"Compose a short sequence
  of…"*), not a structured read of item identity — so decomposing now would be orphaned schema
  ([[withdraw-not-defer-orphaned-schema]]). When ADR-0034 makes that read structural, Make Ahead decomposes
  **in that effort** (carrying a `when`/horizon field from day one, so it is *not* a plain `recipeServeWith`
  clone), never as a 0048 backfill.
- **Chef It Up → rows only if dogfooding shows per-item *curation*.** Weaker, and it flips on a different
  argument than Make Ahead: it has no downstream consumer and plausibly never will (it is terminal advice,
  not an input to another surface). Its only path to rows is the *Serve With* argument — keep/dismiss/reorder
  of regenerated suggestions. But unlike Serve With it arrives here as a bare `String?` with **no identity
  being minted and dropped**, so it pays no ADR-0040 tax while it waits; there is nothing bleeding to justify
  building on spec. The firing condition is observed behaviour — Jon pruning the model's Chef It Up list item
  by item the way he does Serve With — not a downstream consumer. Until then it is a product question, and
  the answer is "prose."

### D5 — `ServeWithCoding.decode` becomes loud, independent of D3

Fix it whether or not the decomposition ships: a failed decode must report, not return `[]`. It is also the
migration's read path, so it must be trustworthy **before** D3 runs, not after.

## What this costs

**One new synced table.** Cheap — the app already registers ~30, for a handful of users
([[synced-table-cost-calibration]]) — and, importantly, **not orphaned schema**: its consumer (the D2 editor)
ships in the same effort, which is the test [[withdraw-not-defer-orphaned-schema]] sets. Pre-production is the
reason to do it **now** rather than the excuse to defer it, the same call ADR-0042 OQ2 made for `workbenchLog`.

The migration is small (decode existing blobs → insert rows → drop the column's use) but it is a real data
migration on a table that syncs, so it wants the D5 loud decode ahead of it and a device pass behind it.

**Honest scope note:** D2 alone answers most of Jon's complaint and costs nothing structurally. D3 is the part
that is genuinely about storage, and it would be defensible to ship D2 and stop — except that Serve With is
where the identity-preserving hack already lives, so stopping leaves the one section that is actively paying
the ADR-0040 tax.

## Slices

- **S1 — the shared row editor** (no schema). Extract from `LearningsSection`; Learnings and Reader Feedback
  both adopt it. Reader Feedback loses the Edit tap and the scrollable `TextEditor`.
- **S2 — loud decode** (D5). Small, standalone, prerequisite to S3.
- **S3 — Serve With → `recipeServeWith` rows.** Table (sparse `sortOrder` + its own provenance enum, see
  Resolved), migration, `reconciledServeWithItems` deleted, Serve With adopts the S1 editor. Register with
  the `SyncEngine`. **The regeneration path upserts by identity and preserves hand-authored rows** — a
  delete-and-reinsert reproduces the very identity loss this slice exists to remove, so that is the slice's
  primary test, not a detail.
- **S4 — deferred**: Make Ahead / Chef It Up. Not scheduled, and *not one slice* — D4 gives them separate
  firing conditions: Make Ahead decomposes inside the [ADR-0034](ADR-0034-prep-plan-work-session-timeline.md)
  structural-compose effort (with a `when`/horizon field); Chef It Up only if dogfooding shows per-item
  curation. Neither has fired.

## Resolved (Jon, 2026-07-26) — both schema questions closed; S3 is specifiable

### OQ2 — `recipeServeWith` **carries provenance**

But **not `LearningProvenance`.** That enum is `{externalHandoff, inApp}`
([`AIHandoff.swift:178`](../../YesChefPackage/Sources/YesChefCore/AIHandoff.swift)) — it distinguishes the
**transport** a learning arrived through, and *both* of its cases are model paths. The distinction Serve With
needs is **authorship**: did the model suggest this dish, or did the cook type it? Reusing the enum would
record `inApp` for a hand-typed item and quietly answer the wrong question. So `recipeServeWith` gets its own
provenance enum expressing model-suggested vs hand-authored, populated from the ADR-0043 record on the
model path.

*Noted, not fixed here:* `Learning` has the same conflation — hand-authored learnings (ferry effort Slice H)
land on `.inApp` alongside in-app model output. Out of scope for this ADR; worth an issue.

### OQ3 — **sparse** `sortOrder`, reusing `LearningOrdering.rankStride` (1024)

Same reasoning as `Learning`: a human moves one item at a time across synced devices, so a reorder should
update only the moved rows rather than rewriting every row in the group and inviting a sync conflict.

**The consequence that must be built in, because it is how this ADR fails silently:** Serve With is *also*
regenerated wholesale by the verb. If regeneration **deletes and re-inserts**, the table reproduces exactly
the identity loss D3 exists to fix — new UUIDs, new ranks, any hand-authored item and any hand ordering
destroyed. So the regeneration path **upserts by identity and preserves the hand-authored rows and their
ranks**; it does not clear the group. New suggestions take fresh sparse ranks at the end. `provenance` (OQ2)
is what makes this decidable at all — you cannot preserve the cook's items if you can't tell which ones are
theirs, which is why these two answers are one design and not two.

### Amendment — malformed legacy blobs remain repairable

Loud decode is right for an interactive read, but it must never run fatally inside a migrator. The migration
tolerates a per-recipe decode failure, preserves the original bytes, and reports the issue; detail loading then
detects that precise decode failure and offers non-blocking repair. A validated repair writes deterministic rows
and clears the legacy blob through the normal synced user-action path.

## Still open (implementation checks, folded into their slices — do not block dispatch)

- ~~**OQ1** — does Reader Feedback keep multi-line bodies?~~ **Closed 2026-07-26 by reading the code, before
  any slice ran.** `LearningRow` already uses `TextField(…, axis: .vertical).lineLimit(2...6)`, so prose fits
  the shared component with no new capability. **But the check turned up a different limit on D2:**
  `RecipeNote` has **no `sortOrder`** column, so Reader Feedback cannot reorder. Reorder is therefore an
  **opt-in capability** of the shared component rather than an assumption — and `RecipeNote` does **not**
  gain a `sortOrder` to make the shape uniform, because nobody asked to reorder reader feedback and that
  would be schema with no requirement behind it.
- **OQ4 → S3.** ADR-0021 variations are display-time overlays that fold on read. Confirm the decomposition
  doesn't create a write path an active variation would silently capture
  ([[recipe-variations-overlay]]: editing with one active writes to the base).
