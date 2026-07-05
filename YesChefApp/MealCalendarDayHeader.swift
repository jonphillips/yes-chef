import SwiftUI
import YesChefCore

struct MealCalendarDayHeader: View {
  let model: MealCalendarModel
  var cookSession: (() -> Void)?
  var chat: () -> Void

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline) {
        titleBlock
          .fixedSize(horizontal: true, vertical: false)
        Spacer()
        actionButtons
          .fixedSize(horizontal: true, vertical: false)
      }
      VStack(alignment: .leading, spacing: 12) {
        titleBlock
        actionButtons
      }
    }
  }

  private var titleBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(model.selectedDateTitle)
        .font(.largeTitle.bold())
        .fixedSize(horizontal: false, vertical: true)
      Text(itemCountTitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var actionButtons: some View {
    HStack {
      cookButton
      chatButton
      addMenu
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

  private var chatButton: some View {
    Button {
      chat()
    } label: {
      Label("Chat", systemImage: "sparkles")
    }
    .buttonStyle(.bordered)
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
