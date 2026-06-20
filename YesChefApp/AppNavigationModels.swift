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
    case .groceries: "basket"
    case .menus: "menucard"
    case .settings: "gearshape"
    }
  }
}

enum SettingsPane: String, CaseIterable, Identifiable {
  case categories

  var id: Self { self }

  var title: String {
    switch self {
    case .categories: "Categories"
    }
  }

  var systemImage: String {
    switch self {
    case .categories: "folder"
    }
  }

  @ViewBuilder var label: some View {
    Label(title, systemImage: systemImage)
  }
}
