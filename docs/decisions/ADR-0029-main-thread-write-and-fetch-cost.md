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
are the follow-on slices. Amendment 3's later S5a measurement retired that convoy theory, and
**Amendment 4 corrects its replacement theory: the measured “COMMIT” interval still includes synchronous
observation work, so S6b attributes that envelope before any image-storage change. Amendment 5 records
the result — SQLite and the fetch are fast — and scopes S6c at the main-actor delivery/render boundary.** Binds
**[ADR-0001](ADR-0001-persistence-sqlitedata.md)**
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

---

# Amendment 3 — S5a measured: the cost is the COMMIT, not the convoy (Finding 5 disproven)

> **One-line:** The S5a signposts landed on a real device switch and read **writer-wait = 20 ms,
> write-txn = 5096 ms, publish-gap = 0 ms**. This **overturns Finding 5**: the writer was free when the
> tap landed (20 ms to enter it — no convoy), and post-commit delivery is instant (0 ms — S5b made the
> re-fetch cheap). **All ~5.1 s is inside `database.write` itself** — a DELETE + INSERT of one tiny
> `recipeActiveVariations` row plus SQLite's COMMIT. Trivial SQL taking 5 s ⇒ the cost is the **commit**
> (fsync / WAL checkpoint) and/or the **per-write CloudKit sync-trigger bookkeeping**, amplified by a
> 44k-row DB with full-resolution image BLOBs stored inline. **Kill S5c** (observations-off-writer moves
> nothing). New direction: split and attack the commit cost. **No schema change yet.**

Status: **Measured** — 2026-07-11, S5a instrument (built with S5b). S5a did exactly its job: it was cheap
insurance against building S5c on a wrong theory, and it caught the wrong theory. Nothing here invalidates
S1/S2/S4/S5b — S5b in particular is *confirmed* by publish-gap = 0. It retires the Finding-5/S5c hypothesis
and redirects at [ADR-0002](ADR-0002-cloudkit-sync-no-server.md)'s shared writer from a different angle: not
*contention* on the writer, but the *per-commit I/O* the writer pays.

## Finding 6 — a two-statement write commits in ~5 s because the commit itself is expensive

The three phases, measured:

| Phase | Definition | Measured |
|---|---|---|
| writer-wait | handler entry → write-closure entry | **20 ms** |
| write-txn | write-closure entry → `database.write` returns (SQL + COMMIT) | **5096 ms** |
| publish-gap | commit → `@Fetch` delivers new `activeVariationID` | **0 ms** |

- **writer-wait 20 ms disproves the convoy.** If sync-engine observation re-fetches were occupying the
  writer (Finding 5), our write would have waited behind them. It didn't. The writer was free.
- **publish-gap 0 ms confirms S5b and clears the render/observation path.** The post-commit re-fetch and
  publish happen within the 5 ms poll resolution. Whatever ate the seconds finished at COMMIT.
- **write-txn 5096 ms is the whole hang, and the SQL is trivial** (`setActiveVariation`:
  [RecipeAdjustment.swift:498](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift) — one
  SELECT guard, one DELETE, one INSERT on a tiny table). So the seconds are in **COMMIT**, not the
  statements. The leading mechanisms, in order of suspicion:
  1. **WAL checkpoint fsync of a huge main DB.** Full-res image `displayData` is stored inline in the main
     SQLite file, so the DB is multi-GB. In WAL mode a normal commit fsyncs only the WAL (fast), but when a
     commit trips the auto-checkpoint threshold it copies WAL pages into — and fsyncs — the multi-GB main
     file. Under active sync the engine writes fast, the WAL grows fast, and *whichever* commit trips the
     checkpoint eats it. This also explains the base ADR's **variability** (archive ≈ 1 s vs switch ≈ 5–6 s):
     it depends on whether your write is the one that checkpoints.
  2. **Per-write sync-trigger bookkeeping** SQLiteData installs (pending-record-zone rows on every synced
     write) doing more work than expected on a 44k-row library.

## Decision — retire S5c, add S6 (measure the commit, then move BLOBs out of the hot file)

- **S5c is dropped.** S5a's numbers say the writer is not contended; moving observations off it is dead
  weight. (Constant-region tracking may still be a *nice* upstream ask, but it is no longer *this* bug's fix.)
- **S6a — split the commit.** Add one more signpost inside `setActiveVariation`: closure-entry → last-
  statement-done (the SQL) vs last-statement-done → `database.write` returns (the COMMIT). Also log
  `PRAGMA wal_checkpoint` / WAL page count around the write, and rerun once with **sync verifiably idle**
  (settles OQ-A2-1). Acceptance: one repro that says "SQL = X ms, COMMIT = Y ms, WAL = Z pages, sync
  idle/active." Expect X ≈ 0, Y ≈ 5000.
- **S6b (gated on S6a; superseded by Amendment 4) — get full-res image bytes out of the commit's fsync
  path.** If S6a confirms the
  checkpoint/fsync-of-a-huge-file hypothesis, the durable fix is that `displayData` should not live inline
  in the main synced SQLite file: move image blobs to on-disk files (or a separate, un-checkpointed store)
  so a metadata commit never fsyncs gigabytes. This **touches sync** (the one-way gate — see
  [[post-browser-sync-vs-features-tension]]) and [[sqlitedata-blob-cloudkit-asset]], so it is a real
  architectural decision, not a quick slice — spec it separately, do not build it speculatively.

## Consequences

- **The interactive-latency bug is an I/O-per-commit problem, not a concurrency-on-the-writer problem.**
  Every mutation — archive, switch, rename, undo — pays it; S1's off-main hop stopped it freezing the UI
  thread but the *latency* is the commit, and only S6 addresses that.
- **S5b stands and helped** (publish-gap = 0). S1/S2/S4 stand. Only S5c is retired.
- **S6b, if pursued, is the first S-slice that changes where image bytes live** — hold it to the sync gate's
  bar, with a device round-trip, not a dogfood slice.

---

# Amendment 4 — the S6a “COMMIT” bucket still includes observation work; keep SQLiteData assets (S6b)

> **One-line:** S6a split repository SQL from the interval after the write closure returns, but that second
> interval is **not pure SQLite COMMIT time**: GRDB runs SQLiteData's non-constant `@Fetch` re-fetches
> synchronously from `databaseDidCommit` before `database.write` returns. Therefore the 5.1 s result does
> not yet prove checkpoint/fsync cost, and the 0 ms publish gap does not prove the re-fetch was cheap — it
> is also what we expect when the re-fetch completed inside the measured “COMMIT” bucket. Keep recipe image
> BLOBs on SQLiteData's supported BLOB→`CKAsset` path. Replace the old image-externalization S6b with a
> narrow attribution slice that measures SQLite's actual `COMMIT` statement separately from the detail
> observation it triggers. **No schema change, no sync change, no image-storage change.**

Status: **Measured** — 2026-07-11. Supersedes Amendment 3's S6b and narrows Finding 6 from a conclusion
(“the commit itself is expensive”) to a candidate mechanism. S1/S2/S4/S5b remain valid. **Amendment 5
records the result: SQLite COMMIT and the detail request are both fast; the five seconds remain between
off-main completion and resumption of the `@MainActor` task.**

## Correction to Finding 6 — the timing boundary was named too strongly

The S6a instrumentation records:

1. `writer-wait`: handler entry → entry into the `database.write` closure;
2. `sql`: closure entry → `setActiveVariation` returns;
3. `commit`: closure return → `database.write` returns;
4. `publish-gap`: `database.write` return → observed active variation matches the target.

The first two names are accurate. The third is an **envelope**, not a pure SQLite phase. GRDB invokes
transaction observers from `databaseDidCommit` before the write API returns. SQLiteData constructs every
`@Fetch` with non-constant-region `ValueObservation.tracking`; for that tracking mode GRDB re-runs an
affected request synchronously on the writer connection from the commit callback. That work therefore
lands after our `sqlDone` timestamp but before `writeExit` — inside the interval S6a labels `commit`.

This changes what the existing measurements establish:

- **20 ms writer-wait** rules out a pre-existing convoy ahead of this tap. It does not rule out work that
  this tap's own commit triggers.
- **0 ms publish-gap** proves only that the new value was ready when `database.write` returned. It is
  consistent with either a cheap re-fetch or a multi-second re-fetch performed synchronously inside the
  return envelope.
- **≈0 ms repository SQL** clears `setActiveVariation` and SQLiteData's row triggers, because those triggers
  execute with the DELETE/INSERT before the closure returns.
- **≈5.1 s closure-return envelope** currently combines SQLite's `COMMIT TRANSACTION`, GRDB commit-callback
  work, affected observation re-fetches, and small wrapper overhead. It cannot choose among them.

The four whole-library `RecipeListRequest` observations are not the favored explanation for a variation
switch: that request does not read `recipeActiveVariations`, so the event should not intersect its observed
region. `RecipeDetailRequest` does read that table and is affected. S5b removed `displayData` from its photo
projection, but the request still performs many sequential queries and reads all `Tag`, `Category`, and
`Equipment` rows before filtering in Swift. That may be cheap; S6b measures it rather than assuming either
way.

### WAL nuance

The S6a `PRAGMA wal_checkpoint(NOOP)` probe is valid on the iOS 27 SQLite runtime: it reports WAL/log and
checkpointed-page counts without performing a checkpoint. Keep it.

However, “the database is multi-GB, therefore a small metadata commit fsyncs gigabytes” is too strong.
A checkpoint copies applicable WAL frames back to their database pages; it does not rewrite every page in
the main file merely because the file is large. Images can still be an indirect amplifier when recent image
writes created a large checkpoint backlog — especially if readers prevented earlier checkpoints from
finishing — but the main-file byte count alone does not establish that mechanism.

## Image/iCloud decision — keep the current SQLiteData asset architecture

SQLiteData 1.6.6 explicitly supports images as SQLite BLOBs: it turns every BLOB field into a `CKAsset` when
materializing a CloudKit record and decodes a received asset back into the table. Its guidance is to place
large BLOBs in a separate related table so ordinary queries do not load them. Yes Chef already has that
shape: `RecipePhoto` owns the bytes separately from `Recipe`, and S2/S5b now select slim projections while
the hero/full-screen path reads `displayData` on demand.

The CloudKit bookkeeping installed on an unrelated metadata write enqueues record identities; it does not
hash, copy, or upload every existing photo. BLOB hashing and temporary `CKAsset` file creation happen when
the sync engine materializes the photo's CloudKit record.

Do **not** move canonical image bytes to ordinary files or a second store in this effort:

- an app-group file path is device-local and will not round-trip through SQLiteData/CloudKit;
- iCloud Drive would introduce a second independent sync/conflict system with no atomic relationship to
  the recipe rows;
- a second SQLite database/`SyncEngine` would lose the real FK/share-tree relationship and cross-store
  transactionality, and two engines targeting the same zone are not an established SQLiteData pattern;
- custom CloudKit asset upload/download would violate ADR-0002's no-hand-rolled-sync decision.

Splitting photo metadata and photo BLOBs into two tables **inside the same SQLite file** remains a possible
query-shaping cleanup, but S2/S5b already avoid selecting the bytes and such a split would not remove image
pages from the file or its WAL. It is not a fix for the mechanism currently under investigation.

## Decision — S6b: attribute the closure-return envelope — **DONE 2026-07-11**

### Goal

Produce one device log in which the existing closure-return envelope reconciles into:

1. SQLite's actual `COMMIT TRANSACTION` statement duration;
2. the affected `RecipeDetailRequest.fetch` duration;
3. any residual GRDB/observation/write-return overhead.

This is the last diagnostic slice before choosing a structural fix. It makes no user-visible behavior,
schema, migration, image-storage, or sync change.

### Implementation scope

1. **Profile the real SQLite COMMIT.** In the existing database `Configuration.prepareDatabase`, install a
   DEBUG-only GRDB `.profile` trace. Inspect the unexpanded statement SQL and log only
   `COMMIT TRANSACTION` events to `AppLog.performance`, including the profile duration and whether
   `SyncEngine.isSynchronizing` is true. Do not log expanded SQL or bound values. The SQLite profile event
   occurs for the statement itself; GRDB's `databaseDidCommit` observation callbacks run afterward.

2. **Time the detail observation request.** Wrap `RecipeDetailRequest.fetch` with a `ContinuousClock`
   interval and emit its total duration to `AppLog.performance`. Keep the repository queries and returned
   value unchanged. This intentionally measures the entire composite request, not each SELECT — per-query
   profiling would add noise and risks logging recipe content.

3. **Retain the S6a envelope.** Keep writer-wait, repository-SQL, closure-return envelope, publish-gap,
   WAL `NOOP`, and sync-state logging. Rename the logged `commit=` field to `write-return-envelope=` (and
   the signpost event accordingly) so future captures cannot repeat Finding 6's category error. Historical
   console captures remain interpretable through this amendment.

4. **Make one correlation line.** After `database.write` returns, emit a single summary containing a
   per-switch correlation token plus writer-wait, SQL, write-return envelope, WAL before/after, and sync
   state. Give the SQLite-COMMIT and detail-fetch profile lines the same token only if it can be threaded
   without global mutable state; otherwise their logger timestamps must make the association unambiguous.
   Do not introduce a singleton or broad tracing service solely for correlation.

5. **No optimization in this slice.** Do not rewrite `RecipeDetailRequest`, enable constant-region
   observation, change checkpoint settings, null/copy image BLOBs, add a second store, or alter the
   `SyncEngine` table list. S6b is evidence only.

### Device pass

Jon performs the real-device pass after the executor's build is green:

1. switch base → variation → base once while sync reports idle;
2. if sync can be observed actively fetching/sending without manufacturing data churn, repeat once active;
3. capture the `performance` category lines from handler entry through publish.

Do not force a checkpoint, disable sync, rewrite the live library, or create artificial CloudKit churn for
this pass.

### Acceptance

The capture must unambiguously report, for at least the idle pair of switches:

- writer-wait;
- repository SQL;
- write-return envelope;
- SQLite `COMMIT TRANSACTION` profile duration;
- `RecipeDetailRequest.fetch` duration;
- publish-gap;
- WAL log/checkpointed pages before and after;
- sync running/sending/fetching state.

The numbers must be sufficient to reconcile the multi-second envelope. Small scheduler/logging residuals
are acceptable; a material unexplained residual is itself the result and blocks structural work until it is
identified.

Verification for the executor: focused instrumentation tests where practical, package tests via
`scripts/check-drift.sh`, and one app build through `scripts/xcodebuild-summary.sh` because database
bootstrap tracing is app-compile-risk. No simulator launch is required; Jon owns the device pass.

## Decision gate after S6b

- **Observation branch:** SQLite's profiled COMMIT is fast while `RecipeDetailRequest.fetch` or the residual
  owns the delay. Design S6c around the measured owner — first choices are a constant-region SQLiteData
  capability/upstream ask or a narrower detail request. Do not touch image storage.
- **SQLite/WAL branch:** the profiled COMMIT itself owns the seconds, including with sync idle, and WAL
  state supports a checkpoint hypothesis. Before changing production storage, make the next slice a
  sync-disabled diagnostic copy of the real database and compare the same write with photo BLOBs present
  versus nulled in the copy. Only a decisive A/B result earns an image-storage ADR.
- **Mixed/ambiguous branch:** return to the ADR with the capture. Do not let the executor choose a
  structural fix from partial evidence.

## Consequences

- The current BLOB→`CKAsset` round-trip remains the canonical image persistence/sync path.
- Amendment 3's “commit itself is expensive” and image-externalization direction are hypotheses, not
  settled findings.
- S6b is intentionally small and reversible: instrumentation only, no migration or CloudKit production
  schema consequence.
- The next performance slice is chosen from measured ownership of the latency, not from database size.

---

# Amendment 5 — S6b clears SQLite and fetch; the delay is at the main-actor delivery boundary (S6c)

> **One-line:** S6b's real-device capture reports **writer-wait = 62.1 ms, repository SQL = 0.1 ms,
> SQLite COMMIT = below the logger's 1 µs display resolution, `RecipeDetailRequest.fetch` = 2.85 ms,
> write-return envelope = 5097.7 ms, sync idle**. Roughly **5095 ms remains after the database work**.
> `writeExit` is recorded only after `await database.write` resumes inside the model's `@MainActor` task,
> so the old envelope includes delivery of the observed value to the main queue, SwiftUI invalidation/render
> work scheduled ahead of the continuation, and the continuation's wait to reacquire the main actor. The
> database, WAL/checkpoint, CloudKit triggers, detail query, and image storage are cleared for this symptom.
> **S6c** measures the actor hop, runs one fetch-animation A/B, and counts variation derivation work before
> choosing a fix. **No schema, sync, image, query, or production behavior change.**

Status: **Measured / S6c proposed** — 2026-07-11. Closes Amendment 4's S6b decision gate on a new branch:
neither the SQLite/WAL branch nor the writer-side observation-fetch branch owns the latency. Supersedes the
remaining performance conclusion in Amendment 3. S1/S2/S4/S5b remain correct; S3 (memoizing variation
resolution) returns as a measured candidate, not yet as the chosen fix.

## S6b result

Device capture, variation switch with the engine running but idle:

| Phase | Measured | Interpretation |
|---|---:|---|
| writer-wait | 62.1 ms | No multi-second work queued ahead of the tap |
| repository SQL | 0.1 ms | Variation SELECT/DELETE/INSERT and SQLiteData row triggers are cheap |
| SQLite `COMMIT TRANSACTION` | 0.000000 s | Below log resolution; not the five seconds |
| `RecipeDetailRequest.fetch` | 0.002845375 s | Composite detail observation fetch is cheap |
| write-return envelope | 5097.7 ms | Contains the unresolved main-actor delivery/resumption interval |
| publish-gap | 37.9 ms | Small, but includes the post-write WAL probe and logging; not a pure phase |
| sync | idle | `isRunning=true`, `isSending=false`, `isFetching=false` |

The screenshot contains several adjacent SQLite COMMIT profile lines and all are below display resolution,
which reinforces that neither the variation transaction nor nearby SQLiteData bookkeeping commits are
expensive.

Both WAL `NOOP` probes failed with `SQLITE_LOCKED` (“database table is locked”). They provide no WAL state
for this run, but that no longer blocks the decision: the profiled SQLite COMMIT itself is fast. Remove the
WAL probes in S6c rather than spending another slice making them work.

## Finding 7 — the “write-return envelope” crosses back onto the main actor

`activeVariationSelectionChanged` is a method on the `@MainActor` `RecipeDetailModel`. Its unstructured
`Task` inherits that isolation. `database.write` executes the transaction away from the main actor, but the
timestamp called `writeExit` is taken only after the `await` continuation resumes on the main actor. The
5097.7 ms envelope therefore does **not** mean that `database.write` itself took 5.1 seconds to return on its
executor.

The favored sequence is now:

1. the writer executes SQL and commits immediately;
2. the affected detail observation fetches in ~2.85 ms;
3. SQLiteData's animated fetch scheduler dispatches delivery to the main queue inside `withAnimation`;
4. observation mutation and/or the resulting SwiftUI update/variation derivation occupies or stays ahead
   of the model task's continuation;
5. the continuation finally resumes and records `writeExit` about 5.1 seconds later.

Step 3 is confirmed by SQLiteData 1.6.6's implementation: `@Fetch(..., animation: .default)` uses an
`AnimatedScheduler` whose `schedule` dispatches to the main queue and invokes the delivery action inside
`withAnimation(animation)`. Steps 4–5 are the favored inference, not yet a measurement. S6c separates them.

### Why S3 returns as a candidate

`RecipeDetailModel.displayDetail` calls `resolved(applying:)`. Several computed display properties call
`displayDetail` independently during a body pass, and ingredient display additionally calls
`variationIngredientHighlights`, which decodes the payload and resolves the recipe again. A broad animated
detail publication can therefore repeat the same pure derivation across view evaluation and animation
frames. The earlier ADR correctly identified this duplication but deprioritized it without measuring its
cumulative render-time cost. S6c measures count plus cumulative time before authorizing memoization.

## Decision — S6c: attribute main-actor delivery and render work

### Goal

Split the remaining ~5.1 seconds into:

1. writer/API completion away from the main actor;
2. wait to resume the model task on the main actor;
3. variation resolve/highlight work performed while the detail update renders;
4. the effect of applying `.default` animation to the entire `RecipeDetailRequest` publication.

S6c is an A/B diagnostic slice. It does not ship a speculative performance fix.

### Implementation scope

1. **Timestamp write return off-main.** Extract the variation write into a small explicitly `@concurrent`
   async helper that accepts only the already-captured Sendable inputs, awaits `database.write`, and records
   `writerAPIReturn` immediately after it returns. The `@MainActor` model awaits that helper and records
   `mainActorResume` as its first statement after the await. Log:
   - last SQL statement → writer API return;
   - writer API return → main-actor resume.

   Use structured `async`/`await`; do **not** use `Task.detached`, an unchecked-Sendable box, a singleton,
   GCD, or a semaphore. Swift 6.2 plain `nonisolated async` stays on the caller's actor, so `nonisolated`
   alone is insufficient — the helper must explicitly opt into concurrent execution.

2. **Add a DEBUG fetch-animation switch.** Keep production behavior as the default. In
   `RecipeDetailModel.init`, choose the detail fetch animation from a DEBUG-only launch argument such as
   `-YesChefDisableDetailFetchAnimation`: absent → `.default`; present → `nil`. This preserves SQLiteData
   observation and main-queue delivery in both runs while isolating the broad `withAnimation` transaction.
   Do not remove observation or replace `@Fetch` with a manual read.

3. **Measure variation derivation without changing it.** Add DEBUG-only timing to
   `RecipeDetailData.resolved(applying:)` and `variationIngredientHighlights(for:)`. Log one line per call
   with operation name and duration; the existing variation-switch signpost window supplies the count and
   cumulative duration. Do not add a cache, change return values, or introduce shared mutable counters in
   this slice.

4. **Mark when SwiftUI observes the new selection.** Add a DEBUG-only marker at the narrowest existing
   recipe-detail view boundary that can observe `detail?.activeVariationID` changing (using the modern
   `onChange(of:) { }` form). Log the new selection and timestamp only; do not mutate model state or create
   a second source of truth. This marker distinguishes “value delivered to the view” from “model write task
   resumed.”

5. **Retain the useful probes, remove the dead ones.** Keep writer-wait, repository SQL, SQLite COMMIT,
   detail-fetch, and the variation-switch signpost. Remove both WAL `NOOP` reads and their support types;
   they fail under the live connection topology, contaminate `publish-gap`, and no longer answer the active
   question. Redefine `publish-gap` from writer API return to the view-delivery marker, or retire the name if
   that value cannot be correlated honestly.

6. **No optimization or persistence work.** Do not implement S3 memoization, permanently remove fetch
   animation, restructure the detail view, change `RecipeDetailRequest`, change checkpoint configuration,
   alter images, or touch CloudKit/`SyncEngine` behavior.

### Device pass

Jon performs two otherwise identical base → variation → base runs on the same recipe with sync idle:

1. normal launch, detail fetch animation `.default`;
2. launch with `-YesChefDisableDetailFetchAnimation`, detail fetch animation `nil`.

Capture the `performance` log from variation handler entry until the visible flip completes. No sync-active
run is required: S6b reproduced the full delay while sync was idle.

### Acceptance

For both switches in both runs, the log must unambiguously report:

- writer-wait and repository SQL;
- SQLite COMMIT and detail-fetch duration;
- last-statement → writer-API-return;
- writer-API-return → main-actor-resume;
- view-delivery marker;
- count and cumulative duration of `resolved(applying:)`;
- count and cumulative duration of `variationIngredientHighlights(for:)`;
- whether detail fetch animation was `.default` or `nil`.

The A/B must be sufficient to explain the five-second interval or select the next diagnostic. A material
unexplained gap remains a valid result; the executor returns it rather than choosing a fix.

Verification for the executor: focused tests for unchanged resolve/highlight output and for the DEBUG
animation selection seam where practical; `scripts/check-drift.sh`; one app build through
`scripts/xcodebuild-summary.sh` because the slice changes concurrency isolation and SwiftUI initialization.
No simulator launch is required; Jon owns the device pass.

## Decision gate after S6c

- **Broad-animation branch:** the `nil` run removes most of the actor-resume/visible delay. Permanently
  remove fetch-level animation in the next fix slice and, if desired, add a narrow content transition owned
  by the specific detail subview. Database observation should publish state; it should not animate the
  entire composite detail tree by default.
- **Variation-derivation branch:** resolve/highlight calls own a material share cumulatively. Implement S3
  as originally conceived: one cached resolved detail and highlight map per `(detail identity,
  activeVariationID)`, invalidated when either changes, with behavioral tests.
- **Neither branch:** the main-actor-resume gap remains large, but the A/B and derivations are cheap. Record
  one real-device SwiftUI Instruments trace over the existing `variationSwitch` signpost and use main-thread
  running coverage plus SwiftUI cause-graph fan-in to identify the blocking view/update source. Do not add
  more timestamp probes blindly.
- **Mixed branch:** if both broad animation and repeated derivation contribute materially, bundle the two
  small fixes only if the measurements show they share the same render path and neither changes behavior;
  otherwise fix the dominant owner first and remeasure.

## Consequences

- The current SQLiteData observation, CloudKit sync, and BLOB→`CKAsset` image design remain unchanged and
  cleared for this symptom.
- S6c uses `@concurrent` deliberately so its off-main timestamp is meaningful under Swift 6.2 actor
  semantics; it does not introduce detached work or a new service layer.
- The fetch-animation A/B is DEBUG-only and reversible. Production behavior remains unchanged until a
  device result selects a fix.
- The next implementation slice is either a narrow animation-scope fix, S3 memoization, or a trace-driven
  SwiftUI fix — never an image-storage migration for this bug.
