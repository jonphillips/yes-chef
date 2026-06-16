# ADR-0001 — Persistence is SQLiteData, not SwiftData/Core Data

Status: Accepted

## Context

Yes Chef needs local-first persistence with future CloudKit sync. The obvious
Apple-native defaults are SwiftData or Core Data. But the house architecture
(`~/code/jon-platform/docs/ios/persistence-and-sync.md`) settles this for every one
of Jon's apps, and it is explicitly the *anti-SwiftData* decision.

## Decision

Persist with **SQLiteData** (the Point-Free library; SQLite/GRDB underneath).
**Local SQLite is the source of truth.** Records are plain value-type structs,
queried with `@FetchAll` / `@FetchOne` / StructuredQueries. **Not SwiftData, not
Core Data, not a hand-rolled SQLite layer.**

## Consequences

- No `@Model` classes and no reference-semantics object graph. Where the data model
  shows a recipe "containing" sections/lines/tags, those are flat tables joined by
  UUID foreign keys and materialized at read time via queries — not stored nested
  collections. See DATA_MODEL.md §2.6 and §35.
- Domain models are structs; the functional core (parsing, scaling, list combining)
  is pure functions over those structs — densely unit-tested.
- SQLiteData's CloudKit synchronization is what makes "no server" viable (ADR-0002),
  so this choice and the sync choice stand or fall together.
- The library moves fast: **verify the current SQLiteData API/version at the start of
  any persistence milestone** rather than working from memory. Use the `pfw-sqlite-data`
  skill for mechanics.
