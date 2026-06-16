# ADR-0002 — Sync is CloudKit via SQLiteData; no server, no auth

Status: Accepted

## Context

Recipes, notes, shopping lists, and plans need to be available across a family's
devices. The house architecture rules out hand-rolled sync engines and custom
backends — historically the heaviest, buggiest, lowest-value part of Jon's apps.

## Decision

Sync each person's library across **their own devices** via **CloudKit's PRIVATE
database**, using SQLiteData's built-in CloudKit synchronization. No custom server, no
sync/upload manager, no GraphQL client. **No auth** — the iCloud account is the
identity; there is no login/registration UI and no Keychain credential flow. Moving
recipes *between* people is a separate transfer feature, not co-editing (ADR-0003).

## Consequences

- Requires a **paid Apple Developer membership** (CloudKit needs it).
- Rules out Android/web clients and any server-side logic, by design.
- Sync debugging is eventual-consistency-on-real-devices with no server logs.
- The CloudKit schema basics bind every synced table from day one:
  - **UUID primary keys** everywhere.
  - **No unique indexes** beyond the primary key. Logical uniqueness is enforced by
    a code-level upsert **plus** dedup-on-read (pick one row per key
    deterministically; a cleanup pass deletes the losers). Even one person's two
    devices editing offline can each insert a duplicate — plan and test for it.
- Private-DB sync may be deferred in MVP 1, but the schema obeys these basics from the
  first table. The Phase-2 Family Cookbook (ADR-0003) is the only piece that uses
  CloudKit *sharing* (a shared zone + share-accept flow); it is a later milestone.
