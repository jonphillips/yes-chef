import SwiftUI
import YesChefCore

struct AppSymbol: Sendable, Hashable {
  private enum Storage: Sendable, Hashable {
    case system(String)
    case asset(ImageResource)
  }

  private let storage: Storage

  init(_ systemName: String) {
    self.storage = .system(systemName)
  }

  init(_ resource: ImageResource) {
    self.storage = .asset(resource)
  }

  var image: Image {
    switch storage {
    case let .system(name): Image(systemName: name)
    case let .asset(resource): Image(resource)
    }
  }

  var systemName: String? {
    guard case let .system(name) = storage else { return nil }
    return name
  }

  var systemNameForIntents: String {
    guard let systemName else {
      preconditionFailure("Custom AppSymbols cannot be used as App Intents system image names.")
    }
    return systemName
  }

  static let recipe = Self("richtext.page")
  static let fromChat = Self("tray.and.arrow.down")
  static let addRecipes = Self(.customRichtextPageBadgePlus)
  static let makeRecipe = Self(.customRichtextPageArrowIn)
  static let menu = Self("menucard")
  static let bringIntoMenu = Self(.customMenucardArrowIn)
  static let source = Self("book")
  static let libraryShelf = Self("books.vertical")
  static let category = Self("folder")
  static let addCategory = Self("folder.badge.plus")
  static let tag = Self("tag")
  static let dish = Self("fork.knife")
  static let edit = Self("square.and.pencil")
  static let editRow = Self("pencil")
  static let delete = Self("trash")
  static let calendar = Self("calendar")
  static let plan = Self("calendar.badge.plus")
  static let groceries = Self("cart")
  static let addToGroceries = Self("cart.badge.plus")
  static let workbench = Self("hammer")
  static let chatTarget = Self("target")
  static let help = Self("questionmark.circle")
}

extension Image {
  init(symbol: AppSymbol) {
    self = symbol.image
  }
}

extension Label where Title == Text, Icon == Image {
  init(_ titleKey: LocalizedStringKey, symbol: AppSymbol) {
    self.init {
      Text(titleKey)
    } icon: {
      symbol.image
    }
  }

  init<S: StringProtocol>(_ title: S, symbol: AppSymbol) {
    self.init {
      Text(String(title))
    } icon: {
      symbol.image
    }
  }
}

extension MealPlanItemKind {
  var symbol: AppSymbol {
    switch self {
    case .recipe: .recipe
    case .note: AppSymbol("note.text")
    case .reservation: AppSymbol("fork.knife.circle")
    }
  }
}

extension GroceryItemOrigin {
  var symbol: AppSymbol {
    switch self {
    case .custom: AppSymbol("plus.circle")
    case .recipe: .recipe
    case .menu: .menu
    case .calendarItem: .calendar
    case .menuPlacement: AppSymbol("calendar.badge.checkmark")
    }
  }
}
