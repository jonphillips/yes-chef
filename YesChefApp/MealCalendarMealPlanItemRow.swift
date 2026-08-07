import SwiftUI
import YesChefCore

// Split out of MealCalendarViews.swift to keep that file under the SwiftLint file-length budget.

struct MealPlanItemRowView: View {
  let row: MealPlanItemRowData
  let editAction: (() -> Void)?
  let deleteAction: (() -> Void)?
  let sourceAction: (() -> Void)?
  let primaryAction: (() -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      rowContent

      Spacer()

      if editAction != nil || deleteAction != nil {
        Menu {
          if let editAction {
            Button(action: editAction) {
              Label("Edit", systemImage: "pencil")
            }
          }
          if let deleteAction {
            Button(role: .destructive, action: deleteAction) {
              Label("Remove", systemImage: "trash")
            }
          }
        } label: {
          Label("Meal Actions", systemImage: "ellipsis.circle")
            .labelStyle(.iconOnly)
        }
      }
    }
    .padding(12)
  }

  @ViewBuilder private var rowContent: some View {
    if let primaryAction {
      Button(action: primaryAction) {
        rowContentLabel
      }
      .buttonStyle(.plain)
    } else {
      rowContentLabel
    }
  }

  private var rowContentLabel: some View {
    HStack(alignment: .top, spacing: 12) {
      MealPlanItemImage(row: row)
        .frame(width: 56, height: 56)

      VStack(alignment: .leading, spacing: 6) {
        Text(row.displayTitle)
          .font(.headline)
        Label(row.item.kind.title, systemImage: row.item.kind.systemImage)
          .font(.caption)
          .foregroundStyle(.secondary)
        if row.isFromMenu {
          menuSourceLabel
        }
        if let notes = row.displayNotes {
          Text(notes)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder private var menuSourceLabel: some View {
    if let sourceAction {
      Button(action: sourceAction) {
        Label(row.menu?.title ?? "Menu", systemImage: "menucard")
          .lineLimit(1)
      }
      .buttonStyle(.plain)
      .font(.caption)
      .foregroundStyle(.tint)
    } else {
      Label(row.menu?.title ?? "Menu", systemImage: "menucard")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }
}
