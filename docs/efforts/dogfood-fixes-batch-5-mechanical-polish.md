# Effort: Dogfood fixes — batch 5 (mechanical polish: detail, editor, search, capture)

**Type:** Layout/UX nits + real bugs, all mechanical and low-ambiguity. **One Codex dispatch, one PR.**
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
Sourced from Jon's dogfood pass 2026-07-08.

**Batching intent:** everything here is bundled into a **single dispatch** on purpose — the surfaces are
adjacent and none of it needs a design decision. The four slices below are an implementation checklist,
**not** separate PRs. (Design-heavy dogfood items — editable AI preview, comment ingestion, workbench
provenance, browser autofill — are held for their own ADR-gated efforts.)

**Reuse leverage:** Slice C's matcher serves **three** pickers; Slice D lands on the capture-review UI
duplicated across the share extension and the in-app flow; Slice B's auto-growing editor is the shared
`StackedTextEditor`, so it also fixes Summary/Notes/Source.

**Read first:** `RecipeDetailView.swift` (toolbar ~78–116, `chatButtonTapped` ~179, `RecipeReaderView`
~188), `AppMainLayout.swift` (focus toggle ~91–109 / 287–300), `RecipeEditorView.swift`,
`RecipeEditorModels.swift` (`saveButtonTapped` ~149), `RecipeEditorDraft.swift`, `FormFields.swift`
(`StackedTextEditor` ~34), `RecipeFilterPickerViews.swift` (~87–89), `MenuViews.swift` (~570–576),
`WorkbenchViews.swift` (~690–695), `ShareViewController.swift` (`ShareCaptureReviewSections` ~237, URL
resolution ~444–469), `RecipeCaptureView.swift` (`RecipeCaptureReviewSections` ~116),
`RecipeImportIdentity.swift`.

**Build/verify:** package `swift build` + core tests for the Core changes (Slice B draft/save, Slice C
matcher, Slice D URL strip — unit-test each). Toolbar/layout/editor slices are iPad-primary — Jon does the
device pass on `iPad Pro 13-inch (M5)` and `iPhone 17 Pro`. `xcodegen generate` if files are added.

---

## SLICE A — recipe detail toolbar & layout

Three nits on the recipe detail surface:

1. **Chef It Up below Notes.** Reorder `RecipeReaderView` so Chef It Up renders after Notes, in **both**
   the iPad long-scroll and the iPhone segmented (`CompactSection`) layouts.
2. **Focus = highlighted leading chevrons.** Drop the labeled "Focus" control; use the double-arrow
   expand chevrons as the toggle and **highlight** them (tint/filled) when `columnVisibility == .detailOnly`.
   Same glyph enters and exits focus. Move the chevrons **and** the Edit button (currently trailing
   `.primaryAction`, ~95–100) to the **leading** edge of the detail toolbar. Reconcile that focus state
   lives on `AppMainLayout`'s `columnVisibility` while Edit lives in the detail toolbar. Keep
   keyboard/VoiceOver affordances.
3. **AI (Chat) button toggles.** On iPad split, `chatButtonTapped()` only forces detent `.balanced`
   (~179) — never closes. Make it a toggle using existing `ChatWorkspaceDetent` cases: visible → collapse
   to reader-only; hidden → `.balanced`. Leave the iPhone dismissible-sheet path alone.

**Acceptance:** Chef It Up sits below Notes on both idioms; the leading chevrons highlight in focus and
toggle back out with no leftover "Focus" label; Edit is leading; the Chat button opens *and* closes the
iPad chat on repeated taps.

## SLICE B — recipe editor: growing text, Make-Ahead/Chef-It-Up, async save

1. **Auto-growing multiline editor (real bug — Jon screenshots 2 & 3).** Instructions only scroll to ~2
   steps because `StackedTextEditor` pins `TextEditor` to a fixed `minHeight` (`FormFields.swift` ~42–43)
   and the inner editor traps its own scroll inside the `Form`. Make `StackedTextEditor` **grow to fit
   content** (measure height, drive the frame; the Form is the scroller; `minHeight` becomes a floor, not
   a cap). Fixes Instructions, Summary, Notes, Source notes at once.
2. **Make-Ahead + Chef It Up editable (real bug).** `RecipeEditorDraft` has no `makeAhead`/`chefItUp`
   fields (~4–33), so the editor drops them. Add both to the draft, load from `detail.recipe`, map back in
   `RecipeRepository.save`, and add editor fields (multiline, using the grown editor). **Guard against
   clobbering** — a save that doesn't touch them must preserve existing values; add a core test.
3. **Async save + spinner.** `saveButtonTapped()` does a synchronous whole-graph + photo-BLOB
   `database.write` on the main actor (~149–165). Move it off-main (async `Task`), add `isSaving`, show a
   Save-toolbar spinner, disable Save/Cancel while saving, dismiss on success, keep the existing error
   alert and validation gate; no double-save on rapid taps.

**Acceptance:** long Instructions fully scroll (every step reachable) on iPad + iPhone; Make-Ahead + Chef
It Up show/edit/persist and never wipe untouched values; Save shows an immediate spinner, stays
responsive, dismisses on completion, surfaces errors. Core tests green.

## SLICE C — tokenized recipe search (shared matcher)

**Bug:** "Sous Vide pork" doesn't return "Sous Vide indoor pulled pork" — pickers use
`localizedCaseInsensitiveContains` (contiguous substring): `RecipeFilterPickerViews.swift` ~89,
`MenuViews.swift` ~572–576, `WorkbenchViews.swift` ~693.

- Add a tokenized matcher in `YesChefCore`: split the query on whitespace; match when **every** token
  appears (case/diacritic-insensitive, per-token substring so "por"→"pork"); empty query matches all.
  Apply to all three pickers against the fields each already searches (keep MenuViews' title/subtitle/
  summary/tags/categories breadth; add subtitle to the title-only pickers).
- Unit-test: the "Sous Vide pork" case, out-of-order tokens, diacritics, empty query, all-tokens-required.

**Acceptance:** "Sous Vide pork" matches "Sous Vide indoor pulled pork" in every recipe picker; existing
single-word searches unaffected.

## SLICE D — capture review: strip query string + editable fields

Two changes on the capture-review flow (both hosts: `ShareCaptureReviewSections` ~237 and in-app
`RecipeCaptureReviewSections` ~116 — same pattern, factor shared bits if it de-dupes).

1. **Strip query string, keep canonical.** When normalizing the incoming shared/source URL (share ext URL
   resolution ~444–469, and the in-app `sourceURL` set), drop the **query + fragment** from the URL used
   for provenance/dedup. Do **not** touch a separately-extracted canonical URL (`rel="canonical"`/`og:url`)
   — it stays the preferred functional link. Confirm `RecipeImportIdentity` dedup improves (tracking-param
   variants now collide) and no test asserts the old query-bearing form.
2. **Editable title/summary/servings/total-time.** These render read-only as `Text` (~248–262 / ~127–141)
   while editorial blocks are already editable `TextField`s (~310 / ~199). Make the four fields editable,
   threading edits into the same draft/model the sheet commits (mirror the editorial-block binding). Total
   time is `Int?` minutes — numeric field.

**Acceptance:** a shared URL with `?utm_...` saves clean while the page's canonical URL still resolves;
title/summary/servings/total-time are editable before save on both the share sheet and in-app capture, and
the saved recipe reflects the edits; ingredients/instructions/editorial editing unchanged.

---

## Slice D follow-up — strip only trackers, not the whole query (review fix, committed on branch)

The first cut of Slice D removed the **entire** query string, which would have collapsed distinct recipes
on query-param-based sites (`?id=123` vs `?id=456`) to one dedup key. Fixed in commit
`Preserve meaningful recipe URL queries`: `strippingQueryAndFragment` →
`strippingTrackingParametersAndFragment`, which filters `queryItems` against a tracking-key denylist
(`utm_*` prefix + `fbclid`/`gclid`/`gbraid`/`wbraid`/`mc_cid`/`mkt_tok`/`msclkid`/`ttclid`/… exact,
case-insensitive), keeps meaningful params, still drops the fragment. Core test now asserts
`?id=123` ≠ `?id=456` while tracker-only variants still collapse. **Known accepted asymmetry:** the parsed
canonical (`og:url`) is still preferred verbatim and not run through the stripper — trusting the site's
declared canonical; revisit only if a real site's canonical carries trackers.
