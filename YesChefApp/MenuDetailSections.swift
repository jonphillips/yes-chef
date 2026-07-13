import SwiftUI
import UniformTypeIdentifiers
import YesChefCore

struct MenuDishList: View {
  let model: MenuLibraryModel
  let detailModel: MenuDetailModel
  let menu: CoreMenu
  let detail: MenuDetailData
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?

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
        MenuDaySection(
          model: model,
          detailModel: detailModel,
          menu: menu,
          dayNumber: dayOffset + 1,
          dayOffset: dayOffset,
          scheduledDate: scheduledDate(for: dayOffset),
          rows: detail.itemRows.filter { $0.item.dayOffset == dayOffset },
          onRecipeSelected: onRecipeSelected
        )
      }
    }
  }

  private var dishHeader: some View {
    Group {
      Text("Dishes")
        .font(.title2.weight(.semibold))

      Button {
        model.addItemButtonTapped(menu: menu)
      } label: {
        Label("Add Dish", systemImage: "plus")
      }
      .buttonStyle(.bordered)

      Button {
        model.placeMenuButtonTapped(menu: menu, minimumDayCount: minimumDayCount)
      } label: {
        Label("Place", systemImage: "calendar.badge.plus")
      }
      .buttonStyle(.bordered)
    }
  }

  private var minimumDayCount: Int {
    max((detail.itemRows.map(\.item.dayOffset).max() ?? 0) + 1, 1)
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
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        dayTitle
          .font(.headline)
          .foregroundStyle(.secondary)

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
      }

      if rows.isEmpty {
        Text("No dishes")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            // Interim within-day reorder: a dish can move up/down only past an adjacent sibling in the
            // same meal slot (rows are sorted day → meal slot → sortOrder, so same-slot items are
            // contiguous). Moving across meal slots stays the meal-slot pill's job.
            let canMoveUp = index > 0
              && rows[index - 1].item.mealSlot == row.item.mealSlot
            let canMoveDown = index < rows.count - 1
              && rows[index + 1].item.mealSlot == row.item.mealSlot
            MenuDishRowView(
              model: model,
              detailModel: detailModel,
              menu: menu,
              row: row,
              canMoveUp: canMoveUp,
              canMoveDown: canMoveDown,
              onRecipeSelected: onRecipeSelected
            )
            if row.id != rows.last?.id {
              Divider()
                .padding(.leading, 44)
            }
          }
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
    .dropDestination(for: MenuDraggedRecipe.self) { recipes, _ -> Bool in
      return model.addRecipesToMenu(
        recipeIDs: recipes.map(\.recipeID),
        menuID: menu.id,
        dayOffset: dayOffset,
        mealSlot: .dinner
      )
    }
    .dropDestination(for: MenuDraggedMenuItem.self) { items, _ in
      let sameMenuItems = items.filter { $0.menuID == menu.id }
      guard !sameMenuItems.isEmpty else { return false }
      return sameMenuItems.allSatisfy { item in
        model.moveMenuItem(itemID: item.itemID, toDayOffset: dayOffset)
      }
    }
  }

  private var dayTitle: Text {
    guard let scheduledDate else {
      return Text("Day \(dayNumber)")
    }

    let weekday = scheduledDate.formatted(.dateTime.weekday(.wide))
    let date = scheduledDate.formatted(.dateTime.month(.wide).day().year())
    return Text("\(weekday) - \(date) (Day \(dayNumber))")
  }
}

private struct MenuDishRowView: View {
  let model: MenuLibraryModel
  let detailModel: MenuDetailModel
  let menu: CoreMenu
  let row: MenuItemRowData
  var canMoveUp: Bool = false
  var canMoveDown: Bool = false
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?

  private var isDepositTarget: Bool {
    detailModel.selectedTargetItemID == row.id
  }

  var body: some View {
    rowContent
      .background(isDepositTarget ? Color.accentColor.opacity(0.12) : Color.clear)
      .draggable(
        MenuDraggedMenuItem(
          menuID: row.item.menuID,
          itemID: row.item.id
        )
      )
      .swipeActions {
        Button(role: .destructive) {
          model.deleteMenuItemButtonTapped(row)
        } label: {
          Label("Delete", systemImage: "trash")
        }

        if canMoveUp {
          Button {
            _ = model.reorderMenuItemWithinDay(itemID: row.id, direction: .earlier)
          } label: {
            Label("Move Up", systemImage: "arrow.up")
          }
          .tint(.indigo)
        }

        if canMoveDown {
          Button {
            _ = model.reorderMenuItemWithinDay(itemID: row.id, direction: .later)
          } label: {
            Label("Move Down", systemImage: "arrow.down")
          }
          .tint(.teal)
        }

        Menu {
          ForEach(0..<menu.dayCount, id: \.self) { dayOffset in
            Button {
              _ = model.moveMenuItem(itemID: row.id, toDayOffset: dayOffset)
            } label: {
              Label("Day \(dayOffset + 1)", systemImage: "calendar")
            }
            .disabled(dayOffset == row.item.dayOffset)
          }
        } label: {
          Label("Move to Day", systemImage: "arrow.right")
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

      if row.item.kind == .note {
        Button {
          detailModel.makeRecipeFromNoteButtonTapped(row.item)
        } label: {
          Label("Make Recipe", systemImage: "book.badge.plus")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Make a recipe from \(row.displayTitle)")
      }

      Button {
        detailModel.targetItemTapped(row.id)
      } label: {
        Label("Deposit target", systemImage: "target")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .tint(isDepositTarget ? .accentColor : .secondary)
      .accessibilityLabel(
        isDepositTarget
          ? "Clear deposit target"
          : "Set \(row.displayTitle) as chat deposit target"
      )

      Button {
        model.editItemButtonTapped(menu: menu, row: row)
      } label: {
        Label("Edit Dish", systemImage: "calendar")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Edit \(row.displayTitle)")
    }
    .padding(12)
  }

  private func primaryAction() {
    if let recipeID = row.recipe?.id, let onRecipeSelected {
      onRecipeSelected(
        RecipeDetailPresentation(
          recipeID: recipeID,
          scaleContext: .menuItem(row.item.id)
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
      Image(systemName: row.item.kind.systemImage)
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(width: 32, height: 32)
    }
  }
}

struct MenuPlacementList: View {
  let model: MenuLibraryModel
  let menu: CoreMenu
  let minimumDayCount: Int
  let placements: [MenuPlacement]

  var body: some View {
    if !placements.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text("Calendar")
          .font(.title2.weight(.semibold))

        VStack(spacing: 0) {
          ForEach(placements) { placement in
            HStack(spacing: 12) {
              Label {
                Text(placement.startDate, format: .dateTime.weekday(.wide).month(.wide).day())
              } icon: {
                Image(systemName: "calendar.badge.checkmark")
              }

              Spacer()

              Menu {
                Button {
                  model.editPlacementButtonTapped(
                    menu: menu,
                    placement: placement,
                    minimumDayCount: minimumDayCount
                  )
                } label: {
                  Label("Change Start Date", systemImage: "calendar")
                }
                Button(role: .destructive) {
                  model.deletePlacementButtonTapped(menu: menu, placement: placement)
                } label: {
                  Label("Remove from Calendar", systemImage: "trash")
                }
              } label: {
                Label("Placement Actions", systemImage: "ellipsis.circle")
                  .labelStyle(.iconOnly)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            if placement.id != placements.last?.id {
              Divider()
                .padding(.leading, 44)
            }
          }
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(.quaternary)
        }
      }
    }
  }
}

struct MenuDraggedRecipe: Codable, Transferable {
  var recipeID: Recipe.ID

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .yesChefMenuRecipe)
  }
}

struct MenuDraggedMenuItem: Codable, Transferable {
  var menuID: CoreMenu.ID
  var itemID: MenuItem.ID

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .yesChefMenuItem)
  }
}

extension UTType {
  static let yesChefMenuRecipe = UTType(exportedAs: "com.jon.yeschef.menu-recipe")
  static let yesChefMenuItem = UTType(exportedAs: "com.jon.yeschef.menu-item")
}
