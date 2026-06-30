# Effort: Download hero image bytes for browser-captured recipes

**Type:** Feature gap (M3 — Authenticated Browser Capture; follow-on from Slice 5)
**Owner:** Codex (implement) · Jon (architect/review)
**Status:** Ready to scope into Next Up after the Share-Extension refresh effort merges

## Symptom

A recipe captured in the in-app browser (or pasted by URL) shows a **placeholder** where
the hero photo should be, even though the page clearly had one. The recipe imports fine;
only the image is missing.

## Root cause (verified)

The capture pipeline records photos as a **`sourceURL` only** and never downloads the
bytes, while the detail UI filters out any photo with no local image data.

- `ParsedRecipePage.makeRecipeBundle(...)` builds each `RecipePhoto` from `imageURLs` with
  `imageDataReference` + `sourceURL` set but **`displayData`/`thumbnailData` left nil** —
  `YesChefPackage/Sources/YesChefCore/WebRecipeCapture/ParsedRecipePage.swift:125`.
- `RecipePhoto` carries optional `displayData`/`thumbnailData`
  (`YesChefPackage/Sources/YesChefCore/Models.swift:765`).
- `RecipeDetailModel.displayablePhotos` only surfaces photos where
  `displayData != nil || thumbnailData != nil` — `YesChefApp/RecipeModels.swift:643`. With
  both nil, the hero is filtered out → placeholder. (This is true for the paste-URL path
  too, not just browser capture.)

**Finding from the Slice 5 fixture (`atk-rendered.html`):** the ATK hero lives on **public
Cloudinary** (`res.cloudinary.com/hksqkdlah/…`), exposed in the JSON-LD
`image[].contentUrl`. It is **not** a cookie-gated CDN — so a plain unauthenticated
`URLSession` download is sufficient. The milestone doc hedged that the download "may need to
run in the authenticated `WebPage` context"; the real DOM says **it does not** for ATK.
Treat authenticated-CDN sources as a later, separately-evidenced case.

## Reuse (this is mostly assembly, not net-new)

The bytes→stored-photo half already exists and is proven on the Paprika path:

- `RecipePhotoProcessor.process(...)` turns raw image `Data` into a `ProcessedRecipePhoto`
  (`displayData`, `thumbnailData`, `mediaType`, `pixelWidth/Height`, `checksum`) —
  `YesChefPackage/Sources/YesChefCore/RecipePhotoProcessing.swift:63`.
- `PaprikaHTMLImport` already downloads image data and populates `RecipePhoto.displayData`/
  `thumbnailData` through that processor — `PaprikaHTMLImport.swift:158`. **Mirror this.**
- `WebRecipeCaptureClient` already does network via `URLSession.shared.data(for:)` in
  `fetchHTML` (`WebRecipeCaptureClient.swift:185`), so a photo fetch belongs on the same
  client as an injectable dependency (keeps it testable).

## Goal

A browser- or URL-captured recipe with a usable hero URL lands in the library with the hero
rendered, not a placeholder — using the existing photo-processing pipeline, no schema or UI
change.

## Design

1. **Add a `fetchImageData` capability to `WebRecipeCaptureClient`** (a closure dependency
   alongside `fetchHTML`, with a `testValue` that returns canned bytes). Live value: plain
   `URLSession.shared.data(for:)` with the same UA header pattern as `fetchHTML`, status
   validation, and a sane byte cap.
2. **Hydrate photos before commit, not inside the transaction.** `importCapturedRecipe`
   (`WebRecipeCaptureClient.swift:215`) runs synchronously inside `db.write`, so the async
   download must happen earlier. In the ingest/draft step (app side; the same place the draft
   is assembled), fetch bytes for the hero `sourceURL`, run `RecipePhotoProcessor.process`,
   and attach `displayData`/`thumbnailData` to the photo(s) on the `ParsedRecipePage` /
   draft, then import as today.
3. **Scope v1 to the hero (first image).** Process the representative image; leave gallery
   backfill as a follow-up. A failed/missing download must be non-fatal — import proceeds
   with the `sourceURL`-only photo exactly as today (graceful degradation, no regression).

## Scope decisions

- **In scope:** download + process the hero for the browser-capture and paste-URL paths,
  reusing `RecipePhotoProcessor`; injectable fetch dependency; non-fatal failure.
- **Out of scope:** authenticated/cookie-gated CDN downloads (no evidence yet that any target
  needs it — revisit with a real fixture if one appears); full gallery hydration; re-fetching
  photos for already-imported recipes (a possible later backfill).
- **Sync-safety (forward note):** this only populates local `displayData`/`thumbnailData` on
  the photo row at import time; it adds no schema and touches no identity. Nothing here needs
  the later `SyncEngine` path. Image-blob sync strategy is a separate sync-era decision.

## Verification

- Unit (deterministic, no network): with a stub `fetchImageData` returning fixture bytes,
  capture from `atk-rendered.html` and assert the resulting hero `RecipePhoto` has non-nil
  `displayData`/`thumbnailData` and that `displayablePhotos` surfaces it. Assert a failing
  fetch still imports the recipe (photo present, data nil).
- `swift test --package-path YesChefPackage` green; `scripts/check-drift.sh` clean.
- Jon UI pass on iPad/iPhone sim: capture a public ATK recipe → hero renders in detail, not a
  placeholder.

## Open questions for the implementer to confirm

- Exact seam for the hydrate step: in `RecipeCaptureModel.ingestBrowserCapture` (app) vs. a
  new client method invoked from there. Prefer the one that keeps `importCapturedRecipe` pure
  and the download injectable/testable.
- Which URL is canonical for the hero — the JSON-LD `image.contentUrl` vs. the
  `RecipeBodyImageExtractor` candidates (`ParsedRecipePage.imageURLs` ordering). Confirm the
  first `imageURL` is the representative one for ATK and the common case.

---
*Derived from the M3 Slice 5 follow-on notes
(`docs/milestones/M3-authenticated-browser-capture.md`) and the sanitized fixture
`YesChefPackage/Tests/YesChefCoreTests/Fixtures/WebRecipeCapture/SanitizedSites/atk-rendered.html`.*
