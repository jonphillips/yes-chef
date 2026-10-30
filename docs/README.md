# Yes Chef Docs

The product and architecture brief for Yes Chef. This folder is the working source
of truth. `docs/NEXT_UP.md` is the executor's one dispatch ticket, not the contract
(jon-platform ADR-0005).

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
   [milestones/](milestones/) while live and move to
   [milestones/archive/](milestones/archive/) when finished (all of M1–M4 and grocery are archived).
7. [open-questions.md](open-questions.md) — live ambiguities and recently-resolved
   decisions.

## Decisions, efforts, and reviews

- [decisions/](decisions/) — settled ADRs (indexed in [decisions/README.md](decisions/README.md)).
  Check before proposing architecture changes; don't re-litigate them.
- [efforts/](efforts/) — worked designs + slice plans that implement the ADRs. The root
  holds only live briefs (indexed in [efforts/README.md](efforts/README.md)); shipped,
  retired and parked briefs live in [efforts/archive/](efforts/archive/). A brief's
  folder is its status (jon-platform ADR-0005 D10), so finishing or parking one means
  moving it with `jon-platform/scripts/archive-brief`, never marking it Done in place.
  **Search both before writing a new effort or ADR** — per jon-platform
  `agent-workflow.md` § "Working docs stay discoverable."
- [milestones/](milestones/) — the committed arc's build orders, same rule: live in the
  root, finished in [milestones/archive/](milestones/archive/).
- For what's outstanding, run `jon-platform/scripts/outstanding`; no doc here is a status page.
- [reviews/](reviews/) — architect review passes (historical and ongoing).
- [work-intake.md](work-intake.md) — the full dispatch protocol behind `AGENTS.md` § Work Intake.
- [product-principles.md](product-principles.md) — recipe-model, UI, import, AI, and style
  principles plus the original MVP scope (moved out of `AGENTS.md` to keep it lean).

## Operator setup

- [CHATGPT-SETUP.md](CHATGPT-SETUP.md) — install and maintain Jon's shared `Yes Chef` ChatGPT Project; its version-controlled Project artifacts live in [chatgpt/](chatgpt/).

## House layer

Yes Chef is the app-specific layer. The general "how Jon builds software" layer is
`~/code/jon-platform` — start at its `AGENTS.md`, then `docs/ios/` (swift-style,
persistence-and-sync, ui-and-platforms, ai-model-access, toolchain). Nothing here
overrides those unless a Yes Chef ADR says so explicitly.

## Working mode

Two agents build this repo under the architect/executor protocol
(`~/code/jon-platform/docs/agent-collaboration.md`): **Claude as architect** (owns
these docs, the ADRs, and the milestone and effort briefs; reviews slice PRs) and
**Codex as executor** (one branch + PR per dispatch, green before ready). The dispatch
is [NEXT_UP.md](NEXT_UP.md), which points at the live brief sections that are the contract.

## Forthcoming (not yet written)

- `technical-architecture.md` — module/layout boundaries and the ratified Pass-1
  rules in one place.
