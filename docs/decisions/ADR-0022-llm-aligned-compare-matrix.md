# ADR-0022 — LLM-aligned Compare matrix (semantic row alignment + role ordering)

Status: **Accepted** — 2026-07-07; **shipped** S1–S4 (yes-chef PRs [#116](https://github.com/jonphillips/yes-chef/pull/116)
parse fix / [#117](https://github.com/jonphillips/yes-chef/pull/117) / [#118](https://github.com/jonphillips/yes-chef/pull/118) /
[#119](https://github.com/jonphillips/yes-chef/pull/119) the LLM aligner) + the Compare→chat affordance
([#120](https://github.com/jonphillips/yes-chef/pull/120)). See `docs/DONE-LOG.md`. Originally proposed as
an architect sketch. Builds directly on **ADR-0019** (the Recipe Workbench, whose S4 Compare
matrix this refines), the deterministic comparison-key slice ([PR #114], now the *fallback* not the
solution), and the **LLMClientKit structured-output house pattern** (ADR-0011/0012 actionable chat,
ADR-0017 effort tiers). Governed by [[llm-curation-not-synthesis]]. Draws the **LLM-vs-determinism
boundary** first drawn by the grocery milestone ([[grocery-pantry-threshold-design]], Decision #5).

## Context

The Workbench **Compare** matrix (ADR-0019 S4) aligns its rows on a **deterministic** canonical key.
[PR #114] split that into a coarser `CanonicalIngredient.comparisonKey` so form variants
(`fresh`/`frozen`/`dried`) collapse onto one base row. That helped the trivial cases — and a dogfood
pass on real recipes (Jon, 2026-07-07, ~4 beef-birria recipes) shows it hitting a hard ceiling the
deterministic approach **structurally cannot** clear:

- **Spelling / morphology variance** — `guajillo chile` vs `guajillo chiles` vs `guajillo chilies` land
  on different rows (the naive singularizer even mangles `chilies → chily`, splitting them further).
- **Semantic equivalence** — chicken **breast** and chicken **thigh** are doing the same *job* ("the
  chicken"); `morita` and `chipotle` are interchangeable for the dish's *role*. No string logic knows
  this; it needs world knowledge.
- **Parse garbage poisoning keys *and* labels** — the parser leaks quantity/unit fragments into the
  item field on dual-unit and metric-first lines, so rows read `/ 1.8 kg beef`, `To 45 g ancho chile`,
  `1¼ ounces ancho chily`. Garbage in → garbage key → garbage row, unmatched against clean columns.
- **No notion of culinary role** — the cook wants "the **main protein at the top**, no matter the cut,"
  then aromatics, then chiles, then liquids. That is an *editorial ordering by role*, which a canonical
  key has no vocabulary for.

These are not tuning gaps; they are the wrong tool. Semantic clustering and role ranking are exactly
what a language model does well and deterministic normalization cannot do at all.

### The load-bearing question: where is an LLM *appropriate*, and where is it forbidden?

The grocery milestone answered this for the shop: **"intelligence at ingest, determinism at merge."**
Grocery consolidation must stay deterministic because a shopping list must be **reproducible and
correct** — a wrong merge is **silent and expensive** (you buy frozen for a fresh dish and find out at
the stove). An LLM nondeterministically re-clustering the shop is unacceptable. That boundary
(§14 / [[grocery-pantry-threshold-design]]) is the one "most likely to erode," and it must hold.

**The Compare matrix is categorically different, and that difference is the whole ADR:**

| | Grocery consolidation | Compare matrix |
|---|---|---|
| Mutates data? | **Yes** (the list) | **No** — pure read over loaded `WorkbenchDetailData` |
| Consequence of error | Silent, expensive (wrong purchase) | **Visible, self-correcting** — the cell shows `chicken breasts` vs `chicken thighs`; the cook understands instantly |
| Determinism required? | **Yes** (same shop, same result) | No — advisory; a good clustering beats a reproducible bad one |
| Right tool | Deterministic key + unit math | **Semantic judgment** |

So an LLM on the Compare matrix **does not violate** determinism-at-merge — *the matrix is not the
merge*. It is the one surface where fuzzy judgment is both needed and low-risk, precisely the
cost-of-error asymmetry [PR #114] was built around. This ADR formalizes that: **an LLM may drive
presentational/advisory alignment; it may never drive the grocery merge or any data write.**

## Decision (proposed)

Add an **LLM-driven aligner** as the **primary** path for the Compare matrix, keeping the deterministic
`comparisonKey` ([PR #114]) as the **fallback**. Structured-output, deterministic-render — the
[[llm-curation-not-synthesis]] posture, same as every other Workbench verb:

- **Input:** each recipe's **raw ingredient lines with stable IDs** — deliberately the *authored*
  `originalText`, **not** the mangled parsed `item`, which sidesteps the parse-garbage problem
  wholesale (the model reads "4 lb / 1.8 kg beef chuck roast" and just labels the row "Beef (chuck)").
  Plus a natural-language **alignment policy** ("group lines that play the same culinary role; order
  rows main-protein-first regardless of cut, then aromatics, then chiles/spices, then liquids…").
- **Output (structured):** ordered rows, each `{ label, role?, assignments: [recipeID → lineID?] }`.
  **Every line is accounted for** — assigned to a row or to an explicit per-column *other* bucket
  (the honest-blank / ambiguity-to-other rule S4 already has). No line silently dropped, none invented.
- **Render:** code builds the existing `IngredientComparison` struct from the structured result; **the
  cells still show each recipe's verbatim authored line** (unchanged from S4). The model decides only
  *which row a line lands on* and *the row's label and order* — it never rewrites ingredient text.

**Policy lives in the prompt, not in code.** "Protein first" is editorial, tunable by editing the
prompt, not a hardcoded category table — and a natural tie-in to ADR-0018 (prompt customization / taste
profile) if we later let the cook phrase their own ordering.

### Guardrails (how it stays trustworthy)

- **Verbatim cells make every wrong merge visible and self-correcting** — the safety net that lets us
  tolerate a fuzzy aligner here but not on the shop.
- **Account-for-every-line** — the aligner must reference real line IDs; anything it can't place goes to
  *other*, never gets fabricated. Grounding honesty per the Workbench synthesis guardrail.
- **Nondeterminism is bounded by caching.** Alignment is **cached per workbench candidate-set**,
  **device-local, not synced** (a presentational artifact, like view state — ADR-0019 D4 passive
  posture). Stable *within* a set; a *different* set earns a fresh clustering; an explicit **refresh**
  affordance recomputes. Acceptable for an advisory view — and the exact property that would be
  unacceptable for grocery, which is why the boundary holds.
- **The matrix always renders something.** Offline / model-unavailable / pre-result → the deterministic
  `comparisonKey` fallback. The LLM improves the view; it is never a hard dependency for showing it.
- **Advisory only — no write, no grocery reach.** The aligner's output never feeds consolidation,
  pantry matching, or any persisted field. It is a per-view derivation.
- **Effort/latency** ([[personal-app-latency-tolerance]], ADR-0017): small N, ~25 lines each — a modest
  structured call, a few seconds on open, then cached. Budget thinking **and** output tokens for the
  structured response ([[reasoning-budget-starves-output]]).

### Why this does NOT need the deferred structured-ingest program

The grocery milestone's deferred "on-device model populates a cached `{base, form, prep}` per line" is a
heavier, persisted, per-ingredient program. This aligner is **lighter and ephemeral**: read the raw
lines, cluster *for this one view*, cache the result. It **does not depend on** structured-ingest and
should not wait for it. If structured-ingest ever ships, the aligner can consume it as a better input —
but the Compare surface earns its fix now, cheaply, on its own.

## Consequences / boundaries

- **Reuse, not rebuild.** The house LLM pattern is `@Dependency(\.modelClient)` → build a `ModelRequest`
  → `try await modelClient.complete` → defensively parse JSON (MenuPrepPlan, MakeAheadPlan,
  MealPlanComplement). No new client infra. Compare is already a pure read producing `IngredientComparison`
  (`WorkbenchCompareCore.swift`); the aligner is a **new async step that yields the same struct** the
  view already renders. Net-new: the aligner core module + parse, the per-set cache, and a
  loading/fallback state in `WorkbenchCompareView`.
- **`comparisonKey` is demoted, not deleted.** [PR #114] keeps earning its keep as the offline fallback
  and a cheap pre-pass. The deterministic slice was the floor; this is the ceiling.
- **Boundary formalized at ADR level.** LLM alignment is *presentational*; grocery consolidation stays
  deterministic. This is the guard rail that keeps the §14 / determinism-at-merge line from eroding as
  "just let the model do it" gets tempting elsewhere.
- **Testability.** The aligner core is unit-tested with a **stubbed `modelClient`** (fixture request →
  fixture JSON → asserted `IngredientComparison`), no network — same as the draft-client tests. The
  render-from-structured step is pure. Lean verification ([[lean-verification-default]]); Jon does the
  device look on the matrix.

## Open questions for the design session

1. **Effort tier** — **DECIDED (Jon, 2026-07-07): medium.** Clustering ~25 lines across a few recipes is
   lighter than draft *synthesis*, so start `medium` (not the draft verb's `high`) and only revisit if
   alignment quality on real recipes proves it needs more head-room.
2. **Where does the ordering policy live** — a fixed house prompt (v1), or cook-tunable via ADR-0018
   taste profile? Recommend fixed house prompt first; expose later only if dogfooding wants it.
3. **Does *Full* (the whole-recipe flip-through) get role-ordering too, or only the Ingredients matrix?**
   Recommend matrix-only for v1 — *Full* is a reading view, not an alignment.
4. **Cache invalidation granularity** — per candidate-**set** hash is clear; do candidate *edits*
   (not add/remove) invalidate, or is it manual **refresh** only? **DECIDED (Jon, 2026-07-07): detect,
   don't auto-recompute.** The cache slot is keyed by recipe-**set identity** (add/remove/reorder), stable
   across text edits; each cached alignment also stores a **content signature** of the ingredient text.
   When the current text no longer matches, the alignment is shown **flagged stale**
   ("Ingredients changed — refresh to update") and the cook re-runs it on demand — never an automatic LLM
   call per edit. Honors the ADR-0019 D4 passive-artifact posture while keeping the surface honest about
   drift (a silently-stale alignment was the failure mode of pure identity-keying). Shipped as the
   device-local disk-cache follow-on (`CompareAlignmentKey` = `identity` + `contentSignature`,
   `CachedCompareAlignment`, `CompareAlignmentCacheStore`).
5. **Failure UX** — when the call errors, do we silently fall back to the deterministic matrix, or show a
   "couldn't smart-align, showing basic view" affordance with retry? Recommend a quiet fallback + an
   unobtrusive refresh, never a blocking error.

## Slice plan (proposed)

- **S1 — deterministic parse/key fixes (no LLM, ships first, independent).** Fix the singularizer so
  `chilies`/`chiles` → one key (`chile`), not `chily`; stop dual-unit / metric-first quantity fragments
  leaking into the item used for keys/labels. Makes the **fallback** stop embarrassing us regardless of
  whether S2/S3 land. Pure `YesChefCore`, unit-tested. *(This is the "cheap parallel PR" already offered.)*
- **S2 — the LLM aligner core.** `WorkbenchCompareAligner` (or fold into `WorkbenchCompareCore`): build
  the structured request from raw lines + policy, call `modelClient.complete`, defensively parse into an
  `IngredientComparison`. Account-for-every-line + *other* bucket enforced. Unit-tested with a stubbed
  client. Deterministic `comparisonKey` remains the fallback the core falls through to.
- **S3 — wire into the view.** `WorkbenchCompareView` gains an async load, the per-set device-local
  cache, loading + fallback states, and a refresh affordance. Device pass on iPad + iPhone.
- **Later (parked)** — cook-tunable ordering policy (ADR-0018), role-ordering for *Full*, consuming
  structured-ingest if it ever ships.

## Related

- **ADR-0019** (Recipe Workbench — S4 Compare is the surface this refines; D4 passive-artifact posture),
  **ADR-0011/0012** (actionable-chat structured-output + tier-aware grounding), **ADR-0017** (LLM effort
  tiers), **ADR-0018** (prompt customization / taste profile — where a cook-tunable policy would live),
  **ADR-0002 / §14** (the sync/determinism boundary this ADR is careful not to cross).
- **[PR #114]** (`docs/efforts/comparison-key-granularity.md`) — the deterministic `comparisonKey`, now
  the fallback.
- Memory: [[llm-curation-not-synthesis]] (structured out, never flatten), [[grocery-pantry-threshold-design]]
  (the determinism-at-merge boundary), [[personal-app-latency-tolerance]] (seconds-on-open is fine),
  [[reasoning-budget-starves-output]] (budget thinking + output for the structured call),
  [[lean-verification-default]].

[PR #114]: https://github.com/jonphillips/yes-chef/pull/114
