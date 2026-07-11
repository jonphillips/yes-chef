# ADR-0029 — Main-thread DB writes and an over-heavy list fetch cause the UI stalls

> **One-line:** The frequently-tapped mutations (archive, restore, delete, switch/rename variation, undo
> adjustment) run the **synchronous** `try database.write { }` **directly on the `@MainActor` model**, so
> the UI freezes for the whole transaction — and worse, that write serializes behind the `SyncEngine` on the
> **shared** `DatabaseWriter`, which is why an archive can stall ~1s. Separately, the recipe-list `@Fetch`
> re-runs on every write and loads **full-resolution image BLOBs** for every photo, then diffs them
> byte-by-byte through an animated whole-library update. Fix: **(S1)** make the quick mutations
> `await database.write` (off-main); **(S2)** stop the list fetch from carrying full-res bytes; **(S3)**
> memoize the per-render variation resolve; **(S4, added after device pass)** decode detail photos off-main,
> downsampled and cached — the real fix for the ~4 s variation switch, which was synchronous full-res image
> decoding on the main thread, not the S3 resolves. **No schema change.**

Status: **Proposed** — 2026-07-11. Low-hanging-fruit performance pass, spotted from a dogfood report
(archive ≈ 1s; variation switching janky). **Amendment 2 (2026-07-11, below): S4 confirmed working on
video, but tap→flip is still 5.6–6.8 s — measured as writer-queue wait, not rendering (Finding 5); S5a–S5c
are the follow-on slices.** Binds **[ADR-0001](ADR-0001-persistence-sqlitedata.md)**
(SQLiteData) and **[ADR-0002](ADR-0002-cloudkit-sync-no-server.md)** (the shared `DatabaseWriter` that the
`SyncEngine` also uses — the contention amplifier). Touches **[ADR-0021](ADR-0021-recipe-variations.md)** /
**[ADR-0023](ADR-0023-recipe-edit-proposals.md)** (the variation resolve in S3). Holds
[[personal-app-latency-tolerance]] (this is *interactive* latency — a tap — not a considered AI action, so
it does **not** get the generous-latency pass).

## Context

Dogfood observation: archiving a recipe on the main list takes ~1s; switching between recipe variations via
the selector menu on the detail screen feels janky. The question was whether we're doing something wrong —
main-thread work that shouldn't be there. We are, in three distinct places. A Time Profiler / hangs trace is
still owed to confirm the ordering empirically, but S1 in particular is safe and correct to ship regardless
of what the trace says.

### Finding 1 — every quick mutation is a synchronous write on the main actor (the primary cause)

The frequently-tapped handlers call the **blocking** form of `database.write` from inside a `@MainActor`
`@Observable` model, so the calling thread — the main thread — blocks until SQLite commits:

- Archive / delete-active: `RecipeLibraryModel.confirmDeleteRecipeButtonTapped`
  ([RecipeModels.swift:212](../../YesChefApp/RecipeModels.swift))
- Restore: `restoreArchivedRecipeButtonTapped` ([RecipeModels.swift:234](../../YesChefApp/RecipeModels.swift))
- Permanent delete: `confirmDeleteArchivedRecipeButtonTapped`
  ([RecipeModels.swift:254](../../YesChefApp/RecipeModels.swift))
- Switch variation: `activeVariationSelectionChanged`
  ([RecipeDetailModel+Adjustment.swift:96](../../YesChefApp/RecipeDetailModel+Adjustment.swift))
- Rename variation: `renameVariation` ([RecipeDetailModel+Adjustment.swift:80](../../YesChefApp/RecipeDetailModel+Adjustment.swift))
- Undo adjustment: `undoLastAdjustmentButtonTapped` ([RecipeDetailModel+Adjustment.swift:114](../../YesChefApp/RecipeDetailModel+Adjustment.swift))

The write blocks the main thread for the SQL **plus** the `fsync` **plus** all the CloudKit trigger
bookkeeping SQLiteData installs (every write appends pending-record-zone rows). The archive SQL itself is
three trivial statements ([RecipeCore.swift:291](../../YesChefPackage/Sources/YesChefCore/RecipeCore.swift)),
so the SQL is not the cost. **The amplifier is contention:** `\.defaultDatabase` is a single serialized
`DatabaseWriter`, and the `SyncEngine` (ADR-0002) uses that same writer on its background queue. When you
tap Archive while the engine is mid-push or draining remote changes, the synchronous main-thread `.write`
**blocks behind the engine's transaction** — the variable ~1s stall. This is the bug.

Note the heavier operations already do it right — `try await database.write` at
[RecipeModels.swift:174](../../YesChefApp/RecipeModels.swift), `:332`, `:354`, `:551`. It is the fast,
frequent taps that were left synchronous. That is backwards.

### Finding 2 — the list fetch re-runs on every write and carries full-res image BLOBs (why *archive* is heavy)

`@Fetch(RecipeListRequest(), animation: .default)`
([RecipeModels.swift:36](../../YesChefApp/RecipeModels.swift)) re-runs after any write to
`recipes` / `menuItems` / `mealPlanItems`. Its request
([RecipeListRequest.swift:72](../../YesChefPackage/Sources/YesChefCore/RecipeListRequest.swift)) selects
`displayData` — **full-resolution image bytes** — for every photo of every recipe, and each
`RecipeListRowData` carries a `Data?` thumbnail that **falls back to full-res** when no downscaled thumbnail
exists ([:125](../../YesChefPackage/Sources/YesChefCore/RecipeListRequest.swift)). `RecipeListRowData` is
`Equatable`, so SwiftUI's `animation: .default` diff compares those `Data` blobs byte-by-byte across the whole
library on the main thread, then animates. The fetch runs off-main, but the diff + animation + body re-eval
do not — on a real library that is the visible cost of an archive.

### Finding 3 — the variation resolve is recomputed many times per render (why *variation switching* is janky)

Beyond the sync write in Finding 1, the detail view recomputes `resolved(applying:)` — which JSON-decodes the
variation deltas and re-derives the entire recipe
([RecipeAdjustment.swift:670](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift)) — repeatedly
per body pass. `displayDetail` resolves once
([RecipeVariationDisplayModel.swift:26](../../YesChefApp/RecipeVariationDisplayModel.swift)); then
`ingredientLines`, `ingredientGroups`, `instructionSteps`, `visibleNotes` each call `displayDetail` again
(re-resolving), and `displayIngredientLines` calls `variationIngredientHighlights`, which resolves *again*
([:688](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift)). One body pass can resolve the
recipe a dozen times, all on the main thread during the render that follows the switch.

### Finding 4 — the *real* variation-switch cost: full-res image decode on the main thread (amendment, 2026-07-11)

Added after the device pass: a variation switch measured at **~4 seconds**, far past anything the Finding-3
resolves could explain (a resolve is sub-millisecond even a dozen times over). The dominant cost is a
Finding-2-class problem the original ADR only diagnosed for the *list*, now found on the *detail* screen:

- `setActiveVariation` writes `recipeActiveVariations`
  ([RecipeAdjustment.swift:513](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift)), a table
  read by `RecipeDetailRequest`, so the `@Fetch var detail`
  ([RecipeModels.swift:817](../../YesChefApp/RecipeModels.swift)) re-runs and reloads **every photo's full-res
  `displayData`** into a multi-MB `Equatable RecipeDetailData`, published through `animation: .default`.
- The animated re-publish re-evaluates the detail body, and `RecipePhotoImage` called `UIImage(data:)`
  **synchronously in `body`**, uncached and without downsampling
  ([RecipePhotoViews.swift:315, pre-fix](../../YesChefApp/RecipePhotoViews.swift)) — re-decoding full-res
  JPEGs to bitmaps on the main thread, potentially across several animation frames. That is the ~4 s hang.

**Consequence for S3:** the per-render resolves (Finding 3) are real but the *smallest* of these costs;
memoizing them alone would not have moved the 4 s. S3 is therefore deprioritized behind **S4** below.

## Decision

Three slices, in this order. **S1 and S2 are the low-hanging fruit — do them first.** S3 is smaller-impact
render polish; do it in the same dispatch if cheap, or gate it on the Time Profiler trace if it complicates.
No schema change in any slice.

### S1 — Move the quick mutations off the main thread (highest leverage, lowest risk)

Convert the six synchronous `try database.write { }` handlers listed in Finding 1 to the async form. The
handlers are all invoked from SwiftUI button actions / confirmation-dialog buttons / a `Binding` setter
(none from an async context), so **keep each method signature synchronous and wrap the write in a `Task`** —
the model is `@MainActor`, so the `Task` inherits the main actor, `await database.write` hops the write to
the writer's queue off-main, and the `errorMessage` / `isShowingError` assignments stay on main. Minimal
call-site churn (no call sites change). Pattern:

```swift
func activeVariationSelectionChanged(_ variationID: RecipeVariation.ID?) {
  Task {
    do {
      try await database.write { db in
        try RecipeRepository.setActiveVariation(
          variationID, recipeID: recipeID, in: db, now: now, uuid: { uuid() }
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }
}
```

- Keep the pre-write UI state changes (`destination = nil`, `selectedRecipeID = nil`) **synchronous, before
  the `Task`** — they must feel instant and must not wait on the commit.
- Cautions for the implementer: (a) rapid taps (fast variation switching) submit multiple Tasks; the writer
  serializes them in submission order and the `@Fetch` reflects the last commit — acceptable, do not add
  debouncing in this slice. (b) Do **not** convert the `await database.write` sites that already exist, and do
  not touch `workbenchTheseButtonTapped` ([RecipeModels.swift:89](../../YesChefApp/RecipeModels.swift)) or
  other writes that return a value the caller uses synchronously unless the conversion is trivially safe —
  scope this slice to the six enumerated tap handlers.

### S2 — Stop the list fetch from carrying full-resolution image bytes

In `RecipeListRequest` ([RecipeListRequest.swift](../../YesChefPackage/Sources/YesChefCore/RecipeListRequest.swift)):

- **Do not select `displayData`** in the photo query (lines ~72–84). Select only `thumbnailData` (plus the
  dimension/kind/sort columns already used for `listSortKey`). The list must never hold full-res bytes.
- Remove the full-res fallback for the list image: `listImageData` (line ~125) must resolve to a **downscaled
  thumbnail only**. If a photo has no `thumbnailData`, the list row shows the placeholder rather than pulling
  full-res — a recipe missing a generated thumbnail is a data-quality issue to fix at import/capture, not a
  reason to load megabytes into the list.
- Re-evaluate `animation: .default` on the whole-library `@Fetch`
  ([RecipeModels.swift:36](../../YesChefApp/RecipeModels.swift)). Shrinking the payload (above) removes most
  of the diff cost; if the Time Profiler still shows the animated whole-library diff as a hotspot after S2,
  consider dropping the fetch-level animation (animate the specific row removal at the view instead). Leave
  this as a measured follow-up, not a blind change.
- If comparing even thumbnail `Data` in `RecipeListRowData: Equatable` shows up as a cost, prefer keying row
  identity/equality on a cheap thumbnail token (photo ID + a stored hash/size) rather than the bytes — but
  only if measured; do not over-engineer in this slice.

### S3 — Memoize the per-render variation resolve

Cache a single resolved `RecipeDetailData` on the `@MainActor` `RecipeDetailModel`, keyed on the current
`detail` identity + `activeVariationID`, so one render resolves once instead of a dozen times. Invalidate when
`detail` or the active variation changes. The computed properties in
[RecipeVariationDisplayModel.swift](../../YesChefApp/RecipeVariationDisplayModel.swift) read the cache instead
of each calling `resolved(applying:)` / `variationIngredientHighlights` afresh. Keep the resolve logic in
`YesChefCore` unchanged — this is a memoization layer in the app model only.

### S4 — Decode recipe photos off the main thread, downsampled and cached (the variation-switch fix) — **DONE 2026-07-11**

The measured fix for Finding 4. New [RecipeImageLoader.swift](../../YesChefApp/RecipeImageLoader.swift):

- `RecipePhotoImage` no longer calls `UIImage(data:)` in `body`. It decodes **off the main thread** via
  ImageIO `CGImageSourceCreateThumbnailAtIndex`, **downsampled** to a per-variant pixel budget
  (thumbnail/hero/full-screen), and serves results from a `@MainActor` `NSCache` keyed on
  `photoID | checksum | variant`. A cache hit renders synchronously (no placeholder flash); a re-render never
  re-decodes; an edited photo (new checksum) invalidates cleanly. All four call sites in
  [RecipePhotoViews.swift](../../YesChefApp/RecipePhotoViews.swift) thread the photo identity + variant through.
- Scoped to the detail photo path (the reported 4 s). The list/meal-calendar rows and the editor/capture
  previews still decode inline, but after **S2** they carry only small thumbnails, so they are not the hang;
  routing them through the same cache is an optional follow-up, not this fix.
- No core/schema/sync change — app view layer only. Leaves the S2 "cheap `Equatable` token instead of bytes"
  idea and S3's resolve memoization as measured follow-ups; neither is needed to clear the 4 s.

## Consequences

- **Interactive taps stop blocking the main thread** (S1) and the list stops shuttling full-res images
  through an animated diff on every write (S2) — together these are the archive-lag fix. S3 removes the
  redundant resolve work behind variation switching.
- **No schema change, no sync change** — S1 only changes *where* the same writes run; S2/S3 are read/render
  shaping. Nothing at device or sync risk.
- **Behavioral nuance from S1:** errors surface one runloop later (after the async commit) instead of
  synchronously. The confirmation dialog already dismisses before the write, so the human sees an instant
  dismiss and, only on the rare failure, a subsequent error alert — acceptable and arguably better.
- **S2 hard edge:** recipes whose photos never got a downscaled thumbnail will show the placeholder in the
  list instead of a (previously full-res) image. Confirm in Jon's device pass whether the existing library
  has thumbnail-less photos; if common, a one-time thumbnail backfill is a *separate* follow-up, not this ADR.

## Open questions

- **OQ1 — trace before/after.** Time Profiler + SwiftUI hangs instrument on a real archive tap and a
  variation switch, before and after S1+S2, to confirm the ordering and quantify the win. Owed to Jon's
  device pass; S1 ships regardless. *→ Sharpened by Amendment 2 into S5a: the one question the trace must
  answer is how the tap→publish time splits into writer-wait vs. everything else.*
- **OQ2 — thumbnail coverage.** Does the real library have photos with no `thumbnailData` (which S2 would now
  render as placeholders)? If yes, scope a thumbnail backfill separately.
- **OQ3 — writer contention, upstream.** If S1 helps but the writer is still a bottleneck under active sync,
  the deeper lever is whether SQLiteData can give reads/writes more concurrency against the sync engine's use
  of the shared writer — a possible upstream ask, parked until measured. *→ Amendment 2 found the concrete
  mechanism (Finding 5) and it is worse than "the engine holds the writer": our own observations amplify the
  occupancy. See S5c.*

---

# Amendment 2 — The ~6 s variation switch is writer-queue wait, not rendering (measured; S5)

> **One-line:** A 120 fps screen recording of two variation switches, measured with per-pane change
> detection, shows **tap → visible flip = 6.8 s and 5.6 s** while **S4 works exactly as designed** (the flip
> itself is a smooth ~0.5 s crossfade, no placeholder flash) and **the list pane and AI pane never repaint a
> single pixel**. The wait is upstream of all rendering. Mechanism (Finding 5): every SQLiteData `@Fetch` is
> a **non-constant-region** `ValueObservation`, and GRDB runs those observations' re-fetches **synchronously
> on the writer connection inside `databaseDidCommit`** — so every sync-engine commit that touches an
> observed region re-runs our heavy fetches *on the writer queue*, and the tap's two-statement write queues
> behind the convoy. Fix: **(S5a)** signpost the tap→publish pipeline to split the wait empirically;
> **(S5b)** drop full-res `displayData` from the detail fetch (S2's treatment, applied to the detail);
> **(S5c, gated on S5a)** get the heavy observations off the writer. **No schema change.**

Status: **Proposed** — 2026-07-11, same day as the base ADR and the Finding-4/S4 amendment. Nothing here
invalidates S1–S4: S1 correctly turned a main-thread freeze into a delayed update, and S4 genuinely fixed
the decode hang — this amendment explains why the *latency* survived both. Deepens **OQ3** (mechanism found)
and sharpens **OQ1** (into S5a). Binds [ADR-0002](ADR-0002-cloudkit-sync-no-server.md) harder than the base
ADR did: the `SyncEngine`'s use of the shared writer is not just an amplifier of our writes — it is the
queue our *reads* run on too.

## Context — the screen recording, measured

Jon recorded two variation switches on the iPad (base → "Trying to reduce spiciness" → base) with the
library list and the AI chat pane visible alongside the detail. Method: extract per-pane crops (list /
detail / AI / selector-menu region) and run ffmpeg scene-score change detection at 30 fps over all 972
frames — timestamps below are pixel-change events, not eyeballed frames.

| Event | Switch 1 | Switch 2 |
|---|---|---|
| Variation menu opens | ~2.0 s | ~12.5 s |
| Menu item tapped (menu dismisses) | ~3.1 s | ~13.4 s |
| Detail content flips (~0.5 s crossfade) | 9.9–10.5 s | 19.0–19.5 s |
| **Tap → visible result** | **~6.8 s** | **~5.6 s** |

Three facts this settles:

1. **S4 works.** The flip, when it finally comes, is a smooth crossfade with no placeholder flash and the
   hero photo stable throughout. Rendering and decoding are no longer the problem.
2. **The other panes are innocent.** The list pane and AI pane show *zero* change events between 1 s and
   22 s (the only events at the edges are Control Center opening/closing). The suspected multi-pane
   re-render fan-out does not exist visually.
3. **The wait is dead air.** Between tap and flip the detail shows the *old* content unchanged — no partial
   update, no spinner, nothing. Whatever consumes the ~6 s finishes before any UI effect begins.

## Finding 5 — non-constant-region observation fetches run on the writer connection (the convoy)

The tap handler is minimal post-S1 — `Task { await database.write }` around two trivial statements
([RecipeDetailModel+Adjustment.swift:96](../../YesChefApp/RecipeDetailModel+Adjustment.swift)) against a
`DatabasePool`. So where do ~6 seconds go? In GRDB's observation machinery:

- SQLiteData's `@Fetch` builds its observation with plain `ValueObservation.tracking { }`
  (`sqlite-data/Sources/SQLiteData/Internal/FetchKey.swift`), which GRDB classifies as
  `.nonConstantRegionRecordedFromSelection`.
- For that tracking mode, `ValueConcurrentObserver.databaseDidCommit` **cannot use a concurrent reader** (a
  region change could slip past snapshot isolation), so it re-runs the observation's *entire fetch
  synchronously on the writer connection, on the writer queue, inside the commit hook*
  (`GRDB/ValueObservation/Observers/ValueConcurrentObserver.swift`, the
  `.nonConstantRegionRecordedFromSelection` branch of `databaseDidCommit`).

Two consequences, one per direction:

- **Our commit → publish is fast.** The moment the variation write commits, the detail re-fetch happens
  inline right there, then notifies main. So the measured 6 s is, to first order, **time spent waiting for
  the writer queue** before our two-statement write even runs.
- **Why the writer is busy: our own observations occupy it.** Every `SyncEngine` commit that touches an
  observed region triggers those inline writer-connection fetches — for *every live* `@Fetch`. That is:
  the whole-library `RecipeListRequest` (2,159 recipes), held **concurrently by up to four models**
  ([RecipeModels.swift:36](../../YesChefApp/RecipeModels.swift),
  [MenuModels.swift:33](../../YesChefApp/MenuModels.swift),
  [MealCalendarModels.swift:27](../../YesChefApp/MealCalendarModels.swift),
  [WorkbenchModels.swift:115](../../YesChefApp/WorkbenchModels.swift)), plus `RecipeDetailRequest`, which
  still hauls **every photo's full-res `displayData`** ([RecipeCore.swift](../../YesChefPackage/Sources/YesChefCore/RecipeCore.swift)).
  Under active sync the writer becomes a convoy — sync batch commit → inline heavy fetches ×N on the writer
  → next batch → … — and an interactive tap's write waits at the back. The equal-value re-fetches produce no
  visible repaint (SwiftUI diffs them away), which is exactly why the list looked frozen-but-fine in the
  recording while all this churned.
- The [ADR-0028 context](ADR-0028-multi-foreign-key-sync-loss.md) makes engine churn at recording time
  plausible: the ~44k-row library was still being throttled through CloudKit (429s) as of 2026-07-10.

**Honest caveat:** the video cannot fully exclude a clogged main actor (nothing in-app animates during the
dead air to prove responsiveness). S5a's first signpost settles that conclusively; the analysis above is the
strongly favored reading, not yet a measurement.

## Decision — S5, three slices

### S5a — Signpost the tap→publish pipeline (measure before structural work)

Instrument `activeVariationSelectionChanged` with `os_signpost` intervals (plus mirrored `Logger` lines so a
plain console capture suffices — no Instruments run required for the first pass):

1. **writer-wait** — handler entry → write-closure entry (this is the convoy, if the theory holds);
2. **write-txn** — write-closure entry → exit;
3. **publish-gap** — write-closure exit → the `@Fetch` delivering the new `activeVariationID` (observe in
   the model, e.g. where `detail` updates).

Cheap enough to leave in permanently; no DEBUG gating. Acceptance: one on-device repro of a variation switch
yields the three durations unambiguously. Also note whether sync was active during the repro (OQ-A2-1).

### S5b — Drop full-res bytes from the detail fetch (S2's treatment, applied to the detail)

Worth doing regardless of S5a's numbers — it shrinks the fetch that Finding 5 runs inline on the writer, the
multi-MB `Equatable` payload, and resident memory:

- `RecipeDetailData.photos` stops carrying `displayData`. Use a **distinct slim projection type** (metadata
  + `thumbnailData` + a `hasDisplayData` flag — mirroring S2's `RecipeListPhotoRow`), *not* a `RecipePhoto`
  with nulled bytes: the compiler must force the call-site audit, and a slim row must never be writable back
  (data-loss trap).
- **On-demand byte load:** photoID → `displayData` via `database.read` (pool readers are concurrent — this
  never touches the writer), feeding the existing `RecipeImageLoader` cache on a miss. Hero and full-screen
  variants load on demand; the thumbnail variant uses the carried `thumbnailData`.
- Call-site audit (complete as of this writing): `displayablePhotos`
  ([RecipeModels.swift:828](../../YesChefApp/RecipeModels.swift)) needs only the presence flag; the four
  `RecipePhotoViews` sites already thread photo identity + variant through (S4); the editor sites
  ([RecipeEditorModels.swift:61,66,75](../../YesChefApp/RecipeEditorModels.swift)) prefer thumbnails and
  need flag/thumbnail only — audit whether any editor *commit* path needs bytes (OQ-A2-2);
  [RecipeCaptureView.swift:356](../../YesChefApp/RecipeCaptureView.swift) uses an in-memory pending photo,
  unaffected.
- Behavior nuance: the first display of a hero after a cold launch shows the placeholder for one decode beat
  (bytes were previously in hand from the fetch). S4's cache makes that once per photo per launch —
  acceptable; do not pre-warm speculatively in this slice.

### S5c — Get the heavy observations off the writer (structural; gated on S5a's numbers)

Options, deliberately not chosen yet — pick after S5a says how the time splits:

- **Upstream ask:** SQLiteData exposing constant-region tracking (GRDB's `trackingConstantRegion` /
  `ValueObservationTrackingMode.constantRegion`), which moves post-commit fetches to concurrent readers.
  Our requests *are* effectively constant-region per key. This is the durable fix for Finding 5's mechanism.
- **Fewer/lighter observers:** one shared `RecipeListRequest` observation instead of four parallel copies;
  the models subscribe to a shared store.
- **Sync-aware coalescing:** debounce/pause list-scale observation delivery during bulk-sync bursts.

Do not build any of these speculatively; if S5a shows writer-wait is *not* the dominant term, return here
with the new evidence instead.

## Consequences

- **The perceived fix depends on where the time actually is** — S5a is cheap insurance against building S5c
  on a wrong theory. If writer-wait dominates and sync churn is transient (post-bulk-sync), day-to-day
  latency improves on its own; S5c is what makes it *stay* fixed under future sync bursts.
- **S5b is a win on every branch:** less writer occupancy per Finding-5 fetch, smaller diffs, less memory,
  and it completes the "no surface carries full-res bytes in a fetch" invariant that S2 started.
- **No schema change, no sync change** in any S5 slice.

## Open questions

- **OQ-A2-1 — was sync draining during the repro?** Check the sync status around the recording (11:23 AM,
  2026-07-11) and rerun the S5a repro once with sync verifiably idle to bound the engine's contribution.
- **OQ-A2-2 — does any editor commit path need fetched full-res bytes?** Audit during S5b; if yes, the
  editor does its own on-demand read at commit time — the fetch still never carries bytes.
