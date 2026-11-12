# ADR-0070 — What you teach the app reaches everyone; your household stays yours

> **One-line:** Yes Chef holds two kinds of data. **Household state** (pantry, grocery lists, menus, your recipes)
> stays in each person's own iCloud, never shared. **Kitchen knowledge** (which names are one ingredient, which
> store area something is in, which trip it goes on) is promoted on a schedule into a data file that ships with the
> app, so every user gets what any user taught it. Each person's own corrections still win on their devices.

Status: **Accepted** — 2026-11-12 (Jon). Effort: [`efforts/archive/kitchen-knowledge-promotion.md`](../efforts/archive/kitchen-knowledge-promotion.md).
Origin: Jon, 2026-11-12, as Wendy starts using the app: *"1) We would not share household state. We each control
our own lives in that way 2) Wendy at some point could view my recipe list and copy a recipe to hers (this is
bigger, I know; we don't need to scope now.) 3) The work I patiently do to improve pantry/grocery list item
categorization, etc would either flow to her as data or get incorporated in the code on a regular basis so all users
benefit. Otherwise Wendy ... and maybe my boys ... just think my app sucks."*
Builds on: [ADR-0003](ADR-0003-private-libraries-recipe-transfer.md) (private libraries; reaffirmed) ·
[ADR-0052](ADR-0052-grocery-learned-area-table.md) (learned store areas; its D4 "promote to seed" becomes the
regular path) · [ADR-0068](ADR-0068-two-trip-grocery-split.md) D3 (trip switches) ·
[ADR-0069](ADR-0069-ingredient-name-fixes.md) (name fixes) · [ADR-0060](ADR-0060-chat-access-over-mcp.md) (the
iCloud Drive folder from phone to Mac).

## Context

ADR-0003 gives each person their own library in their own private iCloud database. Nothing syncs between people.
That's right for most of the app, and Jon has confirmed it: what's in your pantry and on your list is yours.

But the grocery work has been moving into that private data. ADR-0052 put store-area corrections in a table,
ADR-0068 put trip switches in a table, and ADR-0069 puts name fixes in a table. Each was the right call for the
person teaching, because a tap fixes it at once with no build. Each also means the teaching stops at that person's
iCloud. Before these tables, a fix was a code change, and code reaches everyone. So the more Jon teaches the app by
tapping, the further Wendy's copy falls behind his, and she sees an app that merges "parsley" and "flat-leaf
parsley" for him and not for her.

| Kind | Examples | Today | This ADR |
|---|---|---|---|
| Household state | pantry items and their settings, grocery lists, menus, calendar, recipes, chats | private (ADR-0003) | stays private |
| Kitchen knowledge, built in | `seedAreas`, built-in aliases, trip keeper list, default pantry staples, parser rules | in code; reaches everyone | moves to a data file (rules stay in code) |
| Kitchen knowledge, taught | your store-area corrections, confirmed model placements, trip switches, name fixes | private tables | promoted into the data file on a schedule |

## Decisions

### D1 — Household state is never shared

Pantry, lists, menus, the calendar, prep plans, recipes and chats stay in each person's private database. No shared
zone, no household schema. This reaffirms ADR-0003.

### D2 — Seeing someone's recipes and copying one is ADR-0003 Phase 2, and stays unscoped

Wendy browsing Jon's recipes and copying one into her library is ADR-0003's Phase 2 (Family Cookbook): read and copy,
never co-edit. Recorded here because it's part of the same vision. Not scoped, not scheduled.

### D3 — Built-in kitchen knowledge lives in one data file that ships with the app

`seedAreas`, the built-in aliases, the trip keeper list and the default pantry staples move out of Swift into one
bundled JSON resource in `YesChefCore`. Behavior doesn't change; tests prove each lookup gives the same answer
before and after. Rules stay in code: normalizing, stripping prep words, singularizing, the head-noun area fallback.

A data file means promotion (D5) is a data diff, not a Swift edit, so it's easy to produce, read and review.

### D4 — On every device, your own rows beat the built-in file, and the file beats the model

The precedence ADR-0052 set holds for every kind of knowledge: **your rows > built-in file > model guess**. So after
Jon's fixes are promoted, Wendy gets them, and if she disagrees (her store keeps shallots elsewhere), her correction
wins on her devices without touching anyone else's.

### D5 — Promotion: export what you've taught, merge it into the file, ship it

- **Export.** Settings › Developer gets **Export What I've Taught**. It writes the promotable rows (D6) as JSON into
  the app's iCloud container (`Documents/Knowledge/`, next to Backups), which reaches the Mac the way ADR-0060's
  folder does, and offers the same file in a share sheet. Anyone can run it. Wendy's iCloud isn't Jon's, so she sends
  hers through the share sheet.
- **Merge.** A repo script reads the export, merges it into the data file, and prints what changed and any conflicts
  with existing built-in entries. The diff goes in a normal PR, and the architect reviews it like any other.
- **Cadence.** Promotion runs before each TestFlight build, so the knowledge never trails a release by more than one
  build. The TestFlight script warns when an export is newer than the file's last merge.
- **Cleanup.** When a build's file now covers one of your rows with the same answer, a data pass deletes your
  redundant row (rule against dead data, [[no-dead-data]]). A row that disagrees with the file stays: it's still
  your override.

The base key ADR-0069 caches includes the built-in aliases, so a file change raises the data-pass version and the
#499 canonical-key refresh runs again, as it did for #499.

### D6 — What gets promoted

| Source | Promoted | Why |
|---|---|---|
| Name fixes (ADR-0069) | all | every row is a person saying two names are one |
| Store-area rows, `user` | all | corrections |
| Store-area rows, `model` | only confirmed (`reviewedAt` set) | an unreviewed guess would be the model's work dressed as a person's; other devices can guess for themselves |
| Trip switches (ADR-0068) | all | your call on what keeps; anyone can switch it back |
| Pantry items and settings | never | household state (D1) |

### D7 — Not a live shared feed, for now

The other way to share knowledge is a live one: publish rows to the app's CloudKit **public** database, and every
device reads them with no build in between. Rejected for now. SQLiteData syncs only private databases, so it's
custom CloudKit code. Public writes need permission roles so only an editor can publish. And it skips the review
step. A build-time file costs a lag of one TestFlight build, which is fine for knowledge that changes weekly at
most. Revisit if that lag starts to show.

## What this costs

- A one-time move of four Swift lists into a data file, with tests that prove nothing changed.
- An export action, a merge script and a TestFlight warning.
- A promotion step before each TestFlight build. It's a habit, and the warning keeps it from being forgotten.
- Knowledge reaches others one build late, never instantly.

## Order

ADR-0069 shipped first (#502), since name fixes are the knowledge that piles up fastest. This ADR is one dispatch:
moving the built-in lists into the data file with no behavior change, then export, merge, cleanup and the TestFlight
warning.

## Open questions

- **OQ1 — store-specific areas.** If Wendy shops at a different store, promoted areas could be wrong for her; her
  corrections win (D4), but she has to make them. Per-store layouts are a separate decision; wait for a real case.
- **OQ2 — the boys.** Same model as Wendy. Nothing to decide until they use it.
