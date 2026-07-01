# ADR-0009 — In-app authenticated browser capture via WebExtractorKit

Status: Accepted - 2026-06-30

## Context

Jon's named favorite recipe sites are **4/7 paywalled** (NYT Cooking, Cook's Illustrated, ATK,
Milk Street — issue #29). Those sites embed **perfect `schema.org/Recipe` JSON-LD behind a login**;
an unauthenticated GET (the paste-a-URL / share-extension path from M2) sees only a teaser. This is
an **authentication** problem, not an OCR or parsing one — the structured data is already there once
you're logged in. Without reaching it, the app is not genuinely "worth living in before sync,"
because the daily-driver sources are exactly the ones it can't capture.

Galavant already had a `WKWebView`-based browser+capture surface with the house stack. During M3 it
was extracted into a shared jon-platform SPM package, **`WebExtractorKit`**
(`~/code/jon-platform/packages/WebExtractorKit`; jon-platform ADR-0002, PR #15): `WebExtractorBrowser`
(a modal "browse + capture one thing" `WebView` host) plus the headless `RenderedDOMFetcher`,
app-agnostic via an injected `onExtract(html, sourceURL)` plugin seam.

## Decision

Capture recipes from logged-in sites by **browsing to them in an in-app `WebView` that holds Jon's
authenticated WebKit session**, capturing the **rendered, logged-in DOM**, and routing it through the
**same** parse → draft → **review-before-commit** → idempotent `importBundle` pipeline the paste-URL
flow already uses. The browser is a new **fetch seam, not a new write path**.

- **Never store credentials.** The session lives in **WebKit's own persistent data store**
  (`WebPage.browser()`), so "log in once, browse freely, capture as you go" survives relaunch. The
  app has no credential/Keychain code and never reads cookies or tokens.
- **Two surfaces, one seam:** a **modal** capture session (`WebExtractorBrowser`, launched from the
  capture sheet) for "go fetch this one recipe," and a **persistent Browser** top-level section
  (`WebBrowserView` as `AppSection.browser`, a host-owned long-lived `WebPage`) whose home surface
  lists Jon's favorite/paywalled sites one tap away. Both route through the same
  `ingestBrowserCapture(html:sourceURL:)`.
- **Consume `WebExtractorKit`; don't author a browser.** Depend on it **by local path**
  (`../../jon-platform/packages/WebExtractorKit`), matching Galavant's pattern — a sibling
  jon-platform checkout is required. This deletes yes-chef's vendored `RenderedDOMFetcher` and
  realizes the **headless-fetcher convergence** (issue #11 / ADR-0007).
- **Boundary discipline:** `WebExtractorKit` is consumed by the **app target only**, never
  `YesChefShareExtension` (`APPLICATION_EXTENSION_API_ONLY`) and never `YesChefCore` (which stays
  headless-WebKit-free and host-testable). All recipe/domain logic stays **on our side of
  `onExtract`**; the pure parse/draft logic lives in core, the `WebExtractionOutcome` mapping in the
  app.

## Consequences

- Yes Chef reaches the paywalled majority without an LLM/photo fallback and without a server — the
  right tool for an authentication problem.
- **Cross-repo coupling:** builds require a sibling `~/code/jon-platform` checkout with the package
  on disk. Staying on a local-path dependency (not a pinned git URL) is deliberate; converging to a
  git ref is a later, coordinated cross-repo decision. jon-platform PR #15 (the package lift) is the
  tracking point.
- A genuinely reusable **browser** improvement is a jon-platform PR; recipe-specific extraction
  stays in yes-chef. A session-persistence regression (e.g. an ephemeral store) is a package fix,
  **not** a yes-chef workaround.
- Consistent with the **one-way sync gate** (ADR-0002): all trustworthy capture precedes sync, so
  elevating this above the sync milestone reinforced the gate rather than contradicting it.
- Two **content** gaps surfaced during M3 device use (hero image bytes, editorial-prose blocks) were
  handled as follow-on efforts, not part of this ADR; the capture *mechanism* is what this records.

Build order and slice detail: [`../milestones/M3-authenticated-browser-capture.md`](../milestones/M3-authenticated-browser-capture.md).
