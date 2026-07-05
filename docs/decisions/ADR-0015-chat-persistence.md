# ADR-0015 — Chat persistence / history (currently ephemeral)

**Status:** **Accepted** 2026-07-04 (opened same day from Jon's dogfood feedback). Queued as a near-term
effort in `docs/CURRENT_HANDOFF.md` — decoupled from the sync gate, so it may precede launch work.
**Owner:** Claude (architect) · Jon (product).

## Context

Jon, dogfooding 2026-07-04:

> "How hard/concerning to keep a log of chats by date and time? … It's even weird when I switch from the
> standard recipe view to the same recipe over on the meal planner and the chat window is clear."

Confirmed in code: chat is **ephemeral**. `RecipeChatModel` holds messages in memory, per host; there is no
chat table, nothing persisted, nothing synced. So a conversation vanishes on dismiss, and the "same" recipe
opened from a different surface (reader vs. meal-planner) starts blank — two independent in-memory models.

The intended workflow is to **distill** chat results into the recipe (make-ahead, Chef It Up, etc.) via the
apply-actions — the chat is a means, not an artifact. This ADR decides whether chat *also* deserves to be a
durable, revisitable artifact, and if so at what granularity and sync posture.

### Clarified ask (Jon, 2026-07-04)

> "What's annoying is I have to process everything I'm seeing because the minute I look elsewhere it's gone.
> Would be nice to let things bake for a second. I don't need to go back a year or anything. Just would be
> nice to keep the chat log around for a bit."

This **reframes the question**. It is neither of the two needs the first feedback pointed at (live cross-surface
continuity, or a dated browse-forever archive). It is a **third axis — retention lifetime**:

> **Recent chat should be durable, but bounded by retention — not archived forever.**

Consequences of the reframe:
- Rules **out** ephemeral (status quo) — losing the thread on a glance-away is the stated annoyance.
- Rules **out** the full synced dated-log — "I don't need to go back a year" is an explicit *decline* of that scope
  (and it's the expensive, sync-gate-touching option).
- In-memory continuity (share one model per subject) fixes only the *blank-on-surface-switch* half; it still dies
  on dismiss and relaunch, so it **under-shoots** "let it bake."

The target sits between: **persist chat to disk, keyed by subject, self-pruning after a retention window**
(survives navigation, dismiss, and relaunch; then ages out so it never becomes something to manage).

**Sync posture decided (Jon, 2026-07-04): local-only.** Chat persists on the device it happened on; it does
**not** ride CloudKit. This satisfies the entire clarified ask *and* keeps the feature off the sync-sensitive
spine — so it can be built now, without touching the sync gate.

## The question

Should chat conversations persist (a) at all, (b) with a date/time log, and (c) survive across the surfaces
that share a subject? If yes — what's the storage/identity model, and does it sync? *(Resolved by the clarified
ask + sync decision above: yes-persist, bounded-retention, local-only.)*

## Options (evaluated)

1. **Stay ephemeral (status quo).** Cheapest; leans fully on distill-into-the-recipe. **Rejected** — losing
   the thread on a glance-away is the stated annoyance.
2. **Per-subject in-memory continuity, still not persisted.** Share one chat model per subject (recipe /
   menu / planner day) so switching surfaces keeps the live thread — but it's still gone on relaunch.
   **Under-shoots** — fixes blank-on-switch but not "let it bake" (dies on dismiss/relaunch).
3. **Persist a synced chat log (new CloudKit table).** Dated history, cross-device. **Rejected as over-scope** —
   "don't need to go back a year" declines the archive, and it's the sync-gate-touching option.
4. **Persist a bounded-retention, local-only chat store. ← chosen direction.** A device-side `ChatMessage`
   store keyed by subject (recipe / menu / planner day), surviving navigation + dismiss + relaunch, pruned
   after a retention window. Not in the CloudKit schema. Satisfies the clarified ask; dodges the sync gate.

## Decisions

- **Persist? Yes.** **Sync? No — local-only** (Jon, 2026-07-04). Off the sync spine; buildable pre-launch.
- **Subject keying:** one thread per subject id — recipe id / menu id / planner day — so all surfaces sharing
  a subject open the same thread (fixes blank-on-switch as a side effect).
- **Retention: 1 month** (Jon, 2026-07-04). Time-based — prune messages older than ~30 days on launch/write.
  Simple, self-managing, generous enough to "let it bake," short enough to never become an archive.

## Open (to resolve before Accepted)

- **Local store mechanism:** does the local-only store still live in SQLite (a table CloudKit is told to ignore)
  or a separate lightweight store? Prefer the former if we can cleanly exclude it from the SyncEngine —
  confirm the mechanism ([[sqlitedata-blob-cloudkit-asset]] shows how the sync surface is defined).
- **Distill-vs-keep interaction:** persisted chat must not weaken the "distill into the recipe" habit — chat
  stays the means, the recipe stays the artifact.

## Consequences

Local-only means a future "sync my chat too" is a *later, additive* decision, not something this ADR forecloses
or front-loads. Keeps the pre-launch sync surface unchanged.
