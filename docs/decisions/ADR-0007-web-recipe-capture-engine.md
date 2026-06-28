# ADR-0007 - Web recipe capture engine harvest and convergence

Status: Accepted - 2026-06-28

## Context

Yes Chef needs web recipe capture before CloudKit sync turns on. The capture path creates
recipes, so bad duplicate detection or lossy parsing would pollute the future synced
library the same way a bad import would.

Galavant already has a mature capture engine with the same house stack and clean seams:
HTML parsing is pure, value extraction is layered, and rendered-DOM/network work lives
outside the parser. Its current domain mapping is place-shaped, not recipe-shaped, so
extracting a shared package before Yes Chef has a working recipe implementation would
force a speculative abstraction.

## Decision

Yes Chef will harvest Galavant's domain-agnostic parser shape into `YesChefCore` now and
retarget it to `schema.org/Recipe`.

- The parser remains pure core: HTML string plus optional source URL in,
  `ParsedRecipePage` out. It performs no fetch, WebKit work, database writes, or UI.
- Extraction keeps Galavant's layering and value-vote seam: JSON-LD first,
  OpenGraph/meta fallback, then HTML microdata.
- The recipe vocabulary is app-specific: title, description, author/publisher, image,
  `recipeIngredient`, `recipeInstructions`, `recipeYield`, time fields, categories, and
  aggregate rating.
- Projection into storage uses the existing `RecipeBundleCoding.RecipeBundle` interchange
  shape so `originalImportText` and `originalSnapshot` stay complete.
- Network fetch, rendered DOM fallback, app-group storage, and share-extension plumbing
  remain later M2 slices behind dependency seams.

## Convergence Plan

This harvest is temporary by design. When M2 closes, or when Galavant next changes its
capture engine materially, extract the common parsing pieces into a shared package used by
both apps. Until then, keep the Yes Chef files structurally aligned with Galavant's
`GalavantCapture` names and responsibilities so reconciliation is a reviewable diff rather
than a rewrite.

Tracking issue: [#11](https://github.com/jonphillips/yes-chef/issues/11).

The shared package should own the generic HTML/JSON-LD/meta/microdata mechanics, URL/image
hygiene, body-text cleanup, and value voting. App targets should own domain vocabulary and
projection into their own models.

## Consequences

- Yes Chef can ship recipe capture without destabilizing Galavant.
- A second real consumer will inform the eventual shared package API.
- The repos may diverge temporarily; slice PRs must call out harvested files and any
  intentional differences from Galavant.
- No in-app browser, rendered fetcher, or share extension is implied by this ADR alone;
  those remain separate M2 slices.
