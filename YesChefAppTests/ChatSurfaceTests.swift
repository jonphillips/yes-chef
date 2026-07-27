import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct ChatSurfaceTests {
  @Test
  func starterFactoriesExposeOnlyTheirHostSuppliedStarters() {
    var selectedRecipeSection: PlaybookSectionKind?
    let recipe = ChatSurface.recipeAskSheet(
      content: content,
      selectSection: { selectedRecipeSection = $0 },
      activeSection: .chefItUp,
      onDismiss: {}
    )

    #expect(starters(in: recipe) == [
      .init(id: "makeAhead", title: "Make-ahead"),
      .init(id: "chefItUp", title: "Chef It Up"),
      .init(id: "serveWith", title: "Serve With"),
    ])
    #expect(activeStarterID(in: recipe) == "chefItUp")
    #expect(recipe.resolvedContract.sections == .starters)
    #expect(selectedRecipeSection == nil)
    select("serveWith", in: recipe)
    #expect(selectedRecipeSection == .serveWith)

    var selectedRecipeInspectorSection: PlaybookSectionKind?
    let recipeInspector = ChatSurface.recipeAskInspector(
      content: content,
      selectSection: { selectedRecipeInspectorSection = $0 },
      activeSection: .makeAhead,
      onDismiss: {}
    )

    #expect(starters(in: recipeInspector) == starters(in: recipe))
    #expect(activeStarterID(in: recipeInspector) == "makeAhead")
    #expect(selectedRecipeInspectorSection == nil)

    let menuStarters = [
      ChatSurface.ChatStarter(id: "prepPlan", title: "Prep Plan"),
      ChatSurface.ChatStarter(id: "complement", title: "Complement"),
    ]
    var selectedMenuStarterID: String?
    let menu = ChatSurface.menuTool(
      content: content,
      starters: menuStarters,
      activeStarterID: "prepPlan",
      selectStarter: { selectedMenuStarterID = $0 },
      onDismiss: {}
    )

    #expect(starters(in: menu) == menuStarters)
    #expect(activeStarterID(in: menu) == "prepPlan")
    #expect(menu.resolvedContract.sections == .starters)
    #expect(selectedMenuStarterID == nil)
    select("complement", in: menu)
    #expect(selectedMenuStarterID == "complement")
  }

  @Test
  func noneFactoriesExposeNoStarterControl() {
    let noneSurfaces = [
      ChatSurface.calendarWorkspaceColumn(content: content),
      ChatSurface.workbenchDetailColumn(content: content),
      ChatSurface.workbenchCompareColumn(content: content),
      ChatSurface.calendarCompactSheet(content: content, onDismiss: {}),
      ChatSurface.calendarDayCompactSheet(content: content, onDismiss: {}),
      ChatSurface.workbenchCompactSheet(content: content, onDismiss: {}),
      ChatSurface.workbenchCompareCompactSheet(content: content, onDismiss: {}),
    ]

    for surface in noneSurfaces {
      #expect(starters(in: surface).isEmpty)
      #expect(activeStarterID(in: surface) == nil)
      #expect(surface.resolvedContract.sections == .none)
    }
  }

  @Test
  func menuToolIsTheOnlyChatPresentationState() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      let model = MenuDetailModel(menuID: UUID())
      let chatModel = RecipeChatModel(context: .menu(MenuChatContext(title: "Test", dayCount: 1)))

      model.tool = .chat(chatModel)
      model.activeChatStarterID = "prepPlan"
      model.recipeBrowserButtonTapped()

      guard case .recipeBrowser? = model.tool else {
        Issue.record("Browse Recipes should replace the chat tool.")
        return
      }
      #expect(model.chatModel == nil)
      #expect(model.activeChatStarterID == nil)

      model.tool = .chat(chatModel)
      model.activeChatStarterID = "prepPlan"
      model.tool = nil

      #expect(model.chatModel == nil)
      #expect(model.activeChatStarterID == nil)
    }
  }

  private var content: ChatSurface.Content {
    .init(applyActions: [])
  }

  private func starters(in surface: ChatSurface) -> [ChatSurface.ChatStarter] {
    guard case let .starters(starters, _, _) = surface.sections else { return [] }
    return starters
  }

  private func activeStarterID(in surface: ChatSurface) -> ChatSurface.ChatStarter.ID? {
    guard case let .starters(_, activeStarterID, _) = surface.sections else { return nil }
    return activeStarterID
  }

  private func select(_ starterID: ChatSurface.ChatStarter.ID, in surface: ChatSurface) {
    guard case let .starters(_, _, select) = surface.sections else {
      Issue.record("Expected a starter control.")
      return
    }
    select(starterID)
  }
}
