# ADR-0018 — Prompt customization: a layered taste profile + per-task preferences

Status: **Accepted** (2026-07-05, resolved in design session with Jon). Realizes the **taste profile**
the code already anticipates (`LLMClientKit/ModelClient.swift`: *"The taste profile … is injected into
`system` by the boundary, not re-plumbed per feature"*) — an anticipated-but-unbuilt piece whose
placeholder ADR number was reused by chat-persistence, so it is recorded here for real. Paired with
**ADR-0017**; same files, one dispatch. Cross-repo: Layer A lives at the `LLMClientKit` boundary.

## Context

Today a user's preferences reach the model through **one** field —
`recipeChatCustomInstructionsKey` — and it is read in **exactly one place**
(`RecipeChat.swift:981`, the recipe-chat system prompt). Ask for a menu prep plan, a complement, or a
make-ahead plan and your preferences **never arrive**: those are separate `complete()` calls with their
own static `instructions`. So "I'm a serious home cook, I like bold flavors" informs recipe chat and
nothing else. That is the gap.

Jon's ask: when he says "chef it up," the model should *know* how he likes things chef'd up. The
temptation is to expose every prompt for editing — but that is the wrong move, and Jon named it as such.
Every AI call glues two kinds of text together:

1. **The machine-facing task prompt** — e.g. `MenuPrepPlan`'s *"Return ONLY strict JSON: {…} … Do not
   invent or rewrite per-dish make-ahead prose."* This is an **engineering contract**: output shape the
   parser depends on, tool protocol, guardrails. Editing it silently breaks features.
2. **Preference / persona text** — *"I cook on a gas grill and sous vide; push things
   restaurant-ambitious."* This is the user's.

**Rule: never expose #1 for editing; always expose #2.** The user owns preferences; the app owns
contracts. (A read-only "peek" at #1 was considered and **dropped** — overkill; Jon takes responsibility
for what he sets.)

## Decision

A **two-layer preference model** that composes behind — never replaces — each task's engineering prompt:

> **`[app task prompt]` + `[global taste profile]` + `[optional per-task preference]`**

### Resolved decisions (D1–D5, ratified by Jon 2026-07-05)

- **D1 — Layer A: one global taste profile, injected at the boundary.** A single rich free-text
  "who I am as a cook" profile is stitched into `ModelRequest.system` at the **`TieredModelClient`
  boundary**, so it reaches *every* frontier generative call with **zero per-feature plumbing** — the
  architecture the code already anticipates. This subsumes and replaces today's single-field custom
  instructions, and by construction closes the "preferences only reach recipe chat" gap.
- **D2 — Layer B: optional per-task preference snippets, gated to generative-judgment tasks only.**
  A small optional free-text field for the tasks where taste is *task-specific* — **Chef It Up, Serve
  With, make-ahead / prep plan, menu / meal complements**. It appends *after* the profile, *behind* the
  engineering prompt. **Lookup tasks get no field** — substitution, capture parsing, scaling are about
  correctness, not taste (Jon's own example). Net exposed surface: **1 global profile + ~4 task fields**,
  not "every prompt."
- **D3 — Threading Layer B.** The per-task preference is task-specific, so it can't be injected blindly
  at the boundary. Prefer a lightweight `taskKind` on `ModelRequest` that the boundary maps to *both*
  the global profile *and* that kind's stored preference (centralizes stitching, keeps "add a new
  customizable task" to a Settings field + a `taskKind` case). If that proves heavy in the slice,
  fall back to appending the preference at each of the ~4 call sites. Either way the engineering prompt
  stays authoritative.
- **D4 — Storage: synced across devices (resolved 2026-07-05, Jon).** Profile + per-task preferences
  **follow the user** — set them once and pick up any device (iPad / iPhone / Mac) without wondering
  "did I update the queries here too?" So they are **synced settings, not device-local `@AppStorage`**.
  Implement per the ADR-0010 sync playbook; a synced column must clear the **live-schema audit**
  ([[extension-sync-construct-not-run]], [[sqlitedata-blob-cloudkit-asset]]) — do not add it silently.
  (This retires the one-field `recipeChatCustomInstructionsKey` `@AppStorage`, whose device-local scope
  was itself a papercut.)
- **D5 — Settings UX.** `AISettingsView` gains: the global taste-profile editor (promoted from today's
  lone field) and a compact, collapsible per-task preferences section (the ~4 fields). Copy frames them
  as *preferences that shape every/this AI reply*, not as raw prompts.

### Why not

- **Why not expose the raw task prompts?** They carry output contracts; a user edit breaks parsing.
  Preferences give the control without the footgun.
- **Why not just widen the one existing field?** It only reaches recipe chat and it conflates "global
  me" with "how I want *this* task." The layered model reaches everything and separates the two.
- **Why not per-task for lookups too?** Nothing to tune — the answer is recall, not taste.

## Slice plan (one dispatch with ADR-0017)

- **S4 — Layer A taste profile at the boundary.** Promote the custom-instructions field to a profile;
  inject at `TieredModelClient`; verify it now reaches prep-plan / complement / make-ahead calls (the
  calls that get nothing today). This is the architecture rock.
- **S5 — Layer B per-task preferences.** `taskKind` (or per-call-site append) + the ~4 Settings fields
  for the generative-judgment tasks.

(Numbered S4–S5 to continue ADR-0017's S1–S3 within the shared dispatch.)

## Related

- **ADR-0017** (model + effort; same dispatch). ADR-0010 (sync/BLOB playbook, for D4).
- `LLMClientKit/ModelClient.swift` (the anticipated boundary injection this realizes).
- Memory: `llm-curation-not-synthesis`, `extension-sync-construct-not-run` (sync-audit guard).
