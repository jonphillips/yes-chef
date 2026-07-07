# Effort: LLM-aligned Compare matrix

**Type:** New AI feature (app + core) + a small deterministic parse fix. Dogfood-driven (Jon,
2026-07-07 — real beef-birria recipes don't align in the S4 matrix).
**Owner:** Codex (implement, per slice) · Claude (architect/review) · Jon (product/review)
**Status:** Scoped 2026-07-07. **Rationale + boundary live in
[ADR-0022](../decisions/ADR-0022-llm-aligned-compare-matrix.md) — read it first.** Not yet dispatched;
milestone-sized, do **not** bundle the slices.

**The one-line why.** The Compare matrix aligns rows on a deterministic canonical key ([PR #114]); real
recipes need *semantic* alignment (chicken breast ≡ thigh, `chile`/`chiles`/`chilies` are one thing,
`morita` ≈ `chipotle`) and *role ordering* ("main protein at top, no matter the cut"). That is
LLM-shaped, and the Compare matrix is the **safe** place for a model: read-only, advisory, and
cost-of-error is cheap and self-correcting (the cells show the difference). Grocery consolidation stays
deterministic — see the boundary in ADR-0022.

**Governing invariants (do not cross — from ADR-0022):**
- **Structured out, verbatim cells.** The model decides *which row a line lands on* + the row's
  label/order; it **never rewrites ingredient text**. Cells stay the authored line. [[llm-curation-not-synthesis]]
- **Account for every line.** Each line → a row or an explicit *other* bucket. Nothing dropped or invented.
- **Advisory only.** The aligner output never feeds grocery/pantry or any persisted field.
- **Always renders.** Deterministic `comparisonKey` is the offline/error fallback; the LLM is never a
  hard dependency for showing the matrix.
- **Cache per candidate-set, device-local, not synced** (presentational artifact; ADR-0019 D4 passive).

**Read before starting:**
- `docs/decisions/ADR-0022-llm-aligned-compare-matrix.md` (rationale, guardrails, open questions).
- `YesChefPackage/Sources/YesChefCore/WorkbenchCompareCore.swift` (the pure read the aligner replaces/feeds;
  produces `IngredientComparison`).
- `YesChefPackage/Sources/YesChefCore/CanonicalIngredient.swift` (`comparisonKey` — the fallback; the
  singularizer to fix in S1).
- The house LLM pattern: `YesChefPackage/Sources/YesChefCore/MenuPrepPlan.swift`
  (`@Dependency(\.modelClient)` → build `ModelRequest` → `modelClient.complete` → defensive JSON parse),
  and the draft-client tests for the **stubbed-client** test shape.
- `YesChefApp/…WorkbenchCompareView` (S3 wiring: async load, cache, loading/fallback states).

---

## S1 — deterministic parse/key fixes (no LLM, ships first, independent)

Makes the fallback stop embarrassing us regardless of whether S2/S3 land. Pure `YesChefCore`, unit-tested.

- **Singularizer:** `chilies`/`chiles` must reduce to **one** key. Today `-ies → y` turns `chilies` into
  `chily`, which then never matches `chile` (from `chiles → chile`). Fix so both spellings converge
  (`chile`). Guard the existing `-ies → y` cases that are correct (`berries → berry`) — this is a
  targeted exception/lookup, not a rewrite of the rule. Apply to `canonicalName` **and** `comparisonKey`.
- **Quantity/unit leak:** dual-unit and metric-first lines ("4 lb / 1.8 kg beef…", "28 to 32 g kosher
  salt…") leak fragments into the parsed `item`, so keys/labels read `/ 1.8 kg beef`, `To 45 g ancho
  chile`, `1¼ ounces ancho chily`. Fix in the ingredient parser so the item is the ingredient noun, not
  the residual quantity. (Scope tightly — this is a known-bad-input fix, not a parser rewrite.)

**Tests:** `chilies`/`chiles`/`chile` collapse to one key; a dual-unit and a metric-first line parse to a
clean item; existing `-ies` plurals and existing parse cases unchanged.

## S2 — the LLM aligner core

`WorkbenchCompareAligner` (or an extension of `WorkbenchCompareCore`): build a structured request from
each recipe's **raw `originalText` lines + stable IDs** and the alignment policy; `modelClient.complete`
at **`medium` effort** (ADR-0022 Q1, decided — clustering, not synthesis); defensively parse into an
`IngredientComparison`. Enforce account-for-every-line + the *other* bucket. Deterministic `comparisonKey`
remains the fallback the core falls through to on parse failure / empty.

**Tests (stubbed `modelClient`, no network):** a fixture set of birria lines → asserted rows (chicken
breast/thigh merge; chile spellings merge; protein row ordered first); a malformed/empty model response
falls back to the deterministic matrix; every input line appears in exactly one row or *other*.

## S3 — wire into the view

`WorkbenchCompareView`: async load of the aligned matrix, per-candidate-set device-local cache,
loading + fallback states, and a **refresh** affordance (recompute on demand; ADR-0022 open-Q4 —
manual refresh, no auto-recompute on candidate edits). Quiet fallback on error, never a blocking alert.
Device pass on iPad (primary) + iPhone.

## Verification

Lean ([[lean-verification-default]]): `swift build` the package for S1/S2 (logic + stubbed client);
S3 builds `YesChef` once per the `CURRENT_HANDOFF.md` Verification Pattern. Jon does the Compare-matrix
UI pass — the alignment quality on real recipes is his call, not CI's.

[PR #114]: https://github.com/jonphillips/yes-chef/pull/114
