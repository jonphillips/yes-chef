import SwiftUI
import YesChefCore

struct RecipeDetailPresentation: Hashable, Identifiable {
  var recipeID: Recipe.ID
  var scaleContext: ScaleContext
  var workbenchID: Workbench.ID?

  init(
    recipeID: Recipe.ID,
    scaleContext: ScaleContext? = nil,
    workbenchID: Workbench.ID? = nil
  ) {
    self.recipeID = recipeID
    self.scaleContext = scaleContext ?? .recipe(recipeID)
    self.workbenchID = workbenchID
  }

  var id: String {
    "\(recipeID.uuidString):\(scaleContext.id):\(workbenchID?.uuidString ?? "")"
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
  case groceries
  case mealCalendar
  case menus
  case browser
  case workbenches
  case settings

  var id: Self { self }

  @ViewBuilder var label: some View {
    Label(title, systemImage: systemImage)
  }

  var title: String {
    switch self {
    case .recipes: "Recipes"
    case .groceries: "Groceries"
    case .mealCalendar: "Calendar"
    case .menus: "Menus"
    case .browser: "Browser"
    case .workbenches: "Workbench"
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
  case seedCoverage
#if DEBUG
  case modelCallInventory
#endif

  var id: Self { self }

  var title: String {
    switch self {
    case .ai: "AI"
    case .categories: "Categories"
    case .pantry: "Pantry"
    case .archivedRecipes: "Archived Recipes"
    case .seedCoverage: "Seed Coverage"
#if DEBUG
    case .modelCallInventory: "Model Calls"
#endif
    }
  }

  var systemImage: String {
    switch self {
    case .ai: "sparkles"
    case .categories: "folder"
    case .pantry: "list.bullet"
    case .archivedRecipes: "archivebox"
    case .seedCoverage: "checklist"
#if DEBUG
    case .modelCallInventory: "sparkles"
#endif
    }
  }

  @ViewBuilder var label: some View {
    Label(title, systemImage: systemImage)
  }
}
