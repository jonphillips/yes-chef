import SwiftUI
import YesChefCore

struct RecipeDetailPresentation: Hashable, Identifiable {
  var recipeID: Recipe.ID
  var scaleContext: ScaleContext

  init(recipeID: Recipe.ID, scaleContext: ScaleContext? = nil) {
    self.recipeID = recipeID
    self.scaleContext = scaleContext ?? .recipe(recipeID)
  }

  var id: String {
    "\(recipeID.uuidString):\(scaleContext.id)"
  }
}

struct WorkbenchPresentation: Hashable, Identifiable {
  var workbenchID: Workbench.ID

  var id: Workbench.ID { workbenchID }
}

struct CookSessionItem: Hashable, Identifiable {
  var recipeID: Recipe.ID
  var scaleContext: ScaleContext
  var title: String

  var id: String { scaleContext.id }
}

struct CookSessionPresentation: Hashable, Identifiable {
  var title: String
  var items: [CookSessionItem]

  var id: String {
    ([title] + items.map(\.id)).joined(separator: "|")
  }
}

enum AppSection: String, CaseIterable, Identifiable {
  case recipes
  case workbenches
  case browser
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
    case .workbenches: "Workbenches"
    case .browser: "Browser"
    case .mealCalendar: "Meal Calendar"
    case .groceries: "Groceries"
    case .menus: "Menus"
    case .settings: "Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .recipes: "book.closed"
    case .workbenches: "hammer"
    case .browser: "safari"
    case .mealCalendar: "calendar"
    case .groceries: "cart"
    case .menus: "menucard"
    case .settings: "gearshape"
    }
  }
}

enum SettingsPane: String, CaseIterable, Identifiable {
  case ai
  case categories
  case pantry
  case archivedRecipes

  var id: Self { self }

  var title: String {
    switch self {
    case .ai: "AI"
    case .categories: "Categories"
    case .pantry: "Pantry"
    case .archivedRecipes: "Archived Recipes"
    }
  }

  var systemImage: String {
    switch self {
    case .ai: "sparkles"
    case .categories: "folder"
    case .pantry: "list.bullet"
    case .archivedRecipes: "archivebox"
    }
  }

  @ViewBuilder var label: some View {
    Label(title, systemImage: systemImage)
  }
}
