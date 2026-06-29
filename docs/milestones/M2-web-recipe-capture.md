# Milestone 2 — Web recipe capture (the daily-driver unlock)

*Build order for Codex. Architect/editor-in-chief: this doc is the contract; the
strategic arc is in [../implementation-plan.md](../implementation-plan.md) (now Phase C),
the import format notes in [../IMPORT_EXPORT.md](../IMPORT_EXPORT.md) (§2.4 schema.org,
§2.7 images), the keystone identity in
[M1-paprika-import-hardening.md](M1-paprika-import-hardening.md) (Slices 1 & 3, which
this milestone reuses), and the house rules in `/Users/jon/code/jon-platform/docs/ios/`.
Where this doc and those conflict, stop and flag it — don't silently diverge.*

## The milestone in one sentence

Give Yes Chef a **trustworthy way to capture a *new* recipe from a web page** — paste-a-URL
and a share extension — by **harvesting Galavant's proven capture engine** and re-targeting
it to `schema.org/Recipe`, reusing M1's import identity and review-before-commit so every
capture is **idempotent and never pollutes the library** — making the app Jon's **daily
driver** *before* sync turns on.

## Why this is M2 (and why it gates sync, like M1)

M1 lands Jon's **existing** library. It does nothing for the **next** recipe he finds in
Safari — and without a capture path, that recipe goes into Paprika and his behavior never
shifts. Web capture is the behavior-shift unlock, and it belongs **before** sync for the
same reason M1 does:

- **It is another write path subject to the one-way gate.** A share extension creates
  recipes. An un-idempotent capture pollutes the iCloud private zone exactly like a bad
  bulk import (per [../implementation-plan.md](../implementation-plan.md): sync is a
  one-way gate). So capture must be idempotent **before** the first zone write.
- **It is cheap on M1, not a new pillar.** Capture identity *is* M1's composed key
  (normalized source URL + title). A web page almost always carries a real source URL —
  so capture is the **strong** (URL-present) path of M1's identity, never the weak
  title-only fallback. Re-capturing the same URL is a lookup → reported already-captured →
  skipped (edits sacred). Review-before-commit is M1 Slice 3, reused.
- **The hard part is already solved elsewhere in the portfolio.** Galavant
  (`/Users/jon/code/galavant/galavant`, live, same SQLiteData + swift-dependencies stack)
  has a mature, layered capture engine — JSON-LD → OpenGraph → microdata value-votes — plus
  a **headless rendered-DOM fetcher** for JS-heavy pages (its ADR-0024). We adopt it, we do
  not reinvent it.

## Adoption strategy (decided with Jon: harvest now, converge later)

We **harvest** Galavant's *domain-agnostic* capture engine into YesChefCore and re-target it
to recipes — Galavant stays untouched. The **shared-package** north star (one capture engine
both apps depend on — Galavant's backlog "Portfolio extraction seams") is recorded as a
forthcoming **ADR-0007**, not built now. Codex keeps the harvested engine behind the **same
clean seams** Galavant uses, so a later extraction into a shared package is mechanical.

What is **directly harvestable** (domain-free of `Idea`/MapKit by design):

| Galavant source | Role |
|---|---|
| `GalavantCapture/PageParser.swift` + `JSONLDExtractor`/`MetaExtractor`/`MicrodataExtractor`/`ParseBuilder`/`AttributeVotes` | the layered value-vote engine |
| `GalavantCapture/TextCleaning.swift`, `BodyImageExtractor.swift`, link-density strip | body cleaning + image hygiene |
| `GalavantWeb/RenderedDOMFetcher.swift` | headless JS-rendered DOM (render-on-miss) |
| `GalavantShare/CaptureExtraction.swift` (**page-share path only**) | rendered-DOM-from-JS-preprocessor + URL-fallback fetch |
| `GalavantCaptureUI/CaptureConfirmView.swift`, `Browser/BrowserScreen[Model].swift`, `GalavantWeb/WebExtractorBrowser.swift` | confirm-UI and in-app-browser **patterns** |

What must be **re-targeted to recipes** (the place-specific layer we replace):

- `SchemaOrg.swift`'s place vocabulary → `schema.org/Recipe` properties (`recipeIngredient`,
  `recipeInstructions`, `recipeYield`, `prepTime`/`cookTime`/`totalTime`, `recipeCategory`,
  `aggregateRating`, `author`, `image`, `description`) — the **same itemprops the Paprika
  importer already reads** (IMPORT_EXPORT §2.4).
- `ParsedPage`'s place field set (address/coordinate/phone/openingHours) → a recipe-shaped
  result projected into M1's `RecipeBundle`.
- The confirm UI's place fields → recipe fields; the share extension's **MapKit/vCard
  location branch is dropped entirely**.

## Definition of done

A reviewer can, in the running app:

1. Paste or enter a recipe **URL** → the app fetches the page and shows a **review** screen
   *before* any write: title, ingredients (with section headings), instructions, source
   URL/author, image — with parse warnings surfaced — and **cancel** leaves the library
   untouched.
2. Commit → the recipe lands with `originalImportText` = the **raw fetched HTML preserved
   whole**, source URL captured as provenance.
3. Capture the **same URL again** → reported **already-captured**, **zero duplicate** rows
   (M1 identity, URL-present strong path).
4. From Safari's (or any app's) **share sheet**, "Save to Yes Chef" hands the page to the
   **same** capture → review → commit flow; committing from the extension writes through the
   **same** `importBundle` path, and the recipe appears in the app.
5. A **JS-rendered** page that a plain GET parses to nothing still captures (the headless
   `RenderedDOMFetcher` fallback fires); a page with **no** structured recipe data degrades
   gracefully (best-effort + "couldn't auto-fill, here's the raw text"), never a crash, raw
   HTML still preserved.

Invariants that must hold at merge:

- `swift test --package-path YesChefPackage` green; capture covered by tests over
  **committed, sanitized** HTML-page fixtures (JSON-LD, microdata, no-structured-data,
  JS-rendered-only).
- **Idempotency is tested:** capturing the same fixture URL twice yields the same row counts
  as once (recipes, sections, lines, photos, joins) — reusing M1's assertion.
- House stack honored: the **parser is pure core** (no fetch, no UI); network fetch,
  security-scoped/extension plumbing, and the app-group container live in the app/extension
  targets behind `@Dependency` seams. The extension **calls the same repository path**, it
  does not reimplement import.
- The harvested engine keeps Galavant's clean seams so a future shared-package extraction is
  mechanical (ADR-0007). `originalImportText`/`originalSnapshot` never lossy.

## In scope

- Harvest + recipe-retarget of Galavant's capture engine into YesChefCore (adds **SwiftSoup**).
- `URL` → fetch → `schema.org/Recipe` (JSON-LD primary, OpenGraph/meta, microdata) → `RecipeBundle`.
- Cheap `URLSession` GET first, **headless `RenderedDOMFetcher`** on parse-miss.
- In-app **paste-a-URL** capture with review-before-commit (reuses M1 Slice 3).
- **Share extension** target (page-share path only) over the same core capture path.
- **App-group** shared SQLite container so app + extension see one library.
- Idempotent capture reusing M1's composed identity.
- Sanitized HTML-page fixtures; ADR-0007 recording the harvest + convergence intent.

## Out of scope — with destinations

| Deferred | Goes to | Why not now |
|---|---|---|
| Shared **capture-engine SPM package** both apps consume | **ADR-0007 north star; M-later** | Generalizing Galavant's `ParsedPage` and re-pointing its domain mapping is a cross-repo refactor that risks a working app; harvest with clean seams first |
| **In-app browser** capture surface (`WebExtractorBrowser`/`BrowserScreen`) | **M3** | Jon wants to perfect the browser experience in Galavant first, then harvest it once it's proven there — not block M2 on an unsettled surface |
| **Photo → LLM recipe capture** (snap a printed/handwritten recipe, an LLM structures it) | **M-later milestone** | Explicit product goal (Jon, 2026-06-28). Likely harvests Galavant's `GalavantAI` + `GalavantImaging`; needs its own model-access + review design. Also the **fallback** for any favorite site that resists structured extraction (Slice 5 trigger) |
| Authenticated / paywalled capture (ATK, Milk Street) | **M-later** | User-controlled auth, never store credentials (mirrors M1 out-of-scope) |
| Universal "reader-mode" scraping for sites with no structured data | **M-later research** | This milestone does best-effort + preserve-raw, not a universal scraper |
| Re-capture / "update from source" of an already-captured recipe | **M-later, reviewable** | Matched = skip, edits sacred (same policy as M1) |
| Retrofitting the **Paprika importer** onto the SwiftSoup engine (replacing its `NSRegularExpression` parsing) | **M-later** | Real cleanup the engine enables, but not this milestone's job; flag, don't bundle |
| Widgets / App Intents / Shortcuts capture; clipboard/photo OCR | **Phase D+ parity** | Later capture surfaces |

## Architecture & module layout

```
YesChefPackage/Sources/YesChefCore/
  WebRecipeCapture/            # NEW — harvested engine, recipe-retargeted (pure)
    PageParser, JSONLD/Meta/Microdata extractors, ParseBuilder   # from GalavantCapture
    RecipeSchemaOrg.swift      # schema.org/Recipe vocabulary (replaces place vocab)
    ParsedRecipePage.swift     # recipe-shaped neutral result → projected to RecipeBundle
  RecipeCore.swift             # importBundle + composed identity (REUSED from M1, unchanged)
YesChefPackage/Sources/YesChefWeb/   # NEW target — fetch layer (app-side, WebKit)
    RenderedDOMFetcher.swift   # from GalavantWeb (ADR-0024); injected @Dependency client
YesChefApp/
  RecipeCaptureModel + capture/review view   # paste-URL → fetch → review → commit (reuses M1 Slice 3)
YesChefShareExtension/         # NEW target
  ShareViewController + CaptureExtraction (page-share path only)  # from GalavantShare
App group + shared SQLite container          # app + extension see one library
```

Boundary rule: parsing + identity stay **pure core**; network fetch (WebKit), the app-group
container, and extension plumbing stay in the app/extension targets behind dependency seams.
The extension does **not** reimplement import — it calls the same `RecipeRepository`
capture/`importBundle` path.

## The keystone: capture identity = M1's key (design note)

Web-capture identity reuses M1 Slice 1 verbatim: **normalized(sourceURL) + normalized(title)**.
A web page *is* a URL, so capture is the **strong** (URL-present) path — never the weak
title-only fallback that warns on collision. Re-capturing the same URL is a lookup → reported
already-captured → **skipped by default** (the user may have edited it; "update from source"
is a later reviewable affordance). The fetch is a `@Dependency`-injected client so tests run
against **committed fixtures**, never the live web. Structured-data precedence is Galavant's
proven layering — JSON-LD first (the dominant modern embedding), then OpenGraph/meta, then
microdata (the exact vocabulary the Paprika importer already reads), then preserve-raw +
warn. No fourth heuristic tier this milestone (preserve over guess).

## The slices (each is one PR into `main`)

`main` is protected — every slice is a branch + PR, green at merge (build + tests). Tick the
box in the slice PR that completes it. **Depends on M1 Slices 1 (identity) and 3
(review-before-commit) having landed.**

- [x] Slice 1 — Harvest + recipe-retarget the capture engine (pure core) + ADR-0007
- [x] Slice 2 — Paste-a-URL capture in-app (fetch → review → idempotent commit)
- [x] Slice 3 — App-group shared SQLite container (migration-aware)
- [x] Slice 4 — Share extension target (page-share path)
- [ ] Slice 5 — Real-site hardening + committed sanitized fixtures

*(In-app browser capture is deferred to **M3** — perfect it in Galavant first, then
harvest. See Decisions.)*

### Slice 1 — Harvest + recipe-retarget the engine

Vendor the domain-agnostic engine listed above into `YesChefCore/WebRecipeCapture` (add the
SwiftSoup package) and `YesChefWeb/RenderedDOMFetcher`. Replace `SchemaOrg`'s place vocabulary
with `schema.org/Recipe` properties and `ParsedPage` with a recipe-shaped `ParsedRecipePage`
that projects into M1's `RecipeBundle` (ingredients → lines/sections per M1 Slice 2's section
heuristic; instructions → steps; rating/yield/times → typed fields; raw HTML → `originalImportText`).
**Author ADR-0007** recording: adopting Galavant's engine, the harvest-now/shared-package-later
intent, and how upstream divergence is managed until the package lands. Pure — no fetch, no UI.
**Tests:** over fixture HTML, JSON-LD/microdata/OpenGraph each populate the expected recipe
fields; a barren page yields an empty result the caller can fall back from; raw preserved.
**Done when:** an HTML string → a recipe `RecipeBundle` is covered, the engine knows no I/O,
and ADR-0007 exists.

### Slice 2 — Paste-a-URL capture in-app

A `RecipeCaptureModel` (`@Observable @MainActor`, `Destination`-driven) reusing M1 Slice 3's
review flow: paste/enter URL → fetch (injected client: cheap `URLSession` GET first,
`RenderedDOMFetcher` on parse-miss) → parse → **review** → Commit/Cancel. Commit writes a
`RecipeBundle` through the same `importBundle`, **idempotent** via M1 identity. **Tests:**
fixture pages parse + commit; same URL twice = same row counts (no dup); JS-rendered-only
fixture requires the render fallback; cancel writes nothing. **Done when:** a pasted URL
becomes a reviewed, idempotent recipe with raw HTML preserved.

### Slice 3 — App-group shared SQLite container

Move the SQLite store into an app group (`group.com.jonphillips.yeschef`) so the app and the
(forthcoming) extension share one library. **Migration-aware** — relocate the existing store,
never drop data. **Tests:** the store opens from the group container; a pre-existing store
migrates without loss. **Flag in the PR:** this must be coordinated with the CloudKit
container choice in the sync milestone. **Done when:** one library is reachable from the
group, migration is tested, and the sync-container dependency is surfaced.

### Slice 4 — Share extension target

New `YesChefShareExtension` app-extension target. Harvest the **page-share path** from Galavant's
`CaptureExtraction` — Safari's rendered DOM via an `NSExtensionJavaScriptPreprocessingFile`
(`document.documentElement.outerHTML` + the page URL), falling back to fetching the shared URL —
and **drop the MapKit/vCard location branch entirely**. The recipe appears in the app via the
Slice 3 shared store. **Done when:** sharing a recipe page from Safari lands a reviewed recipe in
the app, idempotently, with raw HTML preserved.

**Reuse the existing core path — do not add a parallel one.** The pure entry points already exist
from Slices 1–2: `WebRecipePageParser.parse(html:sourceURL:capturedAt:)` →
`WebRecipeCaptureDraft` → `RecipeRepository.importCapturedRecipe(_:in:now:uuid:)`. The extension's
job is only to *source* the HTML+URL and present a compact confirm, then call that path. **Prefer
the rendered HTML Safari already handed us; only `WebRecipeCaptureClient.capture(url:)`-fetch when
the share context carries no usable HTML** — never double-fetch a page the preprocessor already
rendered. (The app-side `RenderedDOMFetcher` is not needed here — the preprocessor *is* the render
step; the URL path is the plain-GET fallback.)

**Respect the target boundary.** The extension is a separate target and **cannot import the app
target** — `RecipeCaptureModel`, `RecipeCaptureView`, and `RenderedDOMFetcher` all live in
`YesChefApp` and are unreachable. Give the extension its own thin `@Observable @MainActor` confirm
model (recipe-shaped `CaptureConfirmView` pattern) that calls the **core** path above; **do not
reimplement import** — the parse→draft→commit orchestration is already in core, so anything the
two surfaces would share belongs in core, not copied. The extension bootstraps the *same* shared
store: `prepareDependencies { try $0.bootstrapDatabase() }` against the app group.

**Migration-ordering constraint (this slice breaks a Slice 3 assumption — handle it, don't
inherit a data-loss bug).** Slice 3's `migrateLegacyDatabaseIfNeeded` relocates the pre-M2
app-only store into the group **and guards on "the group store doesn't exist yet"** — and only the
**app** process can see the legacy Application Support container. Adding a second writer breaks the
"app runs first" assumption: if a user shares a page **before** ever opening the M2 build, the
extension creates a fresh group store, and the app's later launch sees the group store already
present, **skips the migration, and strands the user's entire existing library** in the legacy
file. The invariant: **no first-runner ordering may strand or drop the legacy library** — whether
the app or the extension touches the group store first. Simplest safe resolution: the legacy→group
migration stays the **app's exclusive responsibility**, and the extension **refuses to create a
fresh group store** when none exists yet (surface "Open Yes Chef once to finish setup" rather than
forking a divergent store). Pick the mechanism in the PR, but **state it and test it**.

**Target wiring (xcodegen).** New extension target in `project.yml`: the app-group entitlement
(`group.com.jonphillips.yeschef`) on **both** the app and the extension; `YesChefCore` as a target
dependency; the `NSExtension` share point with an activation rule for web pages/URLs; the JS
preprocessing file bundled. Keep `xcodegen generate` and `scripts/check-drift.sh` green.

**Tests:** the HTML-in extraction adapter over a fixture extension context (rendered-HTML-present
and URL-fallback-only); a **parity** assertion that the extension's HTML-in path yields the same
draft + row-count deltas as Slice 2's in-app URL path for the same fixture; the **idempotency**
assertion again (share the same page twice → one recipe); and the **migration-ordering** test
(group store created extension-first, then the app launch still surfaces the full legacy library,
no loss). Plus manual on-device verification of the real share sheet.

### Slice 5 — Real-site hardening + committed fixtures

Run the real recipe sites Jon actually captures from end to end. Commit small, **sanitized**
HTML-page fixtures covering the real shapes: JSON-LD site; microdata site; no-structured-data
fallback; multi-section ingredients; unicode title; and a **JS-rendered-only** page requiring
`RenderedDOMFetcher`. **Charset fidelity (carried from Slice 2):** the live fetch decodes the
response body as hard UTF-8 (`String(decoding:as:UTF8.self)`), which substitutes replacement
characters for any non-UTF-8 page (Latin-1, or charset declared only in the HTTP header) — and
that decoded string is what lands in `originalImportText`, violating the "raw HTML preserved
**whole** / never lossy" invariant. Honor the response's declared encoding (check what
Galavant's harvested fetcher does first — if it already resolves charset, this is a
harvest-fidelity gap to close; if not, note it as a shared upstream issue in the ADR-0007
convergence tracking) and cover it with a non-UTF-8 fixture asserting the raw bytes round-trip
intact. **Tests:** the fixtures exercise Slices 1–4 together (fetch → parse →
review → idempotent commit), idempotency verified across all. **The favorite-sites proof
point** (per Decision #4): Jon's must-have sites must demonstrably capture via structured
data + OpenGraph/meta; **if a must-have site resists structured extraction, that is the
trigger to revisit** the fallback (LLM-assisted parse / photo-OCR capture, a later milestone)
— flag it, don't silently ship a site that can't be sucked in. **Done when:** real sites
capture cleanly and idempotently, the committed fixtures guard every behavior M2 adds, and
any resistant favorite site is surfaced as a revisit trigger.

## Constants register (pre-justified — jon-platform "constants need a rationale")

- **Structured-data precedence = JSON-LD → OpenGraph/meta → HTML microdata → preserve-raw.**
  Harvested from Galavant's `PageParser` layering (proven across its ~38 PRs); JSON-LD is the
  dominant modern embedding, microdata reuses the exact `itemprop` vocabulary the Paprika
  importer already reads (IMPORT_EXPORT §2.4). No fourth heuristic tier (preserve over guess).
- **Fetch strategy = cheap `URLSession` GET (Safari-like User-Agent) first, headless
  `RenderedDOMFetcher` on parse-miss.** Galavant's ADR-0024 pattern; render only when the
  cheap path parses to nothing. Injected as a `@Dependency` — tests never hit the network.
- **Capture identity = normalized(sourceURL) + normalized(title)** — M1's key; web capture is
  the URL-present strong path.
- **App-group identifier = `group.com.jonphillips.yeschef`** — mirrors Jon's owned
  `jonphillips.com` namespace, must match the extension, and must equal the CloudKit container
  coordination noted for the sync milestone.
- **`schema.org/Recipe` property set = `name`, `recipeIngredient`, `recipeInstructions`,
  `recipeYield`, `prepTime`/`cookTime`/`totalTime`, `recipeCategory`, `aggregateRating`,
  `author`, `image`, `description`** — the typed recipe vocabulary replacing Galavant's place
  vocab; derived from `schema.org/Recipe` and IMPORT_EXPORT §2.4, not guessed.

## Decisions (confirmed 2026-06-28)

1. **Convergence — harvest now, but converge, and don't lose the thread.** YesChef *is* the
   second consumer, so the usual "extract once there's a second use" trigger is **already
   met** — the reason to harvest first is narrower: you generalize a shared abstraction best
   from **two working implementations, not one plus a guess** (Galavant's `ParsedPage` is
   place-shaped today and isn't yet neutral enough for recipes). So: harvest in M2, then
   **extract the shared package once M2 ships and the recipe-shaped engine is real** — the
   convergence checkpoint is **M2 close** (or Galavant's next capture-engine change,
   whichever comes first). ADR-0007 owns this as an explicit follow-up with that trigger, and
   a tracking **GitHub issue** keeps it from being forgotten. Not "someday" — a dated next step.
2. **In-app browser → M3.** Split out of M2. Jon hasn't exercised Galavant's browser capture
   enough to be confident in it; **perfect it in Galavant first, then harvest** into YesChef
   as M3. M2 ships share + paste-URL, which is the behavior-shift unlock.
3. **App-group store now — yes.** Move the SQLite store into the app group this milestone
   (Slice 3), migration tested, coordinated with the sync milestone's CloudKit container.
4. **Fallback = OpenGraph/meta + preserve-raw for now — with a proof point and a known
   successor.** No universal scraper this milestone. **But** Jon's must-have sites must prove
   capturable in Slice 5; a site that resists structured extraction is the trigger to revisit.
   The intended successor is **photo → LLM recipe capture** (snap a recipe, an LLM structures
   it) — an explicit product goal, scoped as its own later milestone (see Out of scope), not
   forced into M2.
5. **Real sites for Slice 5 fixtures — confirmed;** Jon to name the handful (captured into the
   slice when authored, as M1 did with `cooksillustrated.com`).
6. **Upstream divergence — confirmed.** Until the shared package lands, ADR-0007 commits to
   periodic reconciliation; keep the harvested files structurally aligned with Galavant's so
   diffs stay reviewable.

## Working agreement

- Each slice: branch → PR → merge (`main` protected; self-merge per the collaboration
  protocol). Commits end with the Co-Authored-By trailer; PR bodies end with the Claude Code
  trailer.
- Tests with swift-testing + CustomDump; control date/uuid/db/**fetch** via `@Dependency`; the
  idempotency test is again the load-bearing assertion.
- Surface every new constant and every harvested file (with its Galavant origin) in the PR
  description — flag, don't bury.
- Blocked or spec looks wrong → write it in the PR, label `question-for-architect`; don't
  silently diverge.
