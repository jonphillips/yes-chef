# ADR-0040 — LLM-populated content is human-editable **at the grain it is stored**

> **Two rules. (1) If the human can't address a row, the human can't edit it — so store LLM output at the
> grain you intend the human to manipulate. (2) The human never authors the serialization format — and any
> text we do parse is *lossless or loud*, never silently lossy.** Yes Chef keeps generating content the human
> can only regenerate, never fix. That is a schema defect masquerading as a missing button.

Status: **Proposed** — 2026-07-14. Origin: Jon, during the [ADR-0038](ADR-0038-external-llm-handoff.md) S3a
review — *"what is annoying about the prep plan is that it's an all-or-nothing proposition. I can't edit it,
I can't add a step, I can't delete a step. I almost have to manage it through an LLM."* Governs
[ADR-0034](ADR-0034-prep-plan-work-session-timeline.md) (the prep plan), ADR-0038 Amd 1 (Learnings),
[ADR-0024](ADR-0024-editable-proposal-preview.md) (the editable review sheet), and everything
[ADR-0039](ADR-0039-playbook-column-thinking-vs-doing.md) will hold. Extends
[[decompose-notes-into-typed-homes]] — the same principle, one beneficiary further on.

## Context — the prep plan can only be regenerated, never repaired

`Menu.prepPlan` is a **BLOB**: one JSON-encoded `[PrepPlanStep]` in one column
(`MenuPrepPlanCoding`, `MenuPrepPlan.swift:146`). There is no such thing as *step 3*. So there is no such
thing as deleting step 3, adding a step, fixing a typo, or reordering. Every affordance is impossible not
because nobody built the button, but because **the button has nothing to point at.** The only handle the
schema exposes is *the whole plan* — which is exactly why the LLM became the only way to change it. Jon did
not choose to manage his prep plan through a chatbot; the schema chose for him.

The one editing path that exists is worse than none: `editableReviewText()` /
`applyingEditableReviewText()` round-trips the plan through a **hidden text DSL** —
`session:` colon-terminated headers, `- task → serves` bullets, with a **U+2192 arrow the human cannot
reliably type**. And the parse is **silently lossy** by construction (`MenuPrepPlan.swift:74`):

- a line that doesn't parse is `continue`d — **dropped without a word**;
- a bullet before any session header is dropped (`guard let session`);
- `sourceDish` — a field the human can neither see nor type — is re-attached by **matching the task text**,
  so editing a task's wording **silently severs its recipe link**;
- the band vocabulary is *sniffed from prose* (`session.lowercased().contains("anytime" / "flexible" /
  "get ahead")`, `MenuViews.swift:491`), so a human rewording a heading can silently move a step out of its
  band.

So the single surface where a human edits LLM output is a format nobody told them about, in which a mistake
**deletes their work quietly**. The same defect already bit us inside ADR-0038 S3a: the first pass of the
Learnings commit path parsed bullets and dropped every non-bullet line the human typed.

Meanwhile the `learnings` table (ADR-0038 Amd 1) got the storage grain **right** — one row per learning,
addressable and deletable — and that was not luck: it is [[decompose-notes-into-typed-homes]]. The lesson
generalizes one step further than we wrote it down. **Granularity is not only an AI affordance. It is a
human-editing affordance.** Same property, two beneficiaries.

## Decisions

### D1 — Store LLM output at the grain the human will manipulate

If the human should be able to add / edit / delete / reorder a thing, that thing is **a row with an id**, not
an element inside an encoded blob. A blob is for content that is genuinely atomic (a prose paragraph), never
for a *list of things a human will want to fix one of*.

**Applies now:** `Menu.prepPlan` BLOB → a synced **`prepPlanSteps`** table (`id`, `menuID`, `sortOrder`,
`session`, `task`, `serves`, `sourceDish`). Learnings already comply. Future Playbook content (ADR-0039)
inherits the rule by default.

### D2 — The human never authors the serialization format

The `session:` / `- task → serves` DSL exists because **LLMs emit text**. It is a **transport** format — the
wire between ChatGPT and the parser — and it must never again be the **editing** interface. Humans edit
**fields**: a task field, a serves field, a session **picker** drawn from the known band vocabulary. No
typing colons. No typing arrows. No guessing which heading words put a step in the Flexible band.

This does **not** retire ADR-0024's editable review sheet. That sheet reviews an *inbound proposal* and is
the right place to edit prose before it commits. D2 says: once content is **committed**, the durable editing
surface is structured — you do not go back through the wire format to fix a typo.

### D3 — Any text we do parse is **lossless or loud**

Where we still parse human-touched text (the ADR-0024 review sheet, the paste box), an unparseable line is
**never silently dropped**. It is surfaced to the human — kept as-is, flagged, or refused with a specific
message. Silence is the bug. `applyingEditableReviewText`'s `continue`-on-junk and the S3a
`learningBullets` drop-the-non-bullet behavior are both **defects under this ADR**, not quirks.

Corollary: **hidden state must not be re-derived from text.** `sourceDish` re-attached by matching task
wording is exactly this — the link must ride on the row's identity, not on its prose surviving unedited.

### D4 — Do the prep-plan migration **before the prod-schema cut**

We are in CloudKit **Development** by design; `Menu.prepPlan` sits on the standing prod-promotion list but is
**not promoted**. Promotion is **additive-only and permanently locks the record type**. Restructuring the prep
plan from a BLOB into step rows is therefore **free today and expensive forever** after the first
prod/TestFlight cut. That deadline, not aesthetics, is what makes this urgent.

## Consequences

- **A migration with real data behind it.** `prepPlanSteps` rows are created by decoding the existing BLOB
  per menu (back-compat decode already exists for the ADR-0034 `when`→`session` key change). Keep the BLOB
  column readable through one release, then drop it. `learnings` and `prepPlanSteps` both join the
  prod-promotion list.
- **Sync.** `prepPlanSteps` is a real child of `Menu` — unlike `learnings` it **can** carry a proper FK and
  therefore a real cascade delete (no hand-cascade, cf. [[sqlitedata-single-fk-sync-limit]]: multi-FK is not a
  sync blocker).
- **Reads get scoped, not global.** Step rows load through the existing per-menu `MenuDetailQuery` — **never**
  a whole-library `@Fetch` ([[sqlitedata-fetch-writer-convoy]], ADR-0029 Finding 8).
- **The commit path shrinks.** `AIHandoffReturn` → parsed steps → **rows**. `applyingEditableReviewText`
  survives only as an *inbound* parser, not as the storage round-trip.
- **The band vocabulary must become explicit** (D2's picker needs a list). ADR-0034's horizon bands stop being
  sniffed from prose and become a known set with an "other / free text" escape.

## Rejected

- **"Just add an edit button."** There is nothing to edit. The blob is the disease; a button is a symptom
  patch that would still round-trip through the lossy DSL.
- **Make the DSL friendlier** (accept `->` for `→`, tolerate missing headers). Softens the trap without
  removing it: the human is still authoring a wire format whose failure mode is silent deletion.
- **Wait for ADR-0039.** The Playbook is milestone-sized and Jon-gated; the prod-lock window is not. The
  Playbook should *inherit* editable-at-grain content, not be blocked on inventing it.

## Slices

- **S1 — the Learnings surface** *(already queued as the ADR-0038 S3a follow-on; it is this ADR's first
  instance)*: read + per-row edit + per-row delete on the menu detail. No new AI, no new prompt.
- **S2 — prep plan → step rows.** Migration + `PrepPlanStepRepository` (add / edit / delete / reorder), the
  detail section becomes row-editable with a **session picker**, and the handoff/paste path writes rows.
  **Before the prod cut (D4).**
- **S3 — lossless-or-loud pass** on the remaining text parsers (review sheet, paste box): surface what didn't
  parse instead of dropping it.

**Sequenced ahead of [ADR-0038 S3b](../efforts/adr-0038-external-llm-handoff.md)** — S3b adds two more sources
writing LLM content into more fields, and it should inherit this rule rather than add three more places that
need retrofitting.
