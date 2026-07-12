# Effort: Workbench dogfood polish (2026-07-11)

**Type:** App-layer UX polish + two display bugs on the shipped Workbench (ADR-0019). Reuses the existing
Workbench stack (candidates, draft/working recipe, compare). **Not** new schema — the candidate ↔ working
recipe links already exist as soft FKs; these slices *surface* data already in `WorkbenchDetailData`.
**One dispatch, cohesive slices, one PR** (implementer may split S5/S6 as a fast-follow if the image plumbing
grows).
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Ready** (from Jon's 2026-07-11 two-device dogfood).

**Read before starting:** [`recipe-workbench.md`](recipe-workbench.md) (the built effort), ADR-0019 in full,
`WorkbenchViews.swift` + `WorkbenchCore.swift`/`WorkbenchDetailData` (candidate rows already carry
`RecipeDetailData` + `recipeTitleSnapshot`), the draft-verb synthesis path (S2 — the rationale text + the
`Workbench.draftRecipeID` link + `originalSnapshot`), and `RecipeDetailView` (the reader the draft opens in,
and its photo storage via `Recipe.coverPhotoID`). Then `CURRENT_HANDOFF.md` Verification Pattern.

**Build/verify:** `xcodegen generate` if files added; build once `-skipMacroValidation`;
`scripts/check-drift.sh`; **no simulator install** — Jon device-passes on `iPad Pro 13-inch (M5)` (both
orientations) + `iPhone 17 Pro`. Workbench is **iPad-primary**.

---

## S1 — Candidate rows show photo + source (bug-adjacent UX)

Each candidate currently renders title-only. Show the candidate's **recipe photo** (thumbnail) and its
**source** on the row. The data is already loaded — candidate rows carry a full `RecipeDetailData`, so this is
a display change, not a new fetch. Use the thumbnail-only image path (post-ADR-0029-S2 discipline: **no
full-res BLOB** in a list row).

## S2 — Draft rationale references recipes by title + source, not object ID

**Bug.** The synthesized draft's rationale text refers to candidate recipes by a raw object/UUID
(`Related recipe ID: <uuid>`-style leakage — same denormalization gap flagged in the ADR-0019 S3 review
notes). Render candidates in the rationale by their **title + source** using the denormalized
`recipeTitleSnapshot` (and source) the candidate already carries. If the synthesis prompt itself is emitting
the ID, feed the model titles/sources instead of IDs so the generated prose is human-readable at the source.

## S3 — Draft recipe pop-up sheet is scrollable

**Bug.** The draft-recipe preview sheet is **not scrollable**, so its content is cut off at the top and bottom.
Wrap the sheet body in a `ScrollView` (and respect safe-area insets) so the full draft is reachable. Confirm on
both iPad and the compact `iPhone 17 Pro` sheet.

## S4 — Archive-all-candidates affordance

Add an affordance to **archive all candidates** on a workbench at once (a header action). Confirm it routes
through the existing candidate-removal/archival path and respects the soft-FK posture (clears links, doesn't
orphan). Confirm the empty state reads cleanly afterward.

## S5 — Select an image from the candidates for the final (promoted) recipe

When drafting/promoting the working recipe, let the cook **pick a candidate's photo** as the working recipe's
image (rather than only inheriting/setting one manually). Reuse the `Recipe.coverPhotoID` plumbing; the
candidate photos are already loaded. This is the image analogue of the synthesis-is-a-choice principle
(ADR-0019) — the cook chooses which candidate's photo represents the result.

## S6 — Links to the candidate recipes from within the promoted recipe

The promoted/working recipe should carry **links back to its candidate recipes** (tap → open that candidate in
the reader). The `Workbench` ↔ candidate soft FKs already exist; surface them as navigable links on the
promoted recipe. **Sync/lifecycle note:** these are soft references — a deleted candidate must degrade to its
denormalized title snapshot, never a dangling crash (ADR-0019 sync posture). Decide with the reader layout
where the links live (a "drafted from" section on the recipe detail is the natural home).

## Recurring signal (not a slice here — flagged for Jon)

Jon noted twice in this pass that **Workbench and individual-recipe workspaces "secretly overlap"** (editing a
variation; promoting a variation to a standalone recipe). That convergence question is parked in
`docs/open-questions.md` (2026-07-11 section) as a design fork, not built here.
