import Observation
import SwiftUI
import YesChefCore

@Observable
@MainActor
final class CookSessionModel {
  let title: String
  let items: [CookSessionItem]

  var selectedItemID: CookSessionItem.ID?
  private var completedItemIDs: Set<CookSessionItem.ID> = []

  init(presentation: CookSessionPresentation) {
    title = presentation.title
    items = presentation.items
    selectedItemID = presentation.items.first?.id
  }

  var activeItems: [CookSessionItem] {
    items.filter { !completedItemIDs.contains($0.id) }
  }

  var completedItems: [CookSessionItem] {
    items.filter { completedItemIDs.contains($0.id) }
  }

  var selectedItem: CookSessionItem? {
    guard let selectedItemID else { return nil }
    return items.first { $0.id == selectedItemID }
  }

  var selectedItemIsCompleted: Bool {
    guard let selectedItemID else { return false }
    return completedItemIDs.contains(selectedItemID)
  }

  func selectItem(_ item: CookSessionItem) {
    selectedItemID = item.id
  }

  func selectedCompletionButtonTapped() {
    guard let selectedItem else { return }
    if completedItemIDs.contains(selectedItem.id) {
      restoreItem(selectedItem)
    } else {
      completeItem(selectedItem)
    }
  }

  func restoreItem(_ item: CookSessionItem) {
    completedItemIDs.remove(item.id)
    selectedItemID = item.id
  }

  private func completeItem(_ item: CookSessionItem) {
    completedItemIDs.insert(item.id)
    guard selectedItemID == item.id else { return }
    selectedItemID = nextActiveItem(after: item)?.id ?? item.id
  }

  private func nextActiveItem(after item: CookSessionItem) -> CookSessionItem? {
    guard let completedIndex = items.firstIndex(of: item) else {
      return activeItems.first
    }

    let trailingItems = items.suffix(from: items.index(after: completedIndex))
    if let nextItem = trailingItems.first(where: { !completedItemIDs.contains($0.id) }) {
      return nextItem
    }

    let leadingItems = items.prefix(upTo: completedIndex)
    return leadingItems.first { !completedItemIDs.contains($0.id) }
  }
}

struct CookSessionView: View {
  @State private var model: CookSessionModel
  let recipeModel: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel

  init(
    presentation: CookSessionPresentation,
    recipeModel: RecipeLibraryModel,
    mealCalendarModel: MealCalendarModel,
    groceryModel: GroceryLibraryModel
  ) {
    _model = State(wrappedValue: CookSessionModel(presentation: presentation))
    self.recipeModel = recipeModel
    self.mealCalendarModel = mealCalendarModel
    self.groceryModel = groceryModel
  }

  var body: some View {
    VStack(spacing: 0) {
      CookSessionSwitcher(model: model)

      Divider()

      TabView(selection: $model.selectedItemID) {
        ForEach(model.items) { item in
          RecipeDetailView(
            recipeID: item.recipeID,
            scaleContext: item.scaleContext,
            libraryModel: recipeModel,
            mealCalendarModel: mealCalendarModel,
            groceryModel: groceryModel,
            showsStartCookingButton: false
          )
          .tag(Optional(item.id))
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
    }
    .navigationTitle(model.title)
    .navigationBarTitleDisplayMode(.inline)
    .keepsScreenAwakeWhilePresented()
  }
}

private struct CookSessionSwitcher: View {
  let model: CookSessionModel

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(model.activeItems) { item in
          CookSessionChip(
            item: item,
            isSelected: model.selectedItemID == item.id,
            isCompleted: false
          ) {
            model.selectItem(item)
          }
        }

        if !model.completedItems.isEmpty {
          Menu {
            ForEach(model.completedItems) { item in
              Button {
                model.restoreItem(item)
              } label: {
                Label(item.title, systemImage: "arrow.uturn.backward.circle")
              }
            }
          } label: {
            Label("Done \(model.completedItems.count)", systemImage: "checkmark.circle")
              .font(.subheadline.weight(.semibold))
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(.tertiary, in: Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Completed recipes")
        }

        if let selectedItem = model.selectedItem {
          Button {
            model.selectedCompletionButtonTapped()
          } label: {
            Label(
              model.selectedItemIsCompleted ? "Undo Done" : "Mark Done",
              systemImage: model.selectedItemIsCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle"
            )
          }
          .buttonStyle(.bordered)
          .accessibilityLabel(
            model.selectedItemIsCompleted
              ? "Mark \(selectedItem.title) not done"
              : "Mark \(selectedItem.title) done"
          )
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 10)
    }
    .scrollIndicators(.hidden)
    .background(.background)
  }
}

private struct CookSessionChip: View {
  let item: CookSessionItem
  let isSelected: Bool
  let isCompleted: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label {
        Text(item.title)
          .lineLimit(1)
      } icon: {
        Image(systemName: isCompleted ? "checkmark.circle.fill" : "fork.knife")
      }
      .font(.subheadline.weight(.semibold))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .foregroundStyle(isSelected ? Color.white : Color.primary)
      .background(
        isSelected
          ? Color.accentColor
          : Color(uiColor: .secondarySystemGroupedBackground),
        in: Capsule()
      )
      .overlay {
        Capsule()
          .stroke(isSelected ? Color.accentColor : Color(uiColor: .separator), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
