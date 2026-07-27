# Effort: LLM capture fallback — pages with no machine contract (2026-07-26)

**Type:** New capture rung. Core-heavy (`YesChefPackage`) plus thin app-layer wiring; **no schema.**
One dispatch, four slices (S1a–S1c ship together, S2 follows).
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Ready to dispatch.** Design is ratified — [ADR-0047](../decisions/ADR-0047-llm-capture-fallback.md),
Accepted 2026-07-26 with all five OQs closed. **Do not re-decide anything in the ADR.**

**Read before starting:** [ADR-0047](../decisions/ADR-0047-llm-capture-fallback.md) in full (it is short and
every decision here is load-bearing), then [ADR-0043](../decisions/ADR-0043-model-call-chokepoint.md) (every
model call declares itself — this adds one), then `CURRENT_HANDOFF.md` Verification Pattern.

**Reference failure:** <https://ciaosamin.substack.com/p/yotams-turkey-and-zucchini-meatballs> — no JSON-LD,
no microdata, no hRecipe; `warnings` returns `[.noStructuredRecipeData, .noIngredients, .noInstructions]`.
Clean semantic HTML: two named `<ul>` ingredient groups, numbered `<ol>` steps under subheads.

---

## The findings that shape this dispatch

### Finding 1 — there are four capture entry points and **not all of them are async**

This is the one that decides the shape. `WebRecipeCaptureClient`
([`WebRecipeCaptureClient.swift`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/WebRecipeCaptureClient.swift)):

| Entry point | Signature | Used by |
|---|---|---|
| `capture(url:capturedAt:)` | `async throws` | URL capture; already holds the two-rung ladder |
| `browserCapture(html:sourceURL:capturedAt:)` | **synchronous** | **the in-app browser — the path Jon used for Substack** |
| `capture(sharePayload:capturedAt:)` | `async throws` | share extension |
| (app re-opens a stored draft) | — | extension hand-off |

So the escalation **cannot** just be appended to `capture(url:)`'s existing `page.isEmpty` ladder — the
failing path is the synchronous one.

**Design (falls straight out of ADR-0047 OQ2): a separate `escalate(draft:) async -> WebRecipeCaptureDraft`
on the client**, which the **app** calls after whichever capture path produced the draft. One implementation,
uniform across all four entry points, and the share extension satisfies "never escalates" simply by never
calling it — no flag, no conditional, nothing to get wrong.

**Do not make `browserCapture` async** to force it into the old shape; that changes an unrelated call site's
concurrency for no benefit.

### Finding 2 — the ADR-0043 taxonomy has no case for this

`ModelCallSurface` is `{grocery, mealPlan, menu, reader, recipe, workbench}` — **no `capture`**.
`ModelCallTask` has no extraction case. Both need one, and per ADR-0043 D2 a call site that bypasses the
chokepoint **fails a test**, so this is part of the slice, not follow-up.

### Finding 3 — the document cleaning must be **shared**, not duplicated

`cleanedBodyText` is `private` inside `WebRecipePageParser` and does real work before `.text()`: strips
`script`/`style`/`nav`/`header`/`footer`/`aside`/cookie/consent/breadcrumb, then `removeLinkDenseBlocks`. The
new serializer needs **exactly that cleaned document** — it differs only in what it does afterward (preserve
structure vs. flatten). Extract the cleaning to one function both call. A second copy of the strip list will
drift.

---

# DISPATCH — the fallback rung (S1a–S1c in one PR; S2 after Jon's device pass)

## SLICE S1a — `RecipeStructuredTextSerializer` (pure Core, no model)

Extract the cleaning (Finding 3), then add a sibling pure function that serializes the cleaned `Document` to
**markdown-ish** text: `h1…h6` → `## `, `li` in `ul` → `- `, `li` in `ol` → `1. `, `p` → its own block,
blank line between blocks. Everything else falls back to text.

**Why this exists, so it does not get "simplified" away later:** `bodyText` is `.text()`-flattened and
whitespace-joined. On a contract-bearing page that loss is harmless — the contract carried the structure. On
a no-contract page **the `<ul>`/`<ol>`/`<h#>` structure *is* the recipe boundary**, and it is the only signal
separating "8 ingredients under two subheads" from prose that mentions ingredients. `bodyText` stays exactly
as it is for the review/summary surfaces that already consume it. **Do not feed `bodyText` to the model.**

**Acceptance:** fixture test over the Samin page HTML asserting the serialization retains both ingredient
subheads, both bullet groups, and the numbered steps as distinct lines. Pure function, no I/O, no model.

## SLICE S1b — `RecipeExtractionClient` + the taxonomy cases + `escalate(draft:)`

1. **Taxonomy** (Finding 2): add `ModelCallSurface.capture` and a `ModelCallTask` extraction case.
2. **Client.** Follow `GroceryCategorizationClient` exactly — a `Sendable` struct with a `DependencyKey`,
   `liveValue` / `testValue`, static `instructions` / `prompt` / `parse`, built through `ModelCall(...)` and
   run with `.complete(using: modelClient)`.
   - **Tier: frontier by default**, resolved through the normal path so the ADR-0045 D7 setting and
     degradation still apply. Not a hardcoded frontier-only call.
   - **Budget for thinking *and* output** — a whole recipe is a large structured response and `maxTokens` is
     shared with reasoning. The 1,024 default is far too small; size it deliberately and say why in a comment.
   - **Truncated or unparseable ⇒ throw.** Never return a partial recipe. Lossless-or-loud
     ([ADR-0040](../decisions/ADR-0040-editable-at-the-grain-it-is-stored.md)).
   - **The model may not invent.** `instructions` must say it selects and structures text present on the
     page — never supplies a missing quantity or infers an unlisted ingredient. A gap comes back as a gap.
3. **`escalate(draft:)`** (Finding 1) on `WebRecipeCaptureClient`: if the draft's `warnings` contain
   `.noIngredients` or `.noInstructions`, serialize (S1a) → extract → merge; otherwise return the draft
   untouched.
4. **Merge through `RecipeParseBuilder`** into the **existing** `ParsedRecipePage` — its
   `ParsedRecipeIngredientSection` / `ParsedRecipeInstructionSection` already carry an optional section
   `name`, which is exactly the Substack subheads. **No new draft type.**
5. **Vote priority.** LLM scalars enter at a new rung **below `chromePriority` (0)** in
   `RecipeAttributeVotes`, so any deterministic value wins by arithmetic rather than by a branch.

**Acceptance:** three fixture tests — the Samin page yields ingredients and instructions; a contract-bearing
page (reuse an existing JSON-LD fixture) asserts the model client is **never invoked**; a page with
ingredients but no instructions asserts the deterministic ingredients survive the merge unchanged.

## SLICE S1c — wire the app's capture entry points

Call `escalate(draft:)` after capture at the app-layer entry points (browser capture, URL capture, and the
app's open of an extension-stored draft). **The share extension does not call it** — ADR-0047 OQ2; the
extension must never do network or model work.

Surface the in-flight state — extraction is a frontier call and will not be instant. A capture that silently
sits for several seconds reads as a hang.

**Acceptance:** capturing the Substack page in the in-app browser produces a populated review form.

## SLICE S2 — review-surface provenance and re-run

1. Mark model-extracted sections in `RecipeCaptureView` so Jon knows which fields to read hardest.
2. Distinguish "the model failed" from "the page had nothing" — today both are an empty form.
3. **Re-run**, off the retained `ParsedRecipePage.originalHTML`: a retry costs a model call and **no
   re-fetch**, so it also works on a page captured while authenticated.

**Acceptance:** the Samin capture shows its extracted sections as model-sourced; re-run re-extracts without a
network fetch.

---

## Explicitly out of scope

- **Capture pills** — rejected outright by ADR-0047 D2, not deferred. Do not build a span→field assignment UI.
- **Selection-to-field** (highlight in the browser → "Use as Ingredients") — parked as S3 in the ADR, to be
  built **only** if S1/S2 dogfooding leaves a real residue.
- **Retiring per-site extractors.** ADR-0047 OQ5 explicitly keeps them: the fallback is the floor, not the
  ceiling. Do not touch `RecipeMilkStreetExtractor`.
- **LLM-first or LLM-verifies-deterministic.** The gate is the warning set; a model that can overrule a
  machine contract can corrupt a clean capture.

## Verification

Core-heavy, so most of it lands where `scripts/check-drift.sh` actually runs — S1a and S1b are package tests.
S1c and S2 are `YesChefApp/` and therefore need the elevated `generic/platform=iOS` build as required
evidence. No simulator install; Jon does the device pass on the Substack page.
