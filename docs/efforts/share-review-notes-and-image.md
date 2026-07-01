# Effort: Show & curate notes + hero image in the share-extension review UI

**Type:** Feature gap (M3 — Authenticated Browser Capture; follow-on from Slice 5)
**Owner:** Codex (implement) · Jon (architect/review)
**Status:** Next Up
**Branch:** Implement on the existing `codex/editorial-prose-notes` branch, folding into the
editorial-prose PR — **not** a new branch. (The editorial-prose extractor work is already
committed there; this completes the same user-visible thread.)

## Symptom

Editorial notes and the hero image now flow through capture correctly (both share extension
and in-app browser), and they land on the saved recipe. But the **share-sheet review screen** —
the screen Jon uses to confirm what's coming in before tapping Save — shows neither:

- It does not display the captured **notes** (the "Why This Recipe Works" / "Before You Begin"
  editorial blocks). Jon wants them visible **and editable here**, so he can trim nonsense out
  *on the way in* rather than after import.
- It does not display the incoming **hero image**.

`ShareCaptureReviewSections` renders Review / Source / Warnings / Ingredients / Instructions and
stops there (`YesChefShareExtension/ShareViewController.swift:165`, last section ends at `:238`).

## Why this is cheap (key facts, verified)

- **Editing needs zero commit-path changes.** The share commit builds the bundle straight from
  the draft: `let bundle = try draft.page.makeRecipeBundle(...)`
  (`YesChefPackage/Sources/YesChefCore/WebRecipeCapture/WebRecipeCaptureClient.swift:272`). The
  model already holds the draft as mutable, `@Observable` state: `var draft: WebRecipeCaptureDraft?`
  (`ShareViewController.swift:62`). So if the review UI edits `draft.page.editorialBlocks` in
  place, the existing import honors it. No new DTO, no YesChefCore change, no schema change.
- **Editorial blocks are already on the page.** `ParsedRecipePage.editorialBlocks:
  [ParsedRecipeEditorialBlock]` (`ParsedRecipePage.swift:59`). Each block is a value type with
  `var label`, `var text`, and a `noteText` getter that interpolates `"label\n\ntext"`
  (`ParsedRecipePage.swift:23`–`35`). That getter is what becomes the saved note
  (`makeRecipeNotes`, `ParsedRecipePage.swift:288`).
- **The hero bytes are already hydrated in memory.** `loadSharedPage` calls
  `hydrateHeroImage` (`ShareViewController.swift:83`; impl at `WebRecipeCaptureClient.swift:102`),
  which populates `page.processedImages` for the hero. The hero URL is `page.imageURLs.first`
  (matches the `kind == .hero` rule in `makeRecipeBundle`, `ParsedRecipePage.swift:160`).
  `ProcessedRecipePhoto.displayData` is non-optional `Data`; `thumbnailData` is optional
  (`RecipePhotoProcessing.swift:38`–`44`).

## Goal

On the share-sheet review screen: display the captured editorial notes and let Jon edit or
delete them before saving, and show a preview of the incoming hero image. Saved recipe reflects
whatever the review screen shows at Save time.

## Design

All changes are inside `YesChefShareExtension/ShareViewController.swift`. Keep it small and in
the existing `Form`/`Section` style.

1. **Model accessor for editing** (so the optional draft doesn't make bindings ugly). Add to
   `ShareCaptureModel`:
   ```swift
   var editorialBlocks: [ParsedRecipeEditorialBlock] {
     get { draft?.page.editorialBlocks ?? [] }
     set { draft?.page.editorialBlocks = newValue }
   }
   ```

2. **Editable Notes section.** Give the review the model (e.g. `@Bindable var model`, or a
   dedicated `ShareCaptureNotesSection(model:)`), and render a `Section("Notes")` only when
   `!model.editorialBlocks.isEmpty`:
   - One editable row per block: the block **label** as a header (e.g. `.font(.headline)` /
     secondary caption) and a `TextField(..., axis: .vertical)` or `TextEditor` bound to the
     block's `text`.
   - `.onDelete` to remove an entire junk block.
   - **ForEach identity:** the block value type has no `id`. Prefer index-based iteration
     (`ForEach(model.editorialBlocks.indices, id: \.self)` with `$model.editorialBlocks[i].text`,
     plus `.onDelete { model.editorialBlocks.remove(atOffsets: $0) }`) so you don't have to add
     an identity field to a parse-layer value type. If index-based focus proves janky, the
     fallback is making `ParsedRecipeEditorialBlock: Identifiable`, but try without first.

3. **Save-time cleanup.** When a user clears a note's text, it should drop, not save as a bare
   `"Label\n\n"`. In `saveButtonTapped` (or via the setter), filter out blocks whose `text` is
   empty after trimming before commit. Note that in-place `.text` mutation bypasses the
   `ParsedRecipeEditorialBlock` init's trimming — that's fine while typing; just trim/drop at
   the save boundary.

4. **Hero image section (read-only).** Add a `Section` that, when a hero photo exists, renders
   it: resolve `page.imageURLs.first`, look up `page.processedImages[heroURL]`, build a
   `UIImage(data: photo.thumbnailData ?? photo.displayData)`, and show
   `Image(uiImage:).resizable().scaledToFit()`. Skip the section silently if there's no hero or
   the bytes don't decode.

## Scope decisions

- **In scope:** notes display + inline edit + per-block delete; read-only hero image preview;
  edits/deletes honored at Save. All in the share extension view layer.
- **Out of scope:** making ingredients/instructions editable in either review sheet (they stay
  read-only `Text`). No general share-extension editor — this is targeted curation of notes only.
- **Delivered on both surfaces (scope extension, Jon's call at review):** the original brief
  scoped this to the share extension only. During implementation the same notes show/edit/delete
  + read-only hero preview was also added to the **in-app browser capture** review
  (`RecipeCaptureView` / `RecipeCaptureModel`), mirroring the share path so the two surfaces stay
  in parity. Both are shipped in PR #44. (Follow-on: the notes/hero UI + model helpers are now
  near-duplicated across the app and share-extension targets — a shared component/module is a
  tracked cleanup, not a blocker.)
- **Directional note:** this is the review screens' *first* editing affordance; everything there
  was read-only before. Keep it minimal so the screen stays "confirm + light curate," not a full
  editor.
- **Sync-safety:** no model/schema change. Edits happen in memory pre-import; the image preview
  only displays already-hydrated bytes. Nothing for the later `SyncEngine` path.

## Verification

- **Core test (cheap, worth adding):** mutate `page.editorialBlocks` (edit one block's text,
  empty another) → `makeRecipeBundle` → assert the resulting `recipeNotes`/`bundle.notes`
  reflect the edit and that the emptied block is dropped (pairs with the save-time filter).
  Extends `WebRecipeEditorialProseTests`.
- `swift test --package-path YesChefPackage` green; `scripts/check-drift.sh` clean.
- `xcodegen generate` after any new Swift file; build `YesChef` for `iPad Air 13-inch (M4)`.
- **Jon UI pass (primary):** share an ATK recipe → review screen shows the notes (editable) and
  the hero image; edit/delete a note; Save; confirm the saved recipe reflects the curated notes.

## Notes for the dispatcher

- This **folds in the former Ready Effort "Show the hero image in the share-extension review UI"**
  — that item is now part of this brief and should be removed from the queue.
- The **real-device jetsam check** Ready Effort stays separate and in the queue. The image
  preview here reads bytes that are *already* hydrated, so it does not change the memory profile
  that effort is about.

---
*Anchors verified against `YesChefShareExtension/ShareViewController.swift`,
`YesChefPackage/Sources/YesChefCore/WebRecipeCapture/{WebRecipeCaptureClient,ParsedRecipePage}.swift`,
and `RecipePhotoProcessing.swift` on branch `codex/editorial-prose-notes`.*
