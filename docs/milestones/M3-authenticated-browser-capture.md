# M3 — In-app authenticated browser capture (consume `WebExtractorKit`)

**Phase D** of [`../implementation-plan.md`](../implementation-plan.md). Build order for
Codex. Architect owns this doc + the ADR; Codex executes the slices below — **one
branch + draft PR per slice, green before ready, never push to `main`.** Label
`question-for-architect` when blocked.

## Goal

Let Jon capture recipes from sites that gate content behind a login (NYT Cooking,
Cook's Illustrated, ATK, Milk Street — issue #29) by **browsing to them in an in-app
`WebView` holding his authenticated session** and capturing the *rendered, logged-in*
DOM. Those sites embed perfect `schema.org/Recipe` data behind the wall; an
unauthenticated GET only sees a teaser. This is an **authentication** problem, not OCR.

The capture flows through the **same review-before-commit + idempotent `importBundle`
path** the paste-a-URL flow already uses (`RecipeCaptureModel` / `RecipeCaptureView`).
The browser is a new **fetch seam**, not a new write path. **Never store credentials** —
the session lives in WebKit's own persistent data store.

M3 ships **two browser surfaces**, both on `WebExtractorKit`, both routing through the
same capture seam:

- **Modal capture session** (`WebExtractorBrowser`) — launched from the capture sheet
  ("Open in browser") for "go fetch this one recipe and come back" (Slice 3).
- **Persistent Browser destination** (`WebBrowserView`) — a top-level
  sidebar/tab section holding a **long-lived, logged-in session** with full chrome
  (address bar, back/forward, home surface of favorite sites), with a "Capture" action in
  the bottom bar (Slice 4). This is the surface Jon asked for (2026-06-25); it's where the
  "log in once, browse freely, capture as you go" workflow lives.

## What's already in place (don't rebuild)

- **The parse engine** is done and tested in `YesChefCore`:
  `WebRecipePageParser.parse(html:sourceURL:capturedAt:) -> ParsedRecipePage`, the
  `WebRecipeCaptureClient` dependency, `WebRecipeCaptureDraft`, and
  `RecipeRepository.importCapturedRecipe(_:in:now:uuid:)` (composed URL+title identity →
  idempotent re-import). See
  [`YesChefPackage/Sources/YesChefCore/WebRecipeCapture/WebRecipeCaptureClient.swift`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/WebRecipeCaptureClient.swift).
- **The capture UI** is done: `RecipeCaptureView` (form: paste URL → Fetch → review
  sections → Save) backed by `RecipeCaptureModel` in
  [`YesChefApp/RecipeModels.swift:281`](../../YesChefApp/RecipeModels.swift). Presented as
  a sheet from `RecipeLibraryView.swift:72`.
- **The browser itself is done and shared.** `WebExtractorKit` (jon-platform package,
  `~/code/jon-platform/packages/WebExtractorKit`) provides `WebExtractorBrowser` — a modal
  "browse + capture one thing" `WebView` host whose injected `onExtract(html, sourceURL)`
  closure is the plugin seam, returning `.extracted` (dismiss) or `.notFound(message:)`
  (stay open). Built on `WebPage` + SwiftUI `WebView`. It is **app-agnostic**; all recipe
  logic stays on our side of `onExtract`.

So M3 is **wiring**, not authoring a browser: consume the package, route its rendered DOM
through our existing parse → draft → review → commit pipeline.

## Cross-repo coupling (read first)

- yes-chef consumes `WebExtractorKit` **by local path**, exactly as galavant does:
  `../../jon-platform/packages/WebExtractorKit` (relative to the yes-chef repo root).
  Requires a sibling `~/code/jon-platform` checkout with the package present on disk.
- jon-platform PR **#15** (the package lift) and galavant **#43** are **open, not merged**;
  the package files already exist in the jon-platform working tree, which is all a
  local-path SPM dependency needs. **Do not** switch to a git-URL dependency — match
  galavant's local-path pattern; converging to a pinned git ref is a later, coordinated
  decision.
- This realizes the **headless-fetcher** half of the ADR-0007 / issue #11 convergence
  (yes-chef's vendored `RenderedDOMFetcher` was copied from Galavant pre-`WebPage`). The
  in-app browser is **net-new** surface, not previously in core.

## House rules (bake into every slice)

- **XcodeGen `project.yml` is the source of truth.** Every product a target imports
  directly MUST be declared in `packages:` and on the target, or `xcodegen generate` drops
  the link → Undefined symbols. Run `xcodegen generate` after editing `project.yml`.
- **Domain logic stays on our side of `onExtract`.** Do **not** add recipe types to
  `WebExtractorKit`. A genuinely reusable browser improvement is a separate jon-platform
  PR; recipe-specific extraction lives in yes-chef.
- **`YesChefCore` must not import `WebExtractorKit`** (keeps core headless-WebKit-free and
  testable on the macOS host). The `WebExtractionOutcome` mapping lives in the **app**
  target; the pure parse/draft logic lives in **core**.
- **Testability:** keep new extraction logic as pure functions in `YesChefCore` (tested);
  the view/model in the app target is a thin host (app target is not unit-testable).
- **Only the `YesChef` app target gets `WebExtractorKit`.** Keep it **out** of
  `YesChefShareExtension` (`APPLICATION_EXTENSION_API_ONLY: YES`; the extension never used
  the headless fetcher and must not pull in `WebView` host APIs).
- **CI is disabled on this repo** (billing). Verify locally every slice:
  `swift test --package-path YesChefPackage`, `bash scripts/check-drift.sh`,
  `xcodegen generate`, and an `xcodebuild build` for an **iOS 27** iPad simulator
  (`xcrun simctl list devices available` → pick an installed iOS-27 iPad, e.g. *iPad Pro
  (11-inch)*). `swiftlint --strict` is pre-existing-red on `main` from oversize files —
  don't let *new* files regress it.

---

## Slice 1 — Consume `WebExtractorKit`; converge the headless fetcher

Wire the package in and delete the diverged copy. **Behavior-neutral** (the headless
render-on-miss path keeps working through the package's fetcher).

1. `project.yml`:
   - Under `packages:`, add
     ```yaml
       WebExtractorKit:
         path: ../../jon-platform/packages/WebExtractorKit
     ```
   - On the **`YesChef`** target only, add the dependency:
     ```yaml
       - package: WebExtractorKit
         product: WebExtractorKit
     ```
2. Delete [`YesChefApp/RenderedDOMFetcher.swift`](../../YesChefApp/RenderedDOMFetcher.swift)
   (the vendored 17-line copy).
3. [`YesChefApp/YesChefApp.swift`](../../YesChefApp/YesChefApp.swift): `import
   WebExtractorKit`. The existing `renderHTML: { url in await
   RenderedDOMFetcher.renderedHTML(of: url) }` (line 16) now resolves to the **package's**
   `RenderedDOMFetcher.renderedHTML(of:)` — identical signature, no call-site change beyond
   the import. Confirm no other `RenderedDOMFetcher` references remain (`grep -rn`).
4. `xcodegen generate`; build the app for an iOS-27 iPad sim; `swift test
   --package-path YesChefPackage`; `bash scripts/check-drift.sh`.

**PR notes:** state that this converges the *headless* fetcher per ADR-0007 / issue #11,
that the package is consumed by local path (sibling jon-platform checkout required), and
that the in-app browser arrives in the next slice. Flag that jon-platform #15 is still open.

---

## Slice 2 — Pure browser-capture seam in `YesChefCore` (tested)

Add the recipe-side logic the browser plugin will call, as **pure, tested** core code —
before touching any view.

1. In
   [`WebRecipeCaptureClient.swift`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/WebRecipeCaptureClient.swift):
   - Add `public var capturedInBrowser: Bool` to `WebRecipeCaptureDraft` (default `false`,
     parallel to `usedRenderedFallback`) so the review UI can label the provenance. Update
     the initializer (keep the existing params defaulted so call sites don't break).
   - Add a pure builder:
     ```swift
     public func browserCapture(html: String, sourceURL: URL?, capturedAt: Date)
       -> WebRecipeCaptureDraft
     ```
     It parses with `WebRecipePageParser.parse(html:sourceURL:capturedAt:)` and returns a
     draft with `capturedInBrowser: true`. (No network — the browser already has the
     rendered DOM. This is *not* a `fetchHTML`/`renderHTML` path.)
   - Expose `WebRecipeCaptureDraft.isUsable` (or reuse `page.isEmpty`) so the app can map
     an empty parse to `.notFound`. Prefer a named accessor over leaking `isEmpty` checks
     into the app.
2. Tests in `YesChefCoreTests` over a **committed sanitized rendered-DOM fixture** (the M2
   Slice 5 pattern): add
   `Tests/YesChefCoreTests/Fixtures/WebRecipeCapture/SanitizedSites/<site>-rendered.html` —
   a realistic *logged-in-shape* page carrying `schema.org/Recipe` JSON-LD, **scrubbed of
   any cookies, tokens, PII, or real account markup**. Assert:
   - good fixture → draft non-empty, ingredients + instructions populated, `sourceURL`
     preserved, `capturedInBrowser == true`;
   - empty/teaser fixture → `isUsable == false`;
   - **idempotency:** building the bundle twice (`makeRecipeBundle`) yields the same
     composed identity (URL+title), matching the paste-URL path.
3. `swift test --package-path YesChefPackage` green; `check-drift.sh` clean.

---

## Slice 3 — In-app browser capture wired to review-before-commit

Now the UI. The browser is a new entry point into the **existing** `RecipeCaptureModel`
draft/review/commit flow.

1. [`RecipeModels.swift`](../../YesChefApp/RecipeModels.swift) — `RecipeCaptureModel`:
   - Add presentation state for the browser (e.g. `var isPresentingBrowser = false`).
   - Add `func ingestBrowserCapture(html: String, sourceURL: URL?) -> WebExtractionOutcome`
     (app target; `import WebExtractorKit`). It calls
     `captureClient.browserCapture(html:sourceURL:capturedAt: now)`, and:
     - if usable → set `self.draft = …`, return `.extracted`;
     - else → return `.notFound(message: "No recipe found on this page — sign in or open
       the recipe, then try again.")` (leaves the browser open).
   - Add `var browserStartURL: URL` deriving from `normalizedURL` when the user typed one,
     else a home/search start from `WebExtractorKit` (`WebAddress.duckDuckGo`, or
     `WebAddress.resolve(_:search:)` — read `WebAddress.swift` for exact signatures).
2. [`RecipeCaptureView.swift`](../../YesChefApp/RecipeCaptureView.swift):
   - In the top section, alongside Fetch, add an **"Open in browser"** button
     (`systemImage: "safari"`) that sets `model.isPresentingBrowser = true`.
   - Present `WebExtractorBrowser` as a **`.fullScreenCover`** (it needs the whole screen
     for login/navigation):
     ```swift
     WebExtractorBrowser(
       startURL: model.browserStartURL,
       title: "Capture from Site",
       confirmLabel: "Capture",
       onExtract: { html, url in model.ingestBrowserCapture(html: html, sourceURL: url) }
     )
     ```
     On `.extracted` the browser dismisses itself and the existing review sections render
     the populated `model.draft`; **Save uses the unchanged commit path** (`commitButtonTapped`).
   - In `RecipeCaptureReviewSections`, add a `LabeledContent("Fetch") { Text("Captured in
     browser") }` row when `draft.capturedInBrowser` (mirror the `usedRenderedFallback`
     row at line 109).
3. **Authenticated session persistence — verify, don't assume.** Confirm
   `WebExtractorKit`'s `WebPage.browser()` (in `WebPageEngine.swift`) uses WebKit's
   **default persistent data store** (no `ephemeral`/`nonPersistent` store) so Jon's login
   cookies survive app relaunch — that "log in once, not per capture" is the entire value
   for paywalled sites. If it uses an ephemeral store, **stop and raise
   `question-for-architect`** (a fix belongs in the jon-platform package, coordinated PR —
   not a yes-chef workaround). **Never persist or read credentials yourself.**
4. **Verify.** Build for the iOS-27 iPad sim. Sim run: open the capture sheet → "Open in
   browser" → load a *public* recipe site → Capture → confirm the draft review populates →
   Save → recipe lands in the library. **Device verify recommended** for a real paywalled
   login (sim auth flows are unreliable); note device results in the PR. Run `swift test`
   and `check-drift.sh`.

---

---

## Slice 4 — Persistent Browser as a top-level nav destination (`WebBrowserView`)

The "log in once, browse freely, capture as you go" surface. A new app section whose
`WebPage` is **owned for the app's lifetime** so the session — and Jon's logins — survive
section switches and relaunch. Reuses the Slice 2/3 capture seam; **build it last**.

1. **A long-lived, host-owned `WebPage`.** `WebBrowserView` requires the host to own the
   `WebPage` (its whole point — nav + session survive view churn). Add a small app-target
   `@Observable final class BrowserModel` holding `let page = WebPage.browser()` (from
   `WebExtractorKit`) and `var recents: [URL]` (cap it, most-recent-first, de-duped). Own
   it as `@State private var browserModel = BrowserModel()` in `AppContainer`
   ([`RecipeLibraryView.swift:7`](../../YesChefApp/RecipeLibraryView.swift)) alongside the
   other models, and thread it through `AppMainLayout` / `AppCompactTabView`. **Do not**
   create the `WebPage` inside a `body` or a per-render view — that would reset the session.
2. **Register the section** in
   [`AppNavigationModels.swift`](../../YesChefApp/AppNavigationModels.swift): add `case
   browser` to `AppSection` (title `"Browser"`, `systemImage "safari"`). Decide placement
   in `allCases` order (suggest after `recipes`). This auto-populates `AppSidebar` (it
   lists `AppSection.allCases`). Then add the matching arms in
   [`RecipeLibraryView.swift`](../../YesChefApp/RecipeLibraryView.swift): the browser is a
   single full-width surface, so give it a **dedicated two-column branch** in
   `AppMainLayout` — `NavigationSplitView { AppSidebar } detail: { BrowserWorkspaceView }`,
   exactly the shape `.mealCalendar` uses — **not** an arm in the three-column
   `content`/`detail` switches. (Rendering it in the middle `content` column with an
   `EmptyView()` `detail` sizes the browser to the narrow column and leaves the detail
   column blank — see the S4-followup nav correction below.) Then add a `BrowserStack` +
   `.tabItem`/`.tag` in `AppCompactTabView`, and the stack view itself (mirror
   `MealCalendarStack`). `BrowserWorkspaceView` carries **no `NavigationStack` of its own**
   in the regular-width path (the split view's detail column already provides one; nesting
   another traps the iPad split view — same rule as galavant's `BrowserScreen`); only the
   compact `BrowserStack` wraps a `NavigationStack`, which is correct.
3. **Wire the view.** Use `WebBrowserView`'s **no-field-bar convenience init** (recipes
   don't need the tap-to-fill `fieldBar` — that's a Galavant place-specific affordance):
   ```swift
   WebBrowserView(
     page: browserModel.page,
     initialURL: nil,                          // land on the home surface
     onNavigate: { browserModel.recordRecent($0) },
     accessory: { page in CaptureAccessory(page: page, onCapture: …) },
     home: { open in BrowserHome(recents: browserModel.recents, onOpen: open) }
   )
   ```
   - **`accessory`** = a "Capture" button (`Label("Capture", systemImage: "plus.circle")`)
     that reads `await page.currentDOM()` and routes the html + `page.url` through the
     **same** `recipeModel.captureModel.ingestBrowserCapture(html:sourceURL:)` from Slice 3.
     On `.extracted`, present the existing review sheet by setting
     `recipeModel.destination.captureRecipe = true` (the `.sheet` at
     [`RecipeLibraryView.swift:72`](../../YesChefApp/RecipeLibraryView.swift) already renders
     `RecipeCaptureView` over `captureModel.draft` → Save uses the unchanged commit path).
     On `.notFound(message:)`, surface the message transiently (e.g. a `browserModel`
     notice/toast); **don't dismiss** the browser. Wire the `onCapture` callback in
     `AppContainer` where it can reach `recipeModel`.
   - **`home`** = a start surface listing **recents** plus Jon's favorite sites (Serious
     Eats, Food & Wine, Bon Appétit, NYT Cooking, Cook's Illustrated, ATK, Milk Street —
     issue #29's named list); each row calls the supplied `open`. The paywalled four are
     the whole reason this surface exists — make them one tap from home.
4. **Session-persistence note repeats here** (same `WebPage.browser()` persistent-store
   requirement as Slice 3 — already verified there; owning the page app-long means a login
   survives section switches *and* relaunch). **Never store credentials.**
5. **Verify.** Build for the iOS-27 iPad sim; confirm the Browser section appears in both
   the sidebar (regular width) and the tab bar (compact). Sim: open Browser → load a public
   recipe site via the address bar → Capture → review sheet populates → Save → recipe lands;
   switch to Recipes and back → the page/session is still there (not reset). **Device verify
   recommended** for a real paywalled login persisting across an app relaunch — note results
   in the PR. `swift test` + `check-drift.sh`.

---

## Slice 4-followup — Full-width Browser (navigation correction)

PR #38 shipped Slice 4 functionally correct but **rendered the browser in the wrong
column** — it followed this doc's (now-corrected) Slice 4 step 2, which told it to put the
browser in the three-column split's middle `content` column with an `EmptyView()`
`detail`. Result on iPad regular width: the browser is sized to the narrow `content`
column and the empty `detail` column eats the rest of the screen (the bug Jon reported
2026-06-30). The spec was wrong, not the execution.

**Fix** (one branch, review-suggestion-sized — fold into #38 or a fast follow):

1. In [`RecipeLibraryView.swift`](../../YesChefApp/RecipeLibraryView.swift)'s
   `AppMainLayout`, give `.browser` its **own two-column branch**, mirroring the existing
   `.mealCalendar` branch:
   ```swift
   } else if selectedSection == .browser {
     NavigationSplitView {
       AppSidebar(selection: $selectedSection)
     } detail: {
       BrowserWorkspaceView(model: browserModel, onCapture: onBrowserCapture)
     }
   } else if selectedSection == .mealCalendar {
     …
   ```
2. Delete the `.browser` arms from the three-column `content` and `detail` switches.
3. The session does **not** reset across this 2-/3-column structural-identity change: the
   `WebPage` is host-owned in `BrowserModel`, not in the view. Confirm by switching
   Recipes ⇄ Browser — the loaded page/login survives.

**Verify.** iOS-27 iPad sim: Browser fills the detail area edge-to-edge (no blank right
column); compact tab unaffected. `swift test` + `check-drift.sh`.

---

## Slice 5 — DEBUG capture-DOM export (diagnostics for the image + prose gaps)

Jon's 2026-06-30 device capture of an ATK recipe surfaced two **content** gaps (distinct
from the nav bug): the hero image renders as a placeholder, and editorial prose blocks
("Why This Recipe Works", "Before You Begin") are dropped. Diagnosing either needs the
**real rendered, logged-in DOM** — which we can get **without handling Jon's credentials**,
because the captured HTML is already persisted on `recipe.originalImportText` (and the
`originalSnapshot`). This slice adds a tiny, **DEBUG-only** affordance to get that artifact
off-device so we can build a committed *sanitized* fixture and fix the gaps properly.

Scope is **diagnostics only** — no parser or pipeline behavior change.

1. Add a `#if DEBUG` action (share sheet, or write-to-Files) that exports the captured
   rendered DOM for a captured recipe — source it from `recipe.originalImportText` so it
   works for already-saved recipes, no re-capture/re-login. A natural home is the existing
   "View Original" / original-snapshot surface, gated `#if DEBUG`. Keep it out of release
   builds and out of any user-facing menu.
2. **No credentials, ever.** The export is the rendered DOM only. Before it leaves the
   device it's Jon's to inspect; the architect sanitizes it (scrub cookies, tokens, PII,
   account markup) into
   `Tests/YesChefCoreTests/Fixtures/WebRecipeCapture/SanitizedSites/atk-rendered.html` —
   the same fixture pattern as Slice 2.
3. **Verify.** Build the iOS-27 iPad sim; confirm the action is absent in a Release config
   and present in Debug. `swift test` + `check-drift.sh`.

This unblocks two follow-on slices, both informed by the fixture and tracked separately
once we've seen the real DOM:

- **Image bytes:** the capture pipeline records photos as `sourceURL` only
  (`makeRecipeBundle`, [`ParsedRecipePage.swift`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/ParsedRecipePage.swift));
  nothing downloads them, and `RecipeDetailModel.displayablePhotos` filters out any photo
  lacking `displayData`/`thumbnailData` — so the hero shows a placeholder (true for the
  paste-URL path too). The fix downloads hero bytes; **note** the download may need to run
  in the authenticated `WebPage` context (cookie-gated CDN), which is why we want the real
  fixture/DOM before designing it.
- **Editorial prose:** "Why This Recipe Works" / "Before You Begin" are not part of
  `schema.org/Recipe` JSON-LD, so the schema-first parser drops them by design. The fixture
  tells us whether ATK exposes them in JSON-LD (map to `summary`/notes) or only in
  site-specific DOM (a scoped scrape) — a deliberate feature decision, not a bug.

---

## Out of scope (do not build now)

- The tap-to-fill **`fieldBar`** field-capture bar (`WebFieldCaptureBar` / `WebCaptureField`) —
  that's a Galavant place-specific affordance (hours/rating chips); recipes capture the
  whole page, so use `WebBrowserView`'s no-field-bar init.
- Photo → LLM recipe capture (a separate, later fallback for sources with *no* structured
  data; not the answer to paywalled sites).
- Switching `WebExtractorKit` to a git-URL dependency or any package API change (those are
  coordinated cross-repo PRs the architect sequences).
- ADR authoring: the architect lands **ADR-0009** (in-app authenticated browser capture +
  the consume-the-package convergence) and ratifies this milestone. Reference it as
  forthcoming.
