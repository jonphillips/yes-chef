# Effort: Dogfood fixes — batch 2 (multiplier clip + AI provider picker)

**Type:** Bug fix + latent-capability surfacing. Two cohesive, design-free slices in one PR.
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/review)
**Status:** Ready — dispatched 2026-07-03. Runs **in parallel** with the cooking-workspace design
(Jon + Claude); nothing here waits on that design.
**Source:** open-questions.md § "Dogfooding — AI chat + recipe reader (2026-07-03)", the two
non-effort items (bug + cheap).

**Do both slices, in order, one PR.** Neither needs a layout decision.

---

## Slice 1 — Scale multiplier falls off the bottom in full-screen (bug)

The scale control lives in a `Menu` ("Scale Ingredients", `RecipeDetailView.swift` `ScalePanel`,
~line 674) anchored bottom-right. In the full-screen recipe presentation the menu clips below the
viewport and becomes unreachable — the multiplier can't be opened at all (Jon, screenshot 2).

- **Fix:** ensure the scale affordance is always reachable in the full-screen presentation — keep it
  pinned within the safe area (e.g. a toolbar/overlay anchor that can't clip off-screen) rather than a
  free-floating bottom-right menu that overflows. Match whatever the standard (non-full-screen)
  presentation already does if that one doesn't clip.
- **Scope note:** this is the tactical fix. The cooking-workspace effort will *structurally* relocate
  the scale control (always-reachable is one of its requirements), so keep this change small and
  localized — don't redesign the panel here.
- **Verify:** open a recipe in full-screen on `iPad Pro 13-inch (M5)` and confirm the multiplier is
  openable and usable; the scaled ingredient text still updates.

## Slice 2 — AI provider picker: Claude *or* ChatGPT, both keys in Settings

The LLMClientKit lift (ADR-0011 Slice 1) already shipped `OpenAIModelClient` / `OpenAIWire` and a
multi-provider `APIKeyStore`. `AISettingsView` only surfaces `.anthropic` today
(`AISettingsView.swift:58`). This slice surfaces the OpenAI path and lets a conversation choose its
provider. **No new backend** — mirror Galavant's provider-picker UI.

- **Settings (`AISettingsView.swift`):** add an OpenAI (ChatGPT) API-key field + save/clear, alongside
  the existing Claude field, both reading/writing `APIKeyStore` (`.anthropic` / `.openai`). Keep the
  per-provider status rows.
- **Provider preference:** add a stored preference for which frontier provider the recipe chat uses
  (`@AppStorage`, mirroring `recipeChatCustomInstructionsKey`). `RecipeChatModel`'s frontier tier reads
  it when assembling the client. If only one provider has a key, default to that one; if neither, the
  on-device floor still applies (unchanged behavior).
- **Confirm against Galavant:** match Galavant's existing multi-provider Settings shape so the two
  apps stay consistent (this is the pattern Jon referenced). Don't invent a new UI idiom.
- **Verify:** enter both keys; switch provider; confirm a completion round-trips on **device** for each
  (frontier tier needs a real device / no simulator Apple Intelligence). Confirm clearing a key falls
  back sensibly.

**Acceptance:** full-screen recipe multiplier is reachable and usable; Settings holds both a Claude and
a ChatGPT key; the recipe chat honors the selected provider and round-trips on device for each.

## Out of scope (deferred to the cooking-workspace effort)

- Dense full-screen reader redesign, chat-as-side-panel (sheet → inspector), and selection-scoped
  apply-actions (ADR-0011 Amendment 1) — all part of the unified cooking-workspace effort, which is in
  design (needs Jon's layout sketch) and is **not** this batch.
