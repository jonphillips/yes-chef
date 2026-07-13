# Effort — Truncate menu note-item body in the list view

**Type:** dogfood fix (trivial). Origin: Jon's 2026-07-12 dogfood pass ("Notes on the menu need to be
truncated at 5 lines on the list view. I have one that is taking up most of the screen").

**Free rider:** small enough to bundle into any adjacent menu/list dispatch; does not need its own PR.

## Problem

A menu dish-row renders a note-item's full body with **no line limit**, so a long note dominates the
menu detail list. The offender is the `displayNotes` text in the menu dish row:

`YesChefApp/MenuDetailSections.swift` (`MenuDishRowView.rowContent`, ~line 272):

```swift
if let notes = row.displayNotes {
    Text(notes)
        .font(.subheadline)
        .foregroundStyle(.secondary)
}
```

The parallel meal-calendar row already caps at `.lineLimit(2)`, so this is an inconsistency in the menu
reader, not a new pattern.

## Fix

Add `.lineLimit(5)` to that `Text(notes)`.

**Decision to confirm:** with `.lineLimit(5)` the row silently truncates with no "…more" affordance.
That's acceptable here — tapping the row opens the editor with the full text — but it's intentional, not
an oversight. (If Jon wants an expand affordance instead, that's a larger change; default is the plain
cap.)

## Verify

Package has no logic change; app build + Jon's device pass. Confirm a long menu note now caps at 5 lines
and the full text is still reachable by opening the item.
