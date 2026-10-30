# Comment ingestion — parked notes

**Status:** Parked 2026-10-30, moved from `open-questions.md` as written (jon-platform ADR-0005 D14).
**Summary:** Pull top-ranked reader comments into a recipe as tips, NYT first. The capture DOM doesn't carry them, and comments are third-party content with PII constraints.

Restore the part you schedule to a brief in `docs/efforts/`, in the plan PR that schedules it.

## Comment ingestion — top-ranked tips as recipe enrichment

Feature interest noted 2026-06-30 (Jon), surfaced while sanitizing the ATK capture-DOM
fixture. The want: pull a source's comments, sort by **Most Liked (ATK) / Most Helpful
(NYT)**, and surface the top few for their *valuable advice* (e.g. "they spread too much —
cut the sugar", "came out flat") — not the whole thread.

- **The capture-DOM does not give us this — confirmed from the real artifact.** ATK
  server-renders only the **first ~4 comments** into the page, in default **Newest** order;
  the other ~1488 lazy-load via a JS/API call. So a static page capture yields neither the
  volume nor the *ranking* the feature needs. "Most liked" is a different query than what
  the DOM hands us.
- **Two separable axes — don't conflate them:**
  1. *How to obtain ranked comments.* Either **(a) user-driven in the in-app browser** —
     tap "Most Liked," let it load, then a capture scrapes the rendered comment DOM (manual
     sort + automated extract; brittle against hashed CSS-module classes like
     `comments_commentText__3vCsW`), or **(b) per-site comments API** with a sort param
     (reliable ranking, but per-site integration, possible auth/ToS gating, and *not*
     generalizable the way `schema.org` JSON-LD is). Extraction itself is automatable —
     same shape as the editorial-prose scrape.
  2. *How to judge "valuable."* **Jon-reviews** (a review/share-sheet pass over the top N)
     vs **LLM triage** that distills the top comments into a recipe note. Connects to the
     already-noted photo→LLM fallback and the existing review-before-commit flow.
- **Which surface can even do the sort+load (clarified 2026-06-30).** Three capture
  surfaces, and only one can run the interactive "sort → Most Helpful → tap Load More ×N →
  scrape" flow:
  1. *In-app `WebPage` browser* (`YesChefApp/RecipeModels.swift:288` `WebPage.browser()`,
     `BrowserViews.swift`) — the app owns this WebKit view and can inject JS to drive controls,
     await lazy-loads, and read the resulting DOM. **This is the only surface where automated
     ranked-comment loading can ship.** It is option (a) below, done properly.
  2. *iPad share extension* (`YesChefShareExtension`) — passive. `SharePreprocessor.js` runs
     **once** in the host Safari page and returns `{url, document.documentElement.outerHTML}`;
     `ShareViewController` imports no WebKit and cannot click/sort/scroll. The **only** way
     loaded comments reach it is if Jon manually sorts + taps Load-More *in Safari first*, then
     shares the expanded DOM. Weaker, human-in-the-loop variant of (a).
  3. *Claude-in-Chrome MCP (Jon's Mac)* — desktop prototyping only; does not ship. Useful to
     drive a real NYT page and **harvest a "Most Helpful, fully loaded" DOM fixture** — exactly
     the artifact this question says we lack.
- **NYT is the strong first target (clarified 2026-06-30, Jon).** Capture is always
  **authenticated** — Jon captures as a logged-in subscriber, never a logged-out scrape (the
  logged-out-still-exposes-data quirk is trivia, not a strategy). That makes option (a)
  user-driven the natural fit for NYT: in the in-app authenticated browser he can tap "Most
  Helpful," let the full thread load, and scrape the ranked comment DOM — the ranking and
  volume the feature needs are available *because* he's signed in. So the auth-gating worry in
  axis 1 largely dissolves for the sites Jon actually uses; the ToS/PII storage concern below
  still stands.
- **Constraints:** comments are third-party user content — PII (display names/initials),
  plus copyright/ToS questions for *storing and re-displaying* them, and a sanitization
  step on ingest (the ATK capture already pulled in 4 commenters' names and Jon's own `JP`
  avatar). Post-M3 enrichment idea; not in the current milestone arc.
