# Current Handoff

Last updated: June 19, 2026.

Use this as the short entry point when starting a fresh Yes Chef conversation.
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Current Checkpoint

The current slice is saved recipe-list views/presets.

Implemented behavior:

- A `Saved Views` toolbar menu on the recipe list.
- Save the current browse state with a user-provided name.
- Apply a saved view from the menu.
- Manage saved views in a sheet and delete with row swipe actions.
- Show the active saved view with a filled bookmark when the current list state
  exactly matches a saved preset.
- Saved views are local app preferences backed by `@AppStorage`, not database rows
  or iCloud-synced records.

Saved views capture:

- Search text
- Sort order
- Library scope
- Favorites-only and photos-only filters
- Selected categories and tags
- Selected cuisine and course
- Selected sources and authors

Saved views intentionally do not capture:

- Row density
- Source/category metadata visibility in rows

Those remain per-device display preferences through the existing list view-options
menu.

## Verification Pattern

Before checkpointing UI work:

- Run `xcodegen generate` after adding Swift source files.
- Build `YesChef` for `iPad Air 13-inch (M4)`.
- Run `scripts/check-drift.sh`.
- Install and launch on both active iOS 27 simulators:
  - `iPad Air 13-inch (M4)`
  - `iPhone 17 Pro`

Jon performs the primary UI testing pass.

## Recommended Next Larger Task

Start the meal calendar vertical slice.

Suggested first scope:

- Add the durable data model for scheduled meals.
- Show a simple Meal Calendar surface from the existing app shell.
- Let the user place one or more recipes on a date.
- Display recipe title, meal/date, and serving notes if needed.
- Keep shopping lists, menus, event planning, generated prep strategy, and iCloud
  sync for later slices.

Reasoning:

- The recipe library is now useful enough to browse, filter, and save repeated views.
- Meal calendar work connects directly to the existing product thesis.
- It will also give `lastCookedAt` a principled source of truth: a recipe scheduled
  on a past calendar date can later drive or supplement that field instead of using
  a manual "mark cooked" flow.
