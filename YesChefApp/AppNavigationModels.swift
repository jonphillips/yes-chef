import SwiftUI
import YesChefCore

struct RecipeDetailPresentation: Hashable, Identifiable {
  var recipeID: Recipe.ID
  var scaleContext: ScaleContext
  var workbenchID: Workbench.ID?
  var includingArchivedRecipe: Bool

  init(
    recipeID: Recipe.ID,
    scaleContext: ScaleContext? = nil,
    workbenchID: Workbench.ID? = nil,
    includingArchivedRecipe: Bool = false
  ) {
    self.recipeID = recipeID
    self.scaleContext = scaleContext ?? .recipe(recipeID)
    self.workbenchID = workbenchID
    self.includingArchivedRecipe = includingArchivedRecipe
  }

  var id: String {
    "\(recipeID.uuidString):\(scaleContext.id):\(workbenchID?.uuidString ?? ""):\(includingArchivedRecipe)"
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

struct TodayPrepPresentation: Hashable, Identifiable {
  var menuID: CoreMenu.ID
  var title: String
  var id: CoreMenu.ID { menuID }
}

enum AppSection: String, CaseIterable, Identifiable {
  case recipes
  case fromChat
  case createRecipe
  case groceries
  case mealCalendar
  case menus
  case powerBrowser
  case browser
  case workbenches
  case settings

  var id: Self { self }

  var title: String {
    switch self {
    case .recipes: "Recipes"
    case .fromChat: "From Chat"
    case .createRecipe: "Create Recipe"
    case .groceries: "Groceries"
    case .mealCalendar: "Calendar"
    case .menus: "Menus"
    case .powerBrowser: "Power Browser"
    case .browser: "Browser"
    case .workbenches: "Workbench"
    case .settings: "Settings"
    }
  }

  var symbol: AppSymbol {
    switch self {
    case .recipes: .recipe
    case .fromChat: .fromChat
    case .createRecipe: .addRecipes
    case .workbenches: .workbench
    case .powerBrowser: AppSymbol("square.grid.2x2")
    case .browser: AppSymbol("safari")
    case .mealCalendar: .calendar
    case .groceries: .groceries
    case .menus: .menu
    case .settings: AppSymbol("gearshape")
    }
  }
}

enum SettingsPane: String, CaseIterable, Identifiable {
  case ai
  case categories
  case pantry
  case archivedRecipes
  case seedCoverage
  case kitchenKnowledgeExport
  case facetCoverage
#if DEBUG
  case modelCallInventory
  case cookbookSpike
#endif

  var id: Self { self }

  var title: String {
    switch self {
    case .ai: "AI"
    case .categories: "Categories"
    case .pantry: "Pantry"
    case .archivedRecipes: "Archived Recipes"
    case .seedCoverage: "Learned Areas"
    case .kitchenKnowledgeExport: "Export What I've Taught"
    case .facetCoverage: "Label Recipes"
#if DEBUG
    case .modelCallInventory: "Model Calls"
    case .cookbookSpike: "Cookbook Spike"
#endif
    }
  }

  var symbol: AppSymbol {
    switch self {
    case .ai: AppSymbol("sparkles")
    case .categories: .category
    case .pantry: AppSymbol("list.bullet")
    case .archivedRecipes: AppSymbol("archivebox")
    case .seedCoverage: AppSymbol("checklist")
    case .kitchenKnowledgeExport: AppSymbol("square.and.arrow.up")
    case .facetCoverage: .tag
#if DEBUG
    case .modelCallInventory: AppSymbol("sparkles")
    case .cookbookSpike: AppSymbol("person.2")
#endif
    }
  }

  @ViewBuilder var label: some View {
    Label(title, symbol: symbol)
  }
}
