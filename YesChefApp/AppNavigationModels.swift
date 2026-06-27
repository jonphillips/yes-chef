import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
  case recipes
  case mealCalendar
  case groceries
  case menus
  case settings

  var id: Self { self }

  @ViewBuilder var label: some View {
    Label(title, systemImage: systemImage)
  }

  var title: String {
    switch self {
    case .recipes: "Recipes"
    case .mealCalendar: "Meal Calendar"
    case .groceries: "Groceries"
    case .menus: "Menus"
    case .settings: "Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .recipes: "book.closed"
    case .mealCalendar: "calendar"
    case .groceries: "cart"
    case .menus: "menucard"
    case .settings: "gearshape"
    }
  }
}

enum SettingsPane: String, CaseIterable, Identifiable {
  case categories
  case pantry

  var id: Self { self }

  var title: String {
    switch self {
    case .categories: "Categories"
    case .pantry: "Pantry"
    }
  }

  var systemImage: String {
    switch self {
    case .categories: "folder"
    case .pantry: "list.bullet"
    }
  }

  @ViewBuilder var label: some View {
    Label(title, systemImage: systemImage)
  }
}
