# Work intake & dispatch — the full protocol

The rules themselves are summarized in `docs/AGENTS.md` § Work Intake (same numbering);
this is the reasoning and detail behind them. Moved here verbatim on 2026-09-29 to keep the
always-read guide lean.

## Work Intake & Dispatch (full text)

There is **one front door** for "what do I work on": `docs/CURRENT_HANDOFF.md`. Work flows
through a single funnel, not two competing plans:

```
docs/open-questions.md  → ideas, unscoped (e.g. comment ingestion)
docs/milestones/*.md    → the strategic arc/plan (milestones + ordered slices; the sync gate)
docs/efforts/*.md       → scoped, ready-to-build briefs (a milestone slice OR an off-arc item)
docs/CURRENT_HANDOFF.md → the dispatcher: Next Up (one item) + Ready Efforts (the queue)
a pull request          → the handoff out
```

An **"effort"** is the executable unit of work. It is the generalization of a milestone-slice
handoff to also cover work the milestone arc cannot express (defects, spin-offs). A milestone
slice, when approved to build, *becomes* an effort — usually a thin pointer
("M3 Slice 6 — build per the milestone doc §Slice 6, plus these deltas"), never re-specced.

`CURRENT_HANDOFF.md` has two distinct parts:

- **Next Up** — the single dispatch target. Usually one designated effort with a pointer to its
  brief, but it **may bundle several cohesive slices** into one dispatch (one PR) — see the batching
  rule below. Either way it is *one* dispatch. Jon and the architect curate it; the coding agent
  never chooses it.
- **Ready Efforts** — the ordered queue of scoped, ready briefs. Not a dispatch target; it is
  where Next Up is drawn from.

Rules:

1. **Dispatch trigger.** Jon dispatches with: *"Do the Next Up effort in `docs/CURRENT_HANDOFF.md`."*
   The coding agent reads `Next Up`, opens the referenced brief, and implements that — nothing else.
2. **Never infer the next task.** If `Next Up` is empty, missing, or ambiguous, **STOP and ask
   Jon.** Do not pick from Ready Efforts, the milestone doc, or anywhere else on your own.
3. **Curation is the architect's job.** When an effort merges or a slice is approved, the
   architect proposes the promotion and writes the new `Next Up` pointer + brief. Detail lives in
   the effort brief (or the milestone slice it points to), not in chat.
4. **The handoff points, it does not duplicate.** For slices already specced in a milestone doc,
   the brief references that section rather than copying it, so there is one source of truth.
5. **Batch cohesive slices by default.** Each dispatch pays a large fixed tax — cold-start, reading
   the house rules, re-exploring the codebase, and PR ceremony — that scales with the *number of
   dispatches*, not the amount of work. So the architect's default when curating Next Up is to
   **bundle cohesive slices into one dispatch/PR**, decoupling review granularity (stay fine) from
   dispatch granularity (amortize). Bundle when slices **share files and a mental model**; keep them
   separate when a slice has a real chance of being wrong or of changing direction based on a prior
   slice's outcome (batching is amortization — only a win when the whole batch is likely right). When
   a dispatch bundles slices, Next Up lists them in order and the agent does all of them under one PR.
   The architect still thinks and reviews at slice resolution.
6. **Keep the handoff lean; archive the rest.** `CURRENT_HANDOFF.md` holds only Next Up, the Ready
   queue, and the Verification Pattern. Completed-slice history, the implemented-behavior checkpoint,
   and strategic background live in `docs/DONE-LOG.md` (append-on-approval, read-rarely). No dispatch
   instruction points at `DONE-LOG.md` — it is a human archive, kept out of working context on purpose.
7. **On approval, MOVE — don't mark.** "Mark done" is the leak that bloats the handoff into a
   changelog. When a slice/effort is approved, the completed write goes to `DONE-LOG.md` (newest
   first) **and the corresponding block is deleted from `CURRENT_HANDOFF.md`** — both riding the same
   approved PR branch. The handoff only ever gains a **forward** edit (advance Next Up, draw the next
   effort from Ready); it never gains a backward one. **Litmus test:** *if the sentence you're adding
   to `CURRENT_HANDOFF.md` describes finished work, it belongs in `DONE-LOG.md` instead.* A "✅ DONE"
   line, a celebratory header, or an "earlier and logged" PR recitation left in the handoff is a
   process bug, not a record. The one exception: an **owed-but-non-blocking** verification (a device
   or CloudKit gate) stays as a single-line debt under Next Up until Jon clears it — not as a
   done-narrative.
