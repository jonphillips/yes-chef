import YesChefCore

enum MenuDetailInspector: Identifiable {
  case recipeBrowser
  case chat(RecipeChatModel)

  var id: String {
    switch self {
    case .recipeBrowser:
      "recipeBrowser"
    case .chat:
      "chat"
    }
  }
}
