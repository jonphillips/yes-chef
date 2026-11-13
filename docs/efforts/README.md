# Efforts index

Design/discussion + build-order docs for Yes Chef features. **The `decisions/` ADRs
record *what we decided*; these efforts hold the *worked design and slice plan*** that
implements a decision (or explores toward one).

**A brief's location is its status** (jon-platform ADR-0005 D10). This folder's root holds
only live briefs, and this index lists only them. Shipped, retired, superseded and parked
briefs live in [`archive/`](archive/), which needs no index: the folder listing and
[`../DONE-LOG.md`](../DONE-LOG.md) cover it. Parked work has a one-line candidate in
[`../open-questions.md`](../open-questions.md). For what's outstanding, run
`jon-platform/scripts/outstanding`.

**Authoring discipline** (jon-platform `docs/agent-workflow.md` § "Working docs stay
discoverable"):
- **Index at creation.** A new effort adds its one-line entry here in the same change.
- **Self-describing header.** Each live effort opens with `Status:` (one of **Designed**,
  **Ready**, **Dispatched**, **Blocked**) and a one-line `Summary:`; the entry below copies
  them.
- **Archive on completion.** The PR that finishes an effort runs
  `jon-platform/scripts/archive-brief` alongside its `DONE-LOG.md` entry and drops the row
  here. Parking or retiring a brief happens in a plan PR.
- **Search before authoring.** Before writing a new effort or an ADR, `grep -ri
  <topic> docs/` and read adjacent efforts, including `archive/`, and cross-link them.

## Live

- [Family cookbooks](family-cookbooks.md) — **Ready.** S0 is a debug-only spike: a second CloudKit container, a zone-wide read-only share from one Apple ID to another, a 2000-record publish and fetch, timed, with library sync left untouched. S1–S4 get briefed after its device result.
