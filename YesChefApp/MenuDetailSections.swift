import LLMHandoffUI
import SwiftUI
import UniformTypeIdentifiers
import YesChefCore

struct MenuRecipeBrowserPanel: View {
  let recipeModel: RecipeLibraryModel
  var isTinted = false
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?

  var body: some View {
    @Bindable var recipeModel = recipeModel

    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Recipes")
            .font(.headline)

          Spacer()

          Button {
            recipeModel.filterButtonTapped()
          } label: {
            Label(
              "Filter Recipes",
              systemImage: recipeModel.hasActiveFilters
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle"
            )
            .labelStyle(.iconOnly)
          }
          .accessibilityLabel("Filter Recipes")
        }

        TextField("Search recipes", text: $recipeModel.searchText)
          .textFieldStyle(.roundedBorder)
          .textInputAutocapitalization(.never)
      }
      .padding()

      RecipeListStatusBar(model: recipeModel)

      // Search-driven empty state as an `.overlay`, never a branch inside the List: typing a query
      // that matches nothing swaps the List's single child in one update, which raises an
      // invalid-batch-update exception.
      List {
        ForEach(recipeModel.visibleRecipeRows) { row in
          Button {
            onRecipeSelected?(RecipeDetailPresentation(recipeID: row.recipe.id))
          } label: {
            RecipeListRow(
              row: row,
              options: RecipeListViewOptions(
                density: .compact,
                showsSourceMetadata: true,
                showsCategoryMetadata: true
              )
            )
          }
          .buttonStyle(.plain)
          .listRowBackground(Color.clear)
          .draggable(MenuDraggedRecipe(recipeID: row.recipe.id))
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(isTinted ? .hidden : .automatic)
      .overlay {
        if recipeModel.visibleRecipeRows.isEmpty {
          ContentUnavailableView.search(text: recipeModel.searchText)
        }
      }
    }
    .background(isTinted ? Color(uiColor: .secondarySystemBackground) : Color(uiColor: .systemBackground))
  }
}

struct MenuDishList: View {
  let model: MenuLibraryModel
  let detailModel: MenuDetailModel
  let menu: CoreMenu
  let detail: MenuDetailData
  let handoffTransport: HandoffInAppTransport
  var isInitiallyExpanded = true
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  @State private var dayExpansionOverrides: [Int: Bool] = [:]
  @State private var dayFrames: [Int: CGRect] = [:]
  @State private var hoveredDay: Int?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          dishHeader
        }

        VStack(alignment: .leading, spacing: 10) {
          dishHeader
        }
      }

      ForEach(0..<detail.menu.dayCount, id: \.self) { dayOffset in
        let isExpanded = dayExpansionOverrides[dayOffset] ?? isInitiallyExpanded
        MenuDaySection(
          model: model,
          detailModel: detailModel,
          menu: menu,
          dayNumber: dayOffset + 1,
          dayOffset: dayOffset,
          scheduledDate: scheduledDate(for: dayOffset),
          rows: detail.itemRows.filter { $0.item.dayOffset == dayOffset },
          handoffTransport: handoffTransport,
          isExpanded: isExpanded,
          onToggle: {
            dayExpansionOverrides[dayOffset] = !isExpanded
          },
          onRecipeSelected: onRecipeSelected
        )
        .background {
          if hoveredDay == dayOffset {
            RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.1)).padding(-8)
          }
        }
        .overlay {
          if hoveredDay == dayOffset {
            RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 1).padding(-8)
          }
        }
        .background {
          GeometryReader { proxy in
            Color.clear.preference(key: MenuDayFramesKey.self, value: [dayOffset: proxy.frame(in: .named("menuDays"))])
          }
        }
      }
    }
    .coordinateSpace(name: "menuDays")
    .onPreferenceChange(MenuDayFramesKey.self) { dayFrames = $0 }
    .reorderContainer(for: MenuItemRowData.self, in: Int.self) { difference in
      let destination: MenuItemReorderDestination = switch difference.destination.position {
      case let .before(itemID):
        .before(itemID)
      case .end:
        .end
      }
      _ = model.reorderMenuItems(
        itemIDs: difference.sources,
        destinationDayOffset: difference.destination.collectionID,
        destination: destination
      )
    }
    .onDropSessionUpdated { session in
      switch session.phase {
      case .exiting, .ended, .dataTransferCompleted:
        hoveredDay = nil
      case .entering, .active:
        hoveredDay = dayFrames.first(where: { $0.value.contains(session.location) })?.key
          ?? session.reorderDestination(for: MenuItemRowData.self, in: Int.self)?.collectionID
          ?? hoveredDay
      @unknown default:
        hoveredDay = nil
      }
    }
    .dropDestination(for: MenuDraggedRecipe.self) { recipes, session -> Void in
      guard !recipes.isEmpty else { return }
      let reorderDestination = session.reorderDestination(for: MenuItemRowData.self, in: Int.self)
      guard let destinationDayOffset = dayFrames.first(where: { $0.value.contains(session.location) })?.key
        ?? reorderDestination?.collectionID ?? hoveredDay else { return }
      hoveredDay = nil
      let position = reorderDestination?.collectionID == destinationDayOffset ? reorderDestination?.position : nil
      let destination: MenuItemReorderDestination = switch position {
      case let .before(itemID):
        .before(itemID)
      case .end, nil:
        .end
      }
      if model.addRecipesToMenu(
        recipeIDs: recipes.map(\.recipeID),
        menuID: menu.id,
        destinationDayOffset: destinationDayOffset,
        destination: destination
      ) {
        dayExpansionOverrides[destinationDayOffset] = true
      }
    }
  }

  private var dishHeader: some View {
    Text("Dishes")
      .font(.title2.weight(.semibold))
  }

  private var placedStartDate: Date? {
    detail.placements.count == 1 ? detail.placements[0].startDate : nil
  }

  private func scheduledDate(for dayOffset: Int) -> Date? {
    guard let placedStartDate else { return nil }
    return Calendar.autoupdatingCurrent.date(
      byAdding: .day,
      value: dayOffset,
      to: placedStartDate
    )
  }
}

private struct MenuDaySection: View {
  let model: MenuLibraryModel
  let detailModel: MenuDetailModel
  let menu: CoreMenu
  let dayNumber: Int
  let dayOffset: Int
  let scheduledDate: Date?
  let rows: [MenuItemRowData]
  let handoffTransport: HandoffInAppTransport
  let isExpanded: Bool
  var onToggle: () -> Void
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        if rows.isEmpty {
          HStack(spacing: 6) {
            dayTitle
              .font(.headline)
              .foregroundStyle(.secondary)
            Text("— no dishes")
              .font(.subheadline)
              .foregroundStyle(.tertiary)
          }
        } else {
          Button(action: onToggle) {
            HStack(spacing: 8) {
              Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
              dayTitle
                .font(.headline)
                .foregroundStyle(.secondary)
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            isExpanded
              ? Text("Collapse \(dayAccessibilityTitle)")
              : Text("Expand \(dayAccessibilityTitle)")
          )
        }

        Spacer()

        Button {
          model.addItemButtonTapped(
            menu: menu,
            kind: .recipe,
            dayOffset: dayOffset,
            mealSlot: .dinner
          )
        } label: {
          Label("Add Recipe to Day \(dayNumber)", systemImage: "plus.circle")
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Add recipe to Day \(dayNumber)")

        Menu {
          HandoffMenuActions(
            handoffSource: .menuDay(menu.id, dayOffset: dayOffset),
            complementHandoffSource: .menuDayComplement(menu.id, dayOffset: dayOffset),
            transport: handoffTransport,
            prepLabel: "Hand off · Prep",
            pastePrepLabel: "Paste · Prep",
            complementLabel: "Hand off · Complement",
            pasteComplementLabel: "Paste · Complement"
          )
        } label: {
          Label("Hand off", systemImage: HandoffSymbol.handOff)
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Hand off actions for Day \(dayNumber)")
      }

      if isExpanded, !rows.isEmpty {
        VStack(spacing: 0) {
          ForEach(rows) { row in
            MenuDishRowView(
              model: model,
              detailModel: detailModel,
              menu: menu,
              row: row,
              onRecipeSelected: onRecipeSelected
            )
            if row.id != rows.last?.id {
              Divider()
                .padding(.leading, 44)
            }
          }
          .reorderable(collectionID: dayOffset)
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(.quaternary)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  private var dayTitle: Text {
    guard let scheduledDate else {
      return Text("Day \(dayNumber)")
    }

    let weekday = scheduledDate.formatted(.dateTime.weekday(.wide))
    let date = scheduledDate.formatted(.dateTime.month(.abbreviated).day())
    return Text("\(weekday), \(date) · Day \(dayNumber)")
  }

  private var dayAccessibilityTitle: String {
    guard let scheduledDate else {
      return String(localized: "Day \(dayNumber)")
    }

    let weekday = scheduledDate.formatted(.dateTime.weekday(.wide))
    let date = scheduledDate.formatted(.dateTime.month(.abbreviated).day())
    return String(localized: "\(weekday), \(date) · Day \(dayNumber)")
  }
}

private struct MenuDishRowView: View {
  let model: MenuLibraryModel
  let detailModel: MenuDetailModel
  let menu: CoreMenu
  let row: MenuItemRowData
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?

  private var isDepositTarget: Bool {
    detailModel.selectedTargetItemID == row.id
  }

  private var isAskActive: Bool { detailModel.chatModel != nil }

  var body: some View {
    rowContent
      .background(isAskActive && isDepositTarget ? Color.accentColor.opacity(0.12) : Color.clear)
      .contextMenu {
        Button {
          model.editItemButtonTapped(menu: menu, row: row)
        } label: {
          Label("Edit", symbol: .editRow)
        }

        Menu {
          ForEach(0..<menu.dayCount, id: \.self) { dayOffset in
            Button {
              _ = model.moveMenuItem(itemID: row.id, toDayOffset: dayOffset)
            } label: {
              Label("Day \(dayOffset + 1)", symbol: .calendar)
            }
            .disabled(dayOffset == row.item.dayOffset)
          }
        } label: {
          Label("Move to Day", systemImage: "arrow.right")
        }

        if row.item.kind == .note {
          Button {
            detailModel.makeRecipeFromNoteButtonTapped(row.item)
          } label: {
            Label("Make Recipe", symbol: .makeRecipe)
          }
        }

        if isAskActive {
          Button {
            detailModel.targetItemTapped(row.id)
          } label: {
            Label(isDepositTarget ? "Clear Chat Target" : "Set as Chat Target", symbol: .chatTarget)
          }
        }

        Button(role: .destructive) {
          model.deleteMenuItemButtonTapped(row)
        } label: {
          Label("Delete", symbol: .delete)
        }
      }
      .swipeActions {
        Button(role: .destructive) {
          model.deleteMenuItemButtonTapped(row)
        } label: {
          Label("Delete", symbol: .delete)
        }

        Menu {
          ForEach(0..<menu.dayCount, id: \.self) { dayOffset in
            Button {
              _ = model.moveMenuItem(itemID: row.id, toDayOffset: dayOffset)
            } label: {
              Label("Day \(dayOffset + 1)", symbol: .calendar)
            }
            .disabled(dayOffset == row.item.dayOffset)
          }
        } label: {
          Label("Move to Day", systemImage: "arrow.right")
        }
      }
      .swipeActions(edge: .leading) {
        if row.item.kind == .note {
          Button {
            detailModel.makeRecipeFromNoteButtonTapped(row.item)
          } label: {
            Label("Make Recipe", symbol: .makeRecipe)
          }
        } else {
          Button {
            model.editItemButtonTapped(menu: menu, row: row)
          } label: {
            Label("Edit", symbol: .editRow)
          }
        }
      }
  }

  private var rowContent: some View {
    HStack(alignment: .top, spacing: 12) {
      dishImage

      VStack(alignment: .leading, spacing: 5) {
        Button {
          primaryAction()
        } label: {
          Text(row.displayTitle)
            .font(.headline)
        }
        .buttonStyle(.plain)
        Menu {
          ForEach(MealPlanItemSlot.allCases, id: \.self) { mealSlot in
            Button {
              _ = model.moveMenuItem(
                itemID: row.id,
                toDayOffset: row.item.dayOffset,
                mealSlot: mealSlot
              )
            } label: {
              Label(mealSlot.title, systemImage: mealSlot.systemImage)
            }
            .disabled(mealSlot == row.item.mealSlot)
          }
        } label: {
          Label(row.item.mealSlot.title, systemImage: row.item.mealSlot.systemImage)
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        if let notes = row.displayNotes {
          Text(notes)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }
      }

      Spacer()

      if isAskActive && isDepositTarget {
        Image(symbol: .chatTarget)
          .foregroundStyle(.tint)
          .accessibilityLabel("Chat target")
      }
    }
    .padding(12)
  }

  private func primaryAction() {
    if let recipeID = row.recipe?.id, let onRecipeSelected {
      onRecipeSelected(
        RecipeDetailPresentation(
          recipeID: recipeID,
          scaleContext: .menuItem(row.item.id),
          includingArchivedRecipe: true
        )
      )
    } else {
      model.editItemButtonTapped(menu: menu, row: row)
    }
  }

  @ViewBuilder private var dishImage: some View {
    if row.item.kind == .recipe {
      RecipeThumbnail(data: row.thumbnailData)
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    } else {
      Image(symbol: row.item.kind.symbol)
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(width: 32, height: 32)
    }
  }
}

struct MenuDraggedRecipe: Codable, Transferable {
  var recipeID: Recipe.ID

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .yesChefMenuRecipe)
  }
}

extension UTType {
  static let yesChefMenuRecipe = UTType(exportedAs: "com.jonphillips.yeschef.menu-recipe")
}

private struct MenuDayFramesKey: PreferenceKey {
  static var defaultValue: [Int: CGRect] { [:] }
  static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}
