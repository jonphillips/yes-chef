# ADR-0005 - Image storage and processing

Status: Accepted - 2026-06-16

## Context

Yes Chef will receive recipe images from several paths:

1. Paprika HTML imports, including multiple images per recipe and image-only recipe
   evidence such as "see attached photo."
2. User-selected recipe photos.
3. Future web/import capture, including recipe page images.
4. Future recipe transfer between private libraries.

The Galavant image ADR settled a useful house pattern: no server/object store by
default, split pure image processing from stack-specific storage, keep rows light, and
sync display-ready bytes rather than decoded bitmaps. Yes Chef should align with that
strategy, with one app-specific caution: recipe images are sometimes content, not just
decoration. A photo may contain the actual ingredient list or method, so processing
must preserve readability.

ADR-0002 already chooses CloudKit via SQLiteData and no server/auth. ADR-0003 chooses
private per-person libraries with recipe transfer by copy. Those decisions mean recipe
photos should be owned by a user's private library copy and should transfer as part of
the recipe bundle.

## Decision

Use the shared house image strategy, adapted for recipe evidence.

1. **No S3, no image server, no upload manager.** Images live in the local-first
   SQLiteData/CloudKit world. Reopening a separate object store requires a new ADR.

2. **Split processing from storage.** Image processing is a pure module/function:
   source bytes in, display image data plus thumbnail data out. It imports Foundation
   and image-processing frameworks only, not SwiftUI, SQLiteData, CloudKit, or app UI.
   Storage remains Yes-Chef-specific.

3. **Photos are separate rows, never columns on `Recipe`.** A recipe can have many
   photos. The current `RecipePhoto` entity is the recipe-owned photo surface; it may
   either grow display/thumbnail data fields directly or point at a future reusable
   `ImageAsset` table. In either shape, recipe list/detail fetches should not drag large
   image payloads unless they ask for them.

4. **Display tier is canonical for MVP.** On import or selection, create a
   display-ready compressed image and a small thumbnail. The Galavant starting point
   of roughly 1600 px on the longest edge and roughly 300 KB is a good default for
   ordinary photos, but Yes Chef may use a larger budget for document/reference photos
   where text readability matters.

5. **Full-resolution originals are deferred.** If a real need appears, store originals
   as file-backed CloudKit assets rather than oversized inline fields, after verifying
   current SQLiteData support. Until then, the display tier is the synced canonical
   image.

6. **Decoded bitmaps are local cache only.** Synced data is compressed image bytes and
   metadata. Decoded `UIImage`/bitmap/cache files are device-local and can be rebuilt.

7. **One downstream pipeline.** Paprika imports, Photos picker input, web images, and
   future transfer imports all feed the same processing/storage path after source bytes
   are acquired.

8. **Preserve provenance.** Imported photos should keep source metadata where possible:
   original import-relative path, source URL, caption, source type, dimensions, and
   enough checksum/identity information to deduplicate or diagnose import issues.

## Consequences

- Multiple photos per recipe are first-class. Do not design recipe UI or import logic
  around a single hero image.
- Paprika's image references are acceptable for the parser spike, but production import
  must copy/process available image bytes into app-owned storage.
- Missing image files should produce import warnings, not fail the whole recipe.
- Image processing must be quality-aware. If a text-heavy recipe image becomes
  unreadable at the default display budget, choose a larger display tier or warn before
  accepting a lossy import.
- Recipe transfer bundles should include photo payloads or app-owned photo references,
  not private Paprika export paths.
- CloudKit/SQLiteData details for large originals remain a future verification task;
  do not assume current `CKAsset` bridging behavior without checking at that milestone.

## Relationship To Current Implementation

`RecipePhoto` now stores app-owned display/thumbnail bytes and provenance fields.
`imageDataReference` is an app-owned reference string; imported Paprika paths are kept
in `originalSourcePath` for provenance and diagnostics. Full-resolution originals and
more careful quality policies for text-heavy reference photos remain deferred.
