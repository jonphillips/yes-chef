# Open Questions

Live ambiguities and recently-resolved decisions. Resolved items stay here briefly
(dated) so the reasoning is durable, then graduate into the relevant doc or ADR.

## Resolved — 2026-06-28

- **Web recipe capture is its own milestone (M2), before sync.** A share extension is
  another write path; it must be idempotent before the iCloud one-way gate. See
  [milestones/M2-web-recipe-capture.md](milestones/M2-web-recipe-capture.md).
- **Harvest Galavant's capture engine, don't reinvent.** Same-stack, proven (JSON-LD/
  microdata votes, headless rendered-DOM). Re-target to schema.org/Recipe in YesChefCore.
- **In-app browser capture → M3.** Perfect it in Galavant first, then harvest.
- **App-group shared store now** (M2 Slice 3), coordinated with the sync CloudKit container.
- **Fallback is OpenGraph/meta + preserve-raw for M2;** photo → LLM recipe capture is the
  intended successor (its own later milestone) and the fallback for sites that resist
  structured extraction.

## Live — web-capture engine convergence

- **Converge YesChef + Galavant onto a shared capture-engine package (ADR-0007).** YesChef
  is already the second consumer; harvest-first only defers the abstraction until two working
  implementations exist. **Trigger: M2 close** (or Galavant's next capture-engine change).
  Tracked so it isn't forgotten — do not let the two engines drift permanently.

## Resolved — 2026-06-27

- **Rebaseline cleanly, don't retro-fit.** The roadmap §11 numbering is retired;
  forward work is renumbered from current reality. See
  [implementation-plan.md](implementation-plan.md).
- **Audit before forward.** The first architect act is a re-baselining review of
  current `main` for conformance to the now-codified house rules, before any new
  build order. It gates the M1 build order.
- **Order of the big three: stabilize → import → sync.** Architecture-debt paydown
  first, then import hardening, then CloudKit sync. Sync is last by design: it is a
  one-way gate, and enabling it before import is trustworthy would propagate
  throwaway re-imports across all devices and the private iCloud zone.
- **Menus are ratified product, not speculation.** Yes Chef is a next-gen Paprika:
  reach recipe-app parity, then differentiate. Paprika is the source for many
  baseline features (user files / formats: https://www.paprikaapp.com/help/ios/).
  The Menus subsystem stays; it likely earns its own ADR for the
  menu / meal-plan / grocery provenance model.
- **jon-platform did not drift.** The Pass-1 alignment items (repository core,
  persisted enums, observed-reads anti-pattern, identity-preserving saves,
  snapshot-as-interchange-format) all landed in jon-platform's `docs/ios/`. The open
  risk is whether Yes Chef's *code* conforms — which the audit settles.

## Foundation / audit

- Did the Pass-1 P0/P1 fixes actually land in the code before grocery/menu/
  meal-planning were built on top, or is that debt still present under the newer
  features? (The audit answers this.)
- Are the grocery, menu, and meal-plan reads observed (`@Fetch`/`@FetchAll`) or
  hand-pulled into `@State`? Are their saves identity-preserving?
- How much feature logic lives in views vs. `@Observable` models in the newer
  subsystems?

## Import / Paprika parity

- What is the concrete Paprika feature-parity gap list, derived from the live app
  rather than memory? (To be built when authoring Phase B.)
- Which Paprika export path is canonical for the real library import — HTML export,
  `.paprikarecipes` backup, or both reconciled? Which preserves the most fidelity
  (dates, categories, image resolution)?
- Does any high-value source need authenticated capture (ATK, Milk Street), and if
  so, when does that enter scope vs. the manual-HTML fallback?

## Menus / planning model

- Does the Menus subsystem need its own ADR, and what is the canonical provenance
  model linking recipe → menu → menu placement → calendar item → grocery source?
- Is "menu" vs "meal plan" vs "cooking plan" a clean three-concept split, or do two
  of them collapse?

## Sync

- What is the trigger that says "import is trustworthy enough to enable sync"? A
  concrete data-quality checklist, or Jon's judgment call on a real library?
- Can the private CloudKit zone be reset cheaply if a bad import does sync, or must
  we treat first-sync as effectively irreversible?

## House layer

- Any of these resolutions that generalize beyond Yes Chef (e.g. the
  "import-before-sync gate") — do they belong as a jon-platform note rather than an
  app-only one?
