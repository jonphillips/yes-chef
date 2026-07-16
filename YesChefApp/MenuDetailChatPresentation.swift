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

extension Optional where Wrapped == MenuDetailInspector {
  var isPresented: Bool {
    get { self != nil }
    set {
      guard !newValue else { return }
      self = nil
    }
  }
}
