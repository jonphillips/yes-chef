# Next Up — Drop raw import HTML and dead photo rows; re-upload and re-link

**Slices:** effort `raw-import-html-drop`, S1–S3 (one PR, branch `effort/raw-import-html-drop`)
**Briefs:** docs/efforts/raw-import-html-drop.md
**Done when:** per the brief's "Done when"; verification per `docs/verification.md` (check-drift, the elevated generic
iOS build, and `YesChefTests`, because `Recipe`'s shape changes).
**Owed:** Jon's iPad + iPhone device pass in `docs/device-passes.md`, with a backup exported from each device first
(not executor work).
**Notes:** Schema change and two data deletes on synced tables, both approved by Jon on 2026-10-13. The architect
escalates the PR to Jon. Read the standing guards "No raw page in the store" and "A `RecipePhoto` row exists only with
image bytes" first. Within the post-engine pass the order matters: delete byte-less photos, then re-queue recipes
not on the server, then children only of recipes already on the server, then re-link. Never touch a child or link
to a recipe that isn't on the server yet. The migration is append-only; `declaredSchemaVersion` becomes 52. This
must land before `PROD-CUTOVER.md` Phase 3. The completing PR advances this ticket to
`efforts/sync-failure-surfacing.md` (jon-platform#70 must be merged first). Start from a fresh `main`.
