# Yes Chef Docs

The product and architecture brief for Yes Chef. This folder is the working source
of truth; `docs/CURRENT_HANDOFF.md` is the executor's rolling ledger, not the
contract.

## Core sentences

**Product:** Yes Chef is a private, local-first cooking operating system for one
serious home cook (and later, family members each with their own library) — a
next-generation Paprika that starts at recipe-library parity and layers on serious
planning, shopping, and grounded AI on top.

**Architecture:** SwiftUI multiplatform on the jon-platform house stack — SQLiteData
as the local source of truth, CloudKit-only sync with no server and no auth,
`@Observable` feature models with swift-navigation `Destination` enums, pure
repository functions over an explicit `Database`, value types, impossible states
made unrepresentable. Original imported text is never discarded; every persistent
change is migration-aware.

## Read in this order

1. [PRODUCT_BRIEF.md](PRODUCT_BRIEF.md) — the vision, primary user, and product bet.
2. [REQUIREMENTS_MVP_ROADMAP.md](REQUIREMENTS_MVP_ROADMAP.md) — functional
   requirements. **Note:** its §11 milestone numbering is superseded by
   [implementation-plan.md](implementation-plan.md) (see that doc for why).
3. [DATA_MODEL.md](DATA_MODEL.md) — the authoritative, §-numbered schema and the
   data-preservation rules. Read before touching the schema.
4. [IMPORT_EXPORT.md](IMPORT_EXPORT.md) — Paprika export/backup formats and the
   import metadata strategy.
5. [FUTURE_INTELLIGENCE_AND_PLANNING.md](FUTURE_INTELLIGENCE_AND_PLANNING.md) — the
   deferred planning/AI vision; explicitly post-parity.
6. [implementation-plan.md](implementation-plan.md) — the strategic arc and the
   clean milestone rebaseline. The build orders that implement it live in
   [milestones/](milestones/).
7. [open-questions.md](open-questions.md) — live ambiguities and recently-resolved
   decisions.

## Decisions, efforts, and reviews

- [decisions/](decisions/) — settled ADRs (indexed in [decisions/README.md](decisions/README.md)).
  Check before proposing architecture changes; don't re-litigate them.
- [efforts/](efforts/) — worked designs + slice plans that implement the ADRs
  (indexed in [efforts/README.md](efforts/README.md)). **Search here before writing a
  new effort or ADR** — per jon-platform `agent-workflow.md` § "Working docs stay
  discoverable."
- [reviews/](reviews/) — architect review passes (historical and ongoing).

## House layer

Yes Chef is the app-specific layer. The general "how Jon builds software" layer is
`~/code/jon-platform` — start at its `AGENTS.md`, then `docs/ios/` (swift-style,
persistence-and-sync, ui-and-platforms, ai-model-access, toolchain). Nothing here
overrides those unless a Yes Chef ADR says so explicitly.

## Working mode

Two agents build this repo under the architect/executor protocol
(`~/code/jon-platform/docs/agent-collaboration.md`): **Claude as architect** (owns
these docs, the ADRs, and the milestone build orders; reviews slice PRs) and
**Codex as executor** (one branch + PR per slice, green before ready). The milestone
build orders in [milestones/](milestones/) are the contract.

## Forthcoming (not yet written)

- `reviews/` re-baselining audit of current `main` — conformance of the existing
  code to the now-codified house rules; gates the first forward build order.
- `technical-architecture.md` — module/layout boundaries and the ratified Pass-1
  rules in one place.
- `milestones/M1-*.md` — the first forward build order, authored after the audit.
