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
        handoffControls
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
          handoffControls
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

  @ViewBuilder
  private var handoffControls: some View {
    if let handoffSource, let complementHandoffSource {
      Menu {
        HandoffMenuActions(
          handoffSource: handoffSource,
          complementHandoffSource: complementHandoffSource,
          transport: handoffTransport,
          prepLabel: "Handoff Make-ahead",
          pastePrepLabel: "Paste Make-ahead",
          complementLabel: "Handoff Complement",
          pasteComplementLabel: "Paste Complement"
        )
      } label: {
        Label("Day handoff actions", systemImage: "ellipsis.circle")
          .labelStyle(.iconOnly)
      }
      .accessibilityLabel("Day handoff actions")
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
