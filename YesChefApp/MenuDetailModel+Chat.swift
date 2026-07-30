import YesChefCore

private enum MenuChatStarter: String, CaseIterable {
  case prepPlan
  case complement

  var starter: ChatSurface.ChatStarter {
    switch self {
    case .prepPlan: .init(id: rawValue, title: "Prep Plan")
    case .complement: .init(id: rawValue, title: "Complement")
    }
  }
}

extension MenuDetailModel {
  var chatStarters: [ChatSurface.ChatStarter] {
    MenuChatStarter.allCases.map(\.starter)
  }

  var chatModel: RecipeChatModel? {
    guard case let .chat(chatModel) = tool else { return nil }
    return chatModel
  }

  /// Toggles an unseeded menu chat. Guided prompts remain inside the panel's Discuss menu, so
  /// opening Ask is always free and immediately ready for a cook's own question.
  func askButtonTapped() {
    guard let detail else { return }
    if case .chat? = tool {
      dismissTool()
      return
    }
    prepPlanHandoffIntent = .refine
    activeChatStarterID = nil
    tool = .chat(RecipeChatModel(context: .menu(MenuChatContext(detail: detail))))
  }

  func recipeBrowserButtonTapped() {
    if case .recipeBrowser? = tool {
      dismissTool()
    } else {
      activeChatStarterID = nil
      tool = .recipeBrowser
    }
  }

  func dismissTool() {
    tool = nil
  }

  func selectChatStarter(_ starterID: ChatSurface.ChatStarter.ID) {
    guard let starter = MenuChatStarter(rawValue: starterID), let detail else { return }
    guard activeChatStarterID != starterID else { return }
    let context = MenuChatContext(detail: detail)
    let prompt: String
    let summary: String

    switch starter {
    case .prepPlan:
      prepPlanHandoffIntent = .refine
      prompt = context.discussAsk()
      summary = "Started Prep Plan discussion."
    case .complement:
      prompt = AIHandoffToken.discussAsk(
        context: MenuHandoffContext(detail: detail).complementPrompt(),
        deliverableFormat: .menuComplement,
        destination: .onboard
      )
      summary = "Started Complement discussion."
    }

    // The chat can be opened before a starter is selected. Reuse that live thread so selecting a
    // second starter appends its opener instead of silently retaining the prior discussion scope.
    let chatModel = chatModel(for: context)

    Task {
      switch await chatModel.seedIfCold(prompt, summary: summary) {
      case .seeded:
        guard isShowing(chatModel) else { return }
        activeChatStarterID = starterID
      case .failed:
        guard isShowing(chatModel) else { return }
        activeChatStarterID = nil
      case .alreadyWarm:
        guard await chatModel.send(prompt), isShowing(chatModel) else { return }
        activeChatStarterID = starterID
      }
    }
  }

  func regeneratePrepPlan() {
    guard let detail else { return }
    // Regeneration creates a new deliverable; it is not a guided discussion-starter selection.
    // Keep Discuss unselected rather than presenting a regeneration as a Prep Plan conversation.
    prepPlanHandoffIntent = .regenerate
    activeChatStarterID = nil
    let context = MenuChatContext(detail: detail)
    let chatModel = chatModel(for: context)
    Task {
      await chatModel.send(context.discussAsk())
    }
  }

  func onboardPrepPlanFinalized() {
    prepPlanHandoffIntent = .refine
  }

  private func chatModel(for context: MenuChatContext) -> RecipeChatModel {
    if let chatModel {
      chatModel.updateContext(.menu(context))
      return chatModel
    }
    let chatModel = RecipeChatModel(context: .menu(context))
    tool = .chat(chatModel)
    return chatModel
  }

  private func isShowing(_ chatModel: RecipeChatModel) -> Bool {
    self.chatModel === chatModel
  }
}
