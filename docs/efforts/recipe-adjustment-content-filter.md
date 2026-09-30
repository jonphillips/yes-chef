# Effort — Recipe adjustment: stop echoing recipe text, and report a provider-filter stop

Status: Done 2026-09-30 ([PR #330](https://github.com/jonphillips/yes-chef/pull/330)); device pass passed. Schema-free, `YesChefCore` only.
Summary: Recipe revisions fail on OpenAI with `stopReason=content_filter` because the adjustment prompt makes
the model copy whole method steps verbatim (copyrighted instruction text) as anchors. Stop requiring that echo
when an ID anchors the row, backfill the snapshot from our own copy, and give a provider-filter stop its own
error instead of the misleading "couldn't be read".
Related: [ADR-0021](../decisions/ADR-0021-recipe-variations.md) (variation anchors) · [ADR-0023](../decisions/ADR-0023-recipe-edit-proposals.md) (Adjust this recipe) ·
the variation anchor-repair work (Dispatch 0/1: normalize + degrade-not-throw)

## The problem (Jon, 2026-09-30)

A "make this vegetarian" revision returned this Xcode log line (`LoggingModelClient`):

```
response … tier=frontier/openai latencyMs=34772.2 stopReason=content_filter shape=json-object-or-truncated
text={"summary":…,"ingredientOps":[…],"methodStepReplacements":[{"baseStepID":"0D3D…","stepNumber":1,
"originalText":"Heat a large pot over medium-high for a minute or so … sauté until very soft and brown at the edges
```

- **The stop is from the provider, not the logger.** `content_filter` is OpenAI Responses
  `incomplete_details.reason` (`LLMClientKit/OpenAIWire.swift:216`).
- **It stops inside the first long verbatim quote of source text.** The prompt's schema asks for
  `"originalText":"exact current step"` on every step replacement (`RecipeAdjustment.swift` `instructions`).
  Short ingredient lines get through; a paragraph of published method text does not. This fits OpenAI's
  output filter against reproducing copyrighted text, and instruction prose is the copyrightable part of a
  recipe. This is inferred from one log, not proven. Fix 1 settles it.
- **The echo does nothing useful here.** Anchors resolve by `id` → `stepNumber` → `originalText`
  (`index(in:)`), and the model sent a real `baseStepID` for every op.
- **The user-facing error misleads.** `ModelResponse.wasTruncated` only knows `length`/`max_tokens`, so a
  `content_filter` stop fails JSON parsing and surfaces as `responseUnreadable` ("couldn't be read as a recipe
  adjustment").

## Fix 1 — IDs anchor; our copy is the snapshot

1. **Prompt (`RecipeAdjustmentClient.instructions`).** When `baseIngredientID` / `baseStepID` is given, the
   model sets `originalText` to null. Only when the ID is null does it quote the row, and for a step only the
   first ~10 words ("enough to identify it"). Apply the rule to ingredient refs too, so there is one pattern.
   Update the JSON schema example to match. Don't otherwise reword the prompt.
2. **Backfill on normalize.** The resolved anchor's `originalText` must come from the base row, never from the
   model. Today `normalizingAnchors(in:)` pins only `id` (method step replacements ~L257–263,
   `normalizedIngredientReferenceIfPossible`, `RecipeStepReference.normalizedIfPossible`). Set
   `originalText` from the resolved line or step too, the way `reanchoring(_:to:)` already does for repair. Do
   the same in `backfillingAnchors`. **This is required, not tidy-up:** the stored `originalText` is what
   the anchor-repair UI shows (`displayText`) when a base edit later orphans the anchor. Without it, the
   repair UI would show a UUID.
3. **Tests (`RecipeAdjustmentTests`).** A proposal with IDs and null `originalText` normalizes to the base
   text (ingredient remove/substitute/scale, step replacement, structural insert-after/remove). A model
   `originalText` that differs from the base is replaced by the base text once the ID resolves. The
   ID-less / prefix-quote fallback still resolves.

## Fix 2 — a provider-filter stop gets its own error

1. In `ModelResponse+Truncation.swift`, add `wasBlockedByProvider`: the stop reason is `content_filter`
   (OpenAI) or `refusal` (Anthropic), matched the way `wasTruncated` is (trimmed, case-insensitive). Add
   `StructuredModelResponseError.responseBlocked`, with a message along the lines of "The AI provider stopped
   this response (content filter). Try again, or switch providers in Settings."
2. **Every `wasTruncated` call site checks blocked first** (11 sites: MakeAheadPlan, ReaderFeedbackCuration,
   LabelProposer, MenuPrepPlan, WorkbenchCompareAligner, RecipeAdjustment, RecipeExtractionClient,
   RecipeEnrichment ×2, WorkbenchDraftRecipe, MealPlanMakeAheadStrategy). Throw `responseBlocked`, except
   where the site degrades instead of throwing (`WorkbenchCompareAligner` falls back to deterministic): there,
   degrade the same way it does for truncation. Keep each site's existing truncation error unchanged.
3. Tests: extend `MakeAheadPlanTruncationTests` (or a sibling) for `wasBlockedByProvider` matching, plus one
   `RecipeAdjustmentClient` test: a `content_filter` stop throws `responseBlocked`, not `responseUnreadable`.

## Out of scope

- Other verbs that legitimately reproduce recipe text (extraction from a captured page, workbench riff →
  new recipe) may hit the same filter. Fix 2 makes that legible; don't redesign them here.
- The outboard (ChatGPT/Claude) hand-off contract. This effort is the in-app extractor only.
- Changing `LLMClientKit`: stop reasons already pass through raw.

## Done when

Both fixes land with tests, `check-drift.sh` is green, and the owed device pass is recorded: re-run a
vegetarian-style revision on OpenAI against a recipe with long method steps; it completes and the review
shows the base step text.
