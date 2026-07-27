# ADR-0047 — Capture escalates to an **LLM extractor** when the page carries no machine contract; capture pills are rejected

Status: **Accepted** — opened 2026-07-26 from Jon's Substack dogfood pass ("Browser needs capture pills like
Paprika … OR, better, we need to understand what the LLM can do to parse the page"); **ratified the same day
with all five open questions answered** (see Resolved). S1 is dispatchable. Extends
[ADR-0007](ADR-0007-web-recipe-capture-engine.md) (the harvested deterministic parser) and
[ADR-0009](ADR-0009-in-app-authenticated-browser-capture.md) (the rendered-DOM rung). Governed by
[ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) (lossless-or-loud) and
[ADR-0043](ADR-0043-model-call-chokepoint.md) (every model call declares itself).

## Context

**The capture path today contains zero model calls.** `WebRecipeCaptureClient` fetches, `WebRecipePageParser`
runs six deterministic extractors (JSON-LD → meta → microdata → Milk Street → body image → editorial prose),
and `RecipeAttributeVotes` reconciles scalars by source priority. That ladder has exactly two rungs:
static HTML, and — per ADR-0009 — the rendered logged-in DOM (`usedRenderedFallback`). Both rungs assume the
page ships a **machine contract**. When it doesn't, there is no third rung.

**The triggering page proves the gap.** Jon tried to capture
[Yotam's Turkey & Zucchini Meatballs](https://ciaosamin.substack.com/p/yotams-turkey-and-zucchini-meatballs)
(Samin Nosrat, *a grain of salt*). Verified against the live page:

- **No JSON-LD, no microdata, no hRecipe.** Three of the six extractors miss completely; capture can produce
  title, hero image, and prose, and nothing else. `warnings` comes back
  `[.noStructuredRecipeData, .noIngredients, .noInstructions]`.
- **But the HTML is clean and semantic.** Ingredients are `<ul>` bullets under two subheads ("For the Sour
  Cream & Sumac Sauce", "For the Turkey and Zucchini Meatballs"); directions are numbered steps under "Make
  the sour cream sauce" / "Shape the meatballs" / "Cook the meatballs". Not paywalled, not truncated.

So this is not a hard page. It is a page with **no contract** — which is the whole category the deterministic
ladder structurally cannot serve, and that category is most of the food writing worth capturing now
(Substack, personal sites, newsletters, forum posts). Adding `RecipeSubstackExtractor` next to
`RecipeMilkStreetExtractor` fixes one domain and leaves the category.

**The hook was already cut.** `WebRecipePageParser` keeps `bodyText` uncapped with the comment *"full
`bodyText` remains uncapped for later fallback extraction"*
([`RecipePageParser.swift:33`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/RecipePageParser.swift)).
This ADR is that fallback.

## Decision

### D1 — The LLM is **rung 3 of the existing ladder**, gated on warnings the parser already computes

Deterministic-first is not a new branch and not a heuristic. `ParsedRecipePage.warnings` already contains
`.noIngredients` / `.noInstructions` / `.noStructuredRecipeData`; the escalation predicate **is** that set.
A page carrying schema.org (NYT, Milk Street, every recipe blog with a plugin) never reaches the model —
it stays fast, free, offline-capable, and reproducible. **Never LLM-first**, and never "LLM to double-check
the deterministic result": a model that can overrule a machine contract is a model that can corrupt a clean
capture, and the contract is right far more often than not.

### D2 — Capture pills are **rejected**, not deferred

Paprika's pills (`Name` / `Description` / `Ingredients` / `Directions` / `Prep` / `Cook` / …, tap-to-assign
selected text) exist *because Paprika has no LLM*. They are a manual-labor UI for span→field assignment.
Three reasons not to build them:

1. **The correction surface already exists.** [`RecipeCaptureView`](../../YesChefApp/RecipeCaptureView.swift)
   is a fully editable review form over every one of those fields. Pills would be a **second** correction
   surface flanking the one that already ships, each fixing the same class of miss.
2. **They fix one page at a time, by hand.** The LLM fallback fixes the no-contract category once.
3. **They land on the wrong side of the effort curve.** Pills are the more expensive build (WKWebView
   selection → DOM range → field mapping, per ADR-0009's rendered-DOM plumbing) *and* the worse outcome.

**What is parked instead (S3, not now):** *selection-to-field* — highlight text in the browser, "Use as
Ingredients". That is ~80% of pills' value at a fraction of the build, and — critically — it is framed as a
**repair tool for the model's misses**, not as the primary acquisition path. Only build it if S1/S2 dogfooding
shows a residue the model can't reach.

### D3 — The model's input is a **structure-preserving serialization**, never `bodyText`

This is the sharp edge and the most likely way a naive implementation fails while looking like a
model-quality problem.

`cleanedBodyText` strips chrome, then calls `.text()` and whitespace-joins the result into **one flat
string**. On a page with a machine contract that loss is harmless — the contract carried the structure. On a
no-contract page, **the `<ul>` / `<ol>` / `<h#>` structure *is* the recipe boundary**: it is the only signal
distinguishing "8 ingredients under two subheads" from a paragraph of prose that happens to mention
ingredients. Flattening it and then asking a model to recover it is asking the model to redo work the DOM
already did.

So the fallback serializes the cleaned `Document` to a **markdown-ish** form — headings → `## `, `li` → `- `,
`ol` items → `1. `, paragraphs preserved as blocks — as a new pure function alongside the parser. `bodyText`
stays exactly as it is for the review/summary surfaces that already consume it.

### D4 — The output target is the **existing** `ParsedRecipePage`, not a new type

`ParsedRecipeIngredientSection` and `ParsedRecipeInstructionSection` both already carry an optional
section `name` alongside their lines/steps. That maps **exactly** onto Substack's "For the Sour Cream & Sumac
Sauce" / "Shape the meatballs" subheads. The extractor fills the same fields the deterministic extractors
fill, through the same `RecipeParseBuilder`, and everything downstream — review form, image hydration,
commit — is untouched. **No new draft type, no new review surface, no schema.**

### D5 — Extraction is licensed **only** because it terminates in a human review gate — and it may not invent

Per [[llm-vs-determinism-surface-boundary]]: capture is advisory-into-a-review-gate, not a reproducible data
merge. Nothing the model produces commits until Jon reads the form and taps Save. That is precisely the
surface where a model is allowed — and it is why this does **not** reopen ADR-0022's deterministic-grocery
line or ADR-0042's D2 (structured canonical writes stay in-app).

The binding constraint on top of that: the extractor **selects and structures text that is present on the
page**. It does not supply a missing quantity, infer an unlisted ingredient, or complete a truncated step.
This is the same fidelity-first rule that made [ADR-0032](ADR-0032-workbench-reference-material-fetch.md)
reject "put the URL in the prompt and let the model read it" — the one unacceptable failure for this app is
plausible-looking invented recipe content. A gap must come back **as a gap** so the review form shows it.

### D6 — Provenance is a **priority rung**, plus a declared `ModelCall`

`RecipeAttributeVotes` already ranks sources: `chromePriority = 0`, `microdataPriority = 1`,
`jsonLDPriority = 2`. LLM-extracted scalars enter at a **new rung below chrome** — so if a deterministic
source ever produces a value for the same attribute, it wins automatically, with no special-casing. "The
model never overrules the contract" becomes an integer, not a code path.

The call registers at the ADR-0043 chokepoint like every other (`surface: .capture`, its own task case), and
the review form marks model-extracted sections visibly so Jon knows which fields to read hardest.

### D7 — Budget for thinking **and** output; truncation throws

A whole recipe is a large structured output, and `maxTokens` is shared with reasoning
([[reasoning-budget-starves-output]]). A tight cap at high effort returns an empty or half-finished recipe
that looks like a parse failure. Budget generously — [[personal-app-latency-tolerance]] applies; this is a
user-initiated capture in a single-user app, and seconds are cheap next to retyping a recipe. A truncated or
unparseable response **throws loudly** and the capture falls back to today's behavior (prose + warnings). It
never silently yields a partial recipe: lossless-or-loud, per ADR-0040.

## What this costs — stated plainly

**This puts the first model call in the capture path**, which has been 100% deterministic since ADR-0007 and
is the path with the highest cost-of-error in the app: a bad capture becomes a recipe you cook from. Three
mitigations, all structural rather than careful: the model only runs where the deterministic path produced
**nothing** (D1), it can never outrank a deterministic source (D6), and it cannot commit anything (D5).

Second cost: capture stops being fully offline **on no-contract pages only**. Contract-bearing pages are
unaffected. Third: an extraction failure now has two possible causes (fetch vs. model), which the warning set
must keep distinguishable.

## Resolved (Jon, 2026-07-26) — all five open questions closed

- **OQ1 — tier: frontier by default.** "I'll happily *pay* to get it right." A whole-recipe extraction over a
  long input is precisely where [[reasoning-budget-starves-output]] bites, and a capture is a
  once-per-recipe, user-initiated action in a single-user app ([[personal-app-latency-tolerance]]) — the
  wrong economy to make. This is the **mirror image of [ADR-0035](ADR-0035-grocery-store-area-grouping.md)**,
  whose classifier is on-device *by design* because it is high-volume, low-stakes and re-runnable; this is
  low-volume and high-stakes. **"By default" is literal**: tier still resolves through the normal path, so
  the ADR-0045 D7 model setting and any degradation still apply — the default is frontier, not a hardcoded
  frontier-only call.
- **OQ2 — the share extension does not escalate. Confirmed.** The extension captures and stores exactly as
  today; escalation happens when the **app** opens the draft. The extension must never do network or model
  work — [[extension-sync-construct-not-run]] is the precedent for how expensively that fails.
  **Design consequence, binding:** `WebRecipePageParser.parse` is a **pure synchronous** function, so the
  escalation cannot live inside it. The gate sits at the existing async boundary
  (`WebRecipeCaptureClient` / the app-side draft open), reading the warnings the pure parser returned. The
  parser stays pure and model-free; the ladder gains a rung *above* it, not inside it.
- **OQ3 — the ladder: whole-page extraction, not per-gap.** When the gate fires, the model sees the whole
  serialized page and returns a whole recipe; D6's priority ladder then discards any half that a
  deterministic source already produced. Chosen over the cheaper per-gap ask because the ladder makes it
  **safe by construction** rather than by careful prompt scoping, and because a model asked for directions
  alone loses the ingredient list as cross-signal.
- **OQ4 — re-run is offered.** `ParsedRecipePage` retains `originalHTML`, so a re-run costs a model call and
  **no re-fetch** — which also means it works on a gated page captured while authenticated
  ([[paywall-gating-taxonomy]]) without re-authenticating. Lands in **S2** next to the provenance marking:
  the surface that says "this came from the model" is the surface that offers "try again".
- **OQ5 — per-site extractors stay allowed.** The fallback is the **floor, not the ceiling**. For a
  high-volume site, bespoke code is faster, free, offline, deterministic, and reproducible — all the
  properties the fallback trades away — so `RecipeMilkStreetExtractor` keeps its pattern and new ones are
  welcome where volume justifies them. The fallback's job is to make sure *not* writing one is never
  blocking: every site works on day one, and a per-site extractor becomes an optimization taken on evidence
  (repeat captures, cost) rather than a prerequisite for capturing at all.

## Slices

- **S1 — the fallback itself.** Structure-preserving serializer (D3) + escalation gate at the async boundary
  on the existing warnings (D1/OQ2) + the whole-page extraction `ModelCall` (OQ3) at the frontier default
  (OQ1) filling `RecipeParseBuilder` (D4) at the new vote priority (D6), with loud truncation (D7).
  Fixture-tested against the Samin page, plus a contract-bearing page asserting the model is **not** called,
  plus a partial page asserting deterministic halves survive the ladder. No UI.
- **S2 — review-surface provenance + re-run.** Mark model-extracted sections in `RecipeCaptureView`, surface
  the failure case distinctly from "page had nothing", and offer re-run off the retained `originalHTML`
  (OQ4).
- **S3 — selection-to-field. Parked** (D2). Build only if S1/S2 dogfooding leaves a real residue.
