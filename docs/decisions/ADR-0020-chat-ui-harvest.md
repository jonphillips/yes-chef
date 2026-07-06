# ADR-0020 — Chat UI harvest: a shared `LLMChatUI` package above LLMClientKit

Status: **Proposed** — 2026-07-06 (architect + Jon, during Recipe Workbench S1 dogfooding).
Extends [ADR-0011](ADR-0011-actionable-chat-make-ahead.md) (the LLMClientKit lift — the transport
boundary) with the *presentation* layer. Follows the harvest-now/converge-later pattern established
for the capture engine ([[galavant-capture-engine-reuse]], ADR-0007): dogfood in one app, lift to
jon-platform once the shape is proven and a second real consumer exists. Yes Chef is the **first real
consumer** of the chat shell; Galavant is the intended second.

> **Correction (2026-07-06 convergence audit — [`docs/audits/2026-07-06-convergence-audit.md`] in
> jon-platform):** this ADR's original premise — "Galavant has no honest chat instance yet" — is
> **stale**. Galavant now has a working but minimal chat panel (`ChatPanelView` over
> `GalavantChat.ChatModel`); the raw-markdown parity fix and the tier picker already landed there,
> though stop/clear, apply-actions, and persistence are still absent. So gate (b) below (a second
> real consumer) is **largely met** — extraction is still *not yet*, but the hold now rests on gate
> (a) (panel churn) alone, not on the absence of a second consumer. Signal to lift: the next chat
> papercut fixed twice.

## Context

Every chat surface in Yes Chef — recipe, menu, workbench, meal-plan; compact sheet and iPad split —
already routes through **one model class** (`RecipeChatModel`) and **one shared panel**
(`RecipeChatPanel`, wrapped by `ChatWorkspaceSplit` on iPad). We will move this chat interface to
Galavant; we were dogfooding it in Yes Chef deliberately. The question is *when* and *where* to lift the
UI, not *whether*.

Two layers are tangled in "the chat interface":

- **Generic shell (reusable):** the panel, split/detent layout, message list + streaming render, input
  bar, send/stop/clear controls, the tier/provider picker, the text-selection UITextView bridge.
- **Domain glue (per-app):** `RecipeChatContext` and its cases + grounding serialization,
  `RecipeChatStore` persistence (SQLite-schema-bound), the concrete apply-actions (Chef It Up, Serve
  With, the S2 draft verb), system-prompt construction.

Key finding (2026-07-06 audit): the shell is **already almost clean**. `RecipeChatPanel` never
pattern-matches domain cases (`.recipe`/`.workbench`/…). It touches only self-describing context
accessors (`context.title`, `.subject`, `.providerContextWarning`, `.seededContextDescription`), the
generic model surface (`messages`, `isResponding`, `send`, `useFrontier`, `selectedProvider`,
`availableProviders`), and a **type-erased** `[AnyChatApplyAction]`. The lift is therefore a protocol
extraction + file move, not a rewrite.

## Decision

1. **Where — a new sibling package `LLMChatUI` (SwiftUI), depending on LLMClientKit. Never inside
   LLMClientKit.** LLMClientKit is headless (no `import SwiftUI`) and has non-UI consumers (share
   extension, potentially server). Folding SwiftUI in would force it onto every consumer and collapse the
   transport/presentation layering. Stack: `LLMClientKit` (transport) ← `LLMChatUI` (presentation).

2. **What lifts:** the generic shell, parameterized over a small `ChatModel` / `ChatContext` protocol
   capturing exactly the surface the panel already uses. **What stays per-app:** the domain glue above.
   Galavant supplies its own context type, persistence, and actions conforming to the same protocols.

3. **When — not yet.** Lift only when **both** hold: (a) the panel has stopped churning (the "Chat
   controls" slice — tier-memory + clear + stop — plus Workbench S2/S3 have landed), and (b) Galavant
   work genuinely reaches for chat, so the seam is extracted against **two real consumers**. Until then,
   dogfood in Yes Chef. Lifting mid-churn would pay the cross-repo tax (two-repo PRs, version bump, git
   dance) on every papercut.

4. **Seam discipline now (cost: nothing).** Write ongoing chat work *as if the panel already lived in
   `LLMChatUI`*: the shell talks only to the model's public surface + generic context accessors — never a
   domain-case pattern-match, never a direct SQLite reach. It is clean today; the rule is "don't regress
   it." If a change tempts the panel to switch on a domain case, that is the smell that the protocol needs
   another generic accessor instead. Add `clear()`/`stop()` as generic model methods and keep the controls
   in the shared panel — which the Chat-controls slice does anyway, so that slice *hardens* the seam for
   free.

## Consequences

- The eventual lift is a near-mechanical protocol pull + file move rather than an untangling.
- One more package in the jon-platform stack; Yes Chef and Galavant both take `LLMChatUI` as a path-dep
  when the time comes (mirrors the LLMClientKit path-dep from ADR-0011).
- Feeds back to a Galavant-side ADR (the Galavant home of the decision) and eventually a jon-platform
  cross-app ADR, same trajectory as actionable chat.

## Open questions (resolve at lift time, not now)

- Exact protocol surface (`ChatModel` vs. also a `ChatContext` protocol; where grounding/system-prompt
  construction sits).
- Whether the apply-action framework (`AnyChatApplyAction`) lifts with the shell or stays app-side behind
  the protocol.
- Persistence abstraction: does `LLMChatUI` define a `ChatMessageStore` protocol, or stay storage-agnostic
  and let the host own persistence entirely?
