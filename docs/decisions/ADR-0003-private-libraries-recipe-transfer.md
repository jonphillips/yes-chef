# ADR-0003 — Private libraries with recipe transfer (not a co-edited shared library)

Status: Accepted (supersedes an earlier draft that modeled one co-edited household library)

## Context

Yes Chef is used by a family — Jon, his wife, and the kids as they start cooking. The
first instinct was one shared household library. But the hard requirement is: **a
family member editing a recipe must never change anyone else's recipe.** People also
mostly don't want each other's whole libraries — most of Jon's recipes won't interest
his wife and vice versa. What's wanted is each person's own collection plus an easy way
to pass a recipe over.

A co-edited shared library can't satisfy "edits don't propagate" without copies, and it
would drag in the full CloudKit shared-zone machinery (shared root, single-FK sharing
tree, participant identity, per-person opinion rows, dedup races across people). That's
a lot of complexity for the wrong model.

## Decision

**Each person keeps their own private library; recipes move between people by transfer,
producing independent copies.**

1. **Private libraries.** A user's entire library lives in their own CloudKit **private
   database** — it syncs across their devices and is invisible to everyone else. No
   shared root, no co-editing, no share-accept flow for normal use. `favorite`,
   `rating`, tags, and notes are plain columns/tables; there are no per-person opinion
   rows or attribution columns inside a library (there's only one person in it).

2. **Transfer = copy.** Sending or publishing a recipe gives the recipient their own
   copy, re-keyed with **fresh UUIDs**. Editing any copy never touches another. This is
   what guarantees "edits don't infect."

3. **Phased sharing (see ROADMAP):**
   - **Phase 1 — Send a copy.** Serialize a recipe + its children + tag/category *names*
     into a self-contained bundle (a `.yeschef` file or universal link) via the system
     share sheet. The recipient imports it as a fresh copy; tag/category names reconcile
     against their own (find-or-create). **No shared CloudKit infrastructure.**
   - **Phase 2 — Family Cookbook.** A later, always-on shared CloudKit zone the family
     participates in, where members publish recipes for others to browse and copy. Same
     copy-on-adopt rule. This is the **only** part of the app using CloudKit *sharing*,
     and because published recipes are read-then-copy (never co-edited), it avoids the
     conflict/sharing-tree complexity a co-edited library would need.

## Consequences

- The core is a **single-user app** (per person). Most of the would-be shared-library
  machinery — `Household`, `Cook`, `RecipeOpinion`, attribution columns, the single-FK
  sharing tree, private-tables exceptions — is **deleted**, not built. This is a large
  simplification.
- UUID primary keys everywhere still hold (CloudKit private-DB sync needs them; transfer
  re-keys copies). Dedup-on-read still applies narrowly to name-unique entities (Tag,
  Category) because a user's own two offline devices can still race.
- The "transfer payload" (recipe bundle) is effectively another import/export format —
  it shares the import discipline in DATA_MODEL.md §29 (preserve original text/source).
- The house multi-user **co-edit** pattern (jon-platform persistence-and-sync, "shared
  library") deliberately does **not** apply here; the rest of the house stack
  (SQLiteData, CloudKit private-DB sync, UUID PKs, no server, no auth) does.
- Authoritative data-model detail: DATA_MODEL.md §2.6. Use the `pfw-sqlite-data` skill
  for the CloudKit-sync mechanics; verify SQLiteData's current private-DB sync API at
  the start of the sync milestone.
