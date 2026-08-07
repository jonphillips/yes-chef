import SwiftUI
import YesChefCore

struct MealCalendarDayHeader: View {
  let model: MealCalendarModel
  var cookSession: (() -> Void)?
  var chat: (() -> Void)?
  var handoffSource: HandoffExportSource?
  var complementHandoffSource: HandoffExportSource?
  let handoffTransport: HandoffInAppTransport

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline) {
        titleBlock
        Spacer()
        cookButton
        chatButton
        dayActionsMenu
        addMenu
      }
      VStack(alignment: .leading, spacing: 12) {
        titleBlock
        if cookSession != nil {
          cookButton
            .frame(maxWidth: .infinity)
        }
        HStack {
          chatButton
          dayActionsMenu
          addMenu
          Spacer()
        }
      }
    }
  }

  private var titleBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(model.selectedDateTitle)
        .font(.largeTitle.bold())
      Text(itemCountTitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var cookButton: some View {
    if let cookSession {
      Button(action: cookSession) {
        Label("Cook these", systemImage: "flame")
      }
      .buttonStyle(.borderedProminent)
    }
  }

  @ViewBuilder
  private var chatButton: some View {
    if let chat {
      Button(action: chat) {
        Label("Ask", systemImage: "sparkles")
      }
      .buttonStyle(.bordered)
    }
  }

  /// Per-day overflow menu. Hosts the grocery add (item 2) alongside the hand-off actions so a cook
  /// can send a whole day to their list without switching to the Grocery tab. Shows whenever either
  /// affordance is available.
  @ViewBuilder
  private var dayActionsMenu: some View {
    if model.canAddSelectedDayToGroceries || (handoffSource != nil && complementHandoffSource != nil) {
      Menu {
        if model.canAddSelectedDayToGroceries {
          Button {
            model.addSelectedDayToGroceriesButtonTapped()
          } label: {
            Label("Add Day to Groceries", systemImage: "cart.badge.plus")
          }
        }

        if let handoffSource, let complementHandoffSource {
          Section {
            HandoffMenuActions(
              handoffSource: handoffSource,
              complementHandoffSource: complementHandoffSource,
              transport: handoffTransport,
              prepLabel: "Handoff Make-ahead",
              pastePrepLabel: "Paste Make-ahead",
              complementLabel: "Handoff Complement",
              pasteComplementLabel: "Paste Complement"
            )
          }
        }
      } label: {
        Label("Day actions", systemImage: "ellipsis.circle")
          .labelStyle(.iconOnly)
      }
      .accessibilityLabel("Day actions")
    }
  }

  private var addMenu: some View {
    Menu {
      Button {
        model.addItemButtonTapped(kind: .recipe)
      } label: {
        Label("Recipe", systemImage: MealPlanItemKind.recipe.systemImage)
      }
      Button {
        model.addItemButtonTapped(kind: .note)
      } label: {
        Label("Add Note", systemImage: MealPlanItemKind.note.systemImage)
      }
    } label: {
      Label("Add", systemImage: "plus")
    }
    .buttonStyle(.borderedProminent)
  }

  private var itemCountTitle: String {
    switch model.selectedDayRows.count {
    case 0: "No items scheduled"
    case 1: "1 item scheduled"
    default: "\(model.selectedDayRows.count) items scheduled"
    }
  }
}
