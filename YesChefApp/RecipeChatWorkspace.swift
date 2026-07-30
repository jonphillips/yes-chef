import Dependencies
import LLMClientKit
import SwiftUI
import UIKit
import YesChefCore

enum ChatWorkspaceDetent: String, CaseIterable {
  case readerOnly
  case balanced
  case chatDive

  var title: String {
    switch self {
    case .readerOnly: "Reader Only"
    case .balanced: "Balanced"
    case .chatDive: "Chat Dive"
    }
  }

  var next: Self {
    switch self {
    case .readerOnly: .balanced
    case .balanced: .chatDive
    case .chatDive: .readerOnly
    }
  }

  var previous: Self {
    switch self {
    case .readerOnly: .chatDive
    case .balanced: .readerOnly
    case .chatDive: .balanced
    }
  }
}

struct ChatWorkspaceSplit<Reader: View>: View {
  let context: RecipeChatContext
  let detentIdentity: ChatSurface.DetentIdentity
  let toggleRequest: Int
  let activeTierChanged: (ModelTier) -> Void
  let applyActions: (RecipeChatModel) -> [AnyChatApplyAction]
  let reader: Reader

  @AppStorage private var detentRaw: String
  @State private var chatModel: RecipeChatModel
  @GestureState private var dragTranslation: CGFloat = 0

  init(
    context: RecipeChatContext,
    detentIdentity: ChatSurface.DetentIdentity,
    toggleRequest: Int = 0,
    activeTierChanged: @escaping (ModelTier) -> Void = { _ in },
    applyActions: @escaping (RecipeChatModel) -> [AnyChatApplyAction],
    @ViewBuilder reader: () -> Reader
  ) {
    self.context = context
    self.detentIdentity = detentIdentity
    self.toggleRequest = toggleRequest
    self.activeTierChanged = activeTierChanged
    self.applyActions = applyActions
    self.reader = reader()
    _detentRaw = AppStorage(
      wrappedValue: ChatWorkspaceDetent.balanced.rawValue,
      detentIdentity.rawValue
    )
    _chatModel = State(wrappedValue: RecipeChatModel(context: context))
  }

  var body: some View {
    GeometryReader { proxy in
      let detent = currentDetent
      let baseChatWidth = chatWidth(for: detent, totalWidth: proxy.size.width)
      let liveChatWidth = proposedChatWidth(
        base: baseChatWidth,
        translation: dragTranslation,
        totalWidth: proxy.size.width
      )

      HStack(spacing: 0) {
        reader
          .frame(width: readerWidth(totalWidth: proxy.size.width, chatWidth: liveChatWidth))
          .clipped()

        ChatWorkspaceDivider(detent: detent) {
          cycleDetent()
        } decrement: {
          currentDetent = detent.previous
        } increment: {
          currentDetent = detent.next
        }
        .simultaneousGesture(
          DragGesture(minimumDistance: 2)
            .updating($dragTranslation) { value, state, _ in
              state = value.translation.width
            }
            .onEnded { value in
              let proposed = proposedChatWidth(
                base: baseChatWidth,
                translation: value.translation.width,
                totalWidth: proxy.size.width
              )
              currentDetent = nearestDetent(toChatWidth: proposed, totalWidth: proxy.size.width)
            }
        )

        if liveChatWidth > 1 {
          RecipeChatPanel(
            chatModel: chatModel,
            surface: chatSurface
          )
          .frame(width: liveChatWidth)
          .transition(.move(edge: .trailing).combined(with: .opacity))
        }
      }
      .animation(.snappy(duration: 0.22), value: currentDetent)
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
    }
    .onChange(of: context) { _, context in
      chatModel.updateContext(context)
    }
    .onAppear {
      activeTierChanged(chatModel.activeTier)
    }
    .onChange(of: chatModel.activeTier) { _, tier in
      activeTierChanged(tier)
    }
    .onChange(of: toggleRequest) { _, _ in
      currentDetent = currentDetent == .readerOnly ? .balanced : .readerOnly
    }
  }

  private var chatSurface: ChatSurface {
    let content = ChatSurface.Content(applyActions: applyActions(chatModel))
    switch detentIdentity {
    case .calendar:
      return ChatSurface.calendarWorkspaceColumn(content: content)
    case .workbenchDetail:
      return ChatSurface.workbenchDetailColumn(content: content)
    case .workbenchCompare:
      return ChatSurface.workbenchCompareColumn(content: content)
    }
  }

  private var currentDetent: ChatWorkspaceDetent {
    get {
      ChatWorkspaceDetent(rawValue: detentRaw) ?? .balanced
    }
    nonmutating set {
      detentRaw = newValue.rawValue
    }
  }

  private func readerWidth(totalWidth: CGFloat, chatWidth: CGFloat) -> CGFloat {
    max(0, totalWidth - ChatWorkspaceDivider.dividerWidth - chatWidth)
  }

  private func proposedChatWidth(base: CGFloat, translation: CGFloat, totalWidth: CGFloat) -> CGFloat {
    let maximum = max(0, totalWidth - ChatWorkspaceDivider.dividerWidth - ChatWorkspaceMetrics.minimumSegmentedReaderWidth)
    return min(max(base - translation, 0), maximum)
  }

  private func chatWidth(for detent: ChatWorkspaceDetent, totalWidth: CGFloat) -> CGFloat {
    let available = max(0, totalWidth - ChatWorkspaceDivider.dividerWidth)
    switch detent {
    case .readerOnly:
      return 0
    case .balanced:
      return min(
        max(totalWidth * ChatWorkspaceMetrics.balancedWidthFraction, ChatWorkspaceMetrics.balancedMinimumChatWidth),
        min(
          ChatWorkspaceMetrics.balancedMaximumChatWidth,
          available * ChatWorkspaceMetrics.balancedAvailableWidthLimit
        )
      )
    case .chatDive:
      return min(
        max(totalWidth * ChatWorkspaceMetrics.chatDiveWidthFraction, ChatWorkspaceMetrics.chatDiveMinimumChatWidth),
        available
      )
    }
  }

  private func nearestDetent(toChatWidth chatWidth: CGFloat, totalWidth: CGFloat) -> ChatWorkspaceDetent {
    ChatWorkspaceDetent.allCases.min { lhs, rhs in
      abs(self.chatWidth(for: lhs, totalWidth: totalWidth) - chatWidth)
        < abs(self.chatWidth(for: rhs, totalWidth: totalWidth) - chatWidth)
    } ?? .balanced
  }

  private func cycleDetent() {
    currentDetent = currentDetent.next
  }
}

struct RecipeChatPanel: View {
  let chatModel: RecipeChatModel
  let surface: ChatSurface

  @State private var draft = ""
  @State private var assistantSelection = ChatAssistantSelection()
  @State private var applyingActionID: AnyChatApplyAction.ID?
  @State private var stagedReviewAction: AnyChatApplyAction?
  @State private var committingReviewItemID: ChatApplyReviewItem.ID?
  @State private var stagedReviewItems: [ChatApplyReviewItem] = []
  @State private var isReviewSheetPresented = false
  @State private var actionError: String?
  @State private var confirmingClearChat = false
  @State private var isFinalizing = false
  @FocusState private var isDraftFocused: Bool
  @Dependency(\.handoffReviewCoordinator) private var handoffReviewCoordinator

  var body: some View {
    @Bindable var chatModel = chatModel

    VStack(spacing: 0) {
      if showsEmbeddedHeader {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          if !starters.isEmpty, let selectStarter {
            ChatStarterMenu(starters: starters, activeStarterID: activeStarterID, select: selectStarter)
          } else {
            Text(chatModel.context.title)
              .font(.headline)
              .lineLimit(1)
          }
          Spacer(minLength: 8)
          chatOptionsMenu
          if let onDismiss {
            Button(action: onDismiss) {
              Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .accessibilityLabel(Text("Close Ask"))
          }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 10)
        Divider()
      }

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ChatContextHeader(chatModel: chatModel)
            if chatModel.messages.isEmpty {
              ChatEmptyState(
                subject: chatModel.context.subject,
                hasStarters: !starters.isEmpty,
                needsReplyForApply: applyActionsNeedReply
              )
            } else {
              ForEach(chatModel.messages) { message in
                ChatMessageBubble(
                  message: message,
                  selection: assistantSelection,
                  seedSummary: chatModel.seedSummary(for: message.id)
                )
                  .id(message.id)
              }
            }
          }
          .padding()
        }
        // A seeded or restored thread arrives with its messages already present, so
        // `.onChange` never fires for them — without this the panel opens scrolled to the
        // top of the machine-authored opener instead of on the reply the cook came to read.
        .defaultScrollAnchor(.bottom)
        .onChange(of: chatModel.messages.count) { _, _ in
          guard let lastID = chatModel.messages.last?.id else { return }
          withAnimation {
            proxy.scrollTo(lastID, anchor: .bottom)
          }
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 12) {
        if let error = chatModel.errorText ?? actionError {
          ChatErrorBanner(message: error)
        }

        if let visibleActionSubject {
          ChatActionSubjectView(
            subject: visibleActionSubject,
            onClear: visibleActionSubject.source == .selection ? { assistantSelection.clear() } : nil
          )
        }

        if let finalization, let finalizeAction {
          Button {
            Task { await finalize(finalization, using: finalizeAction) }
          } label: {
            Label(
              isFinalizing ? "Finalizing…" : finalization.title,
              systemImage: isFinalizing ? "hourglass" : "checkmark.seal"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.borderedProminent)
          .disabled(
            !canFinalize
              || chatModel.isResponding
              || applyingActionID != nil
              || isFinalizing
              || committingReviewItemID != nil
          )
          .accessibilityHint(Text("Creates the final deliverable from this discussion for review."))
        }

        Menu {
          ForEach(visibleApplyActions) { action in
            Button {
              Task { await run(action) }
            } label: {
              Label(action.title, systemImage: action.systemImage)
            }
            .disabled(!canRun(action))
          }
        } label: {
          Label(applyMenuTitle, systemImage: applyingActionID == nil ? "wand.and.stars" : "hourglass")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(
          visibleApplyActions.isEmpty
            || chatModel.isResponding
            || applyingActionID != nil
            || isFinalizing
            || committingReviewItemID != nil
            || !visibleApplyActions.contains(where: canRun)
        )
        HStack(alignment: .bottom, spacing: 8) {
          TextField("Ask about this \(chatModel.context.subject)", text: $draft, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...4)
            .focused($isDraftFocused)
            .onSubmit {
              Task { await sendDraft() }
            }

          Button {
            if chatModel.isResponding {
              chatModel.stop()
            } else {
              Task { await sendDraft() }
            }
          } label: {
            Image(systemName: chatModel.isResponding ? "stop.circle.fill" : "arrow.up.circle.fill")
              .font(.title2)
          }
          .buttonStyle(.plain)
          .disabled(!chatModel.isResponding && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityLabel(Text(chatModel.isResponding ? "Stop" : "Send"))
        }
      }
      .padding()
      .background(.background)
    }
    .modifier(
      RecipeChatPanelNavigationChrome(
        title: chatModel.context.title,
        showsEmbeddedHeader: showsEmbeddedHeader
      )
    )
    .onAppear {
      if surface.content.focusesInputOnAppear {
        isDraftFocused = true
      }
      if surface.presentation.panelOwnsActiveTierPropagation {
        surface.content.activeTierChanged(chatModel.activeTier)
      }
    }
    .onChange(of: chatModel.activeTier) { _, tier in
      if surface.presentation.panelOwnsActiveTierPropagation {
        surface.content.activeTierChanged(tier)
      }
    }
    .toolbar {
      if !showsEmbeddedHeader {
        if let onDismiss {
          ToolbarItem(placement: .topBarLeading) {
            Button("Done") { onDismiss() }
          }
        }
        if !starters.isEmpty, let selectStarter {
          ToolbarItem(placement: .principal) {
            ChatStarterMenu(starters: starters, activeStarterID: activeStarterID, select: selectStarter)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          chatOptionsMenu
        }
      }
    }
    .alert("Clear this chat?", isPresented: $confirmingClearChat) {
      Button("Clear Chat", role: .destructive) {
        clearChat()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes the scratch transcript for this \(chatModel.context.subject).")
    }
    .sheet(isPresented: $isReviewSheetPresented, onDismiss: {
      stagedReviewItems = []
      stagedReviewAction = nil
    }) {
      RecipeCollectionReviewSheet(
        items: stagedReviewItems,
        committingItemID: committingReviewItemID,
        commit: { item, approvedText, usingSecondaryCommit in
          await commit(item, approvedText: approvedText, usingSecondaryCommit: usingSecondaryCommit)
        },
        discard: { item in
          discard(item)
        },
        discardAll: {
          discardAll()
        },
        onEmpty: {
          isReviewSheetPresented = false
        }
      )
    }
  }

  private var applyActions: [AnyChatApplyAction] {
    surface.content.applyActions
  }

  private var finalization: ChatFinalizeConfiguration? {
    surface.content.finalization
  }

  private var showsEmbeddedHeader: Bool {
    surface.presentation.drawsEmbeddedHeader
  }

  private var starters: [ChatSurface.ChatStarter] {
    guard case let .starters(starters, _, _) = surface.sections else { return [] }
    return starters
  }

  private var selectStarter: ((ChatSurface.ChatStarter.ID) -> Void)? {
    guard case let .starters(_, _, select) = surface.sections else { return nil }
    return select
  }

  private var activeStarterID: ChatSurface.ChatStarter.ID? {
    guard case let .starters(_, active, _) = surface.sections else { return nil }
    return active
  }

  private var onDismiss: (() -> Void)? {
    surface.presentation.onDismiss
  }

  private func sendDraft() async {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    draft = ""
    actionError = nil
    stagedReviewItems = []
    isReviewSheetPresented = false
    await chatModel.send(text)
  }

  @MainActor
  private func finalize(
    _ finalization: ChatFinalizeConfiguration,
    using action: AnyChatApplyAction
  ) async {
    guard canFinalize else { return }

    if case .onDevice = chatModel.activeTier {
      await run(action)
      return
    }

    isFinalizing = true
    actionError = nil
    defer { isFinalizing = false }

    // The seed already teaches the shared discussion convention: this is the visible equivalent
    // of the cook typing “finalize,” not a second authored prompt or return parser.
    if let finalizationError = await OnboardChatFinalizer.finalize(
      using: chatModel, stage: { result in
        try await handoffReviewCoordinator.stageOnboardReview(
          source: finalization.source,
          result: result
        )
      },
      onFinalized: finalization.onFinalized
    ) {
      actionError = finalizationError
    }
  }

  @MainActor
  private func run(_ action: AnyChatApplyAction) async {
    let subject = actionSubject(for: action)
    let selectedText: String?
    if let subject {
      switch subject.source {
      case .selection:
        selectedText = subject.text
      case .latestReply:
        selectedText = nil
      }
    } else {
      selectedText = nil
    }
    let subjectSource = subject?.source.logDescription ?? "none"
    AppLog.applyAction.info(
      "invoke id=\(action.id, privacy: .public) title=\(action.title, privacy: .public) subjectSource=\(subjectSource, privacy: .public) subjectPresent=\(subject != nil, privacy: .public)"
    )
    guard !action.requiresSubject || subject != nil else { return }
    applyingActionID = action.id
    actionError = nil
    defer {
      if let selectedText {
        assistantSelection.clear(ifMatching: selectedText)
      }
      applyingActionID = nil
    }

    do {
      let items = try await action.run(subject?.text ?? "", chatModel.messages)
      guard !items.isEmpty else {
        let emptyResultMessage = action.emptyResultMessage ?? "The assistant did not return anything to review."
        AppLog.applyAction.info(
          "extract id=\(action.id, privacy: .public) title=\(action.title, privacy: .public) outcome=empty itemCount=0 emptyResultMessage=\(emptyResultMessage, privacy: .public)"
        )
        actionError = emptyResultMessage
        return
      }
      AppLog.applyAction.info(
        "extract id=\(action.id, privacy: .public) title=\(action.title, privacy: .public) outcome=items itemCount=\(items.count, privacy: .public)"
      )
      stagedReviewAction = action
      stagedReviewItems = items
      isReviewSheetPresented = true
    } catch {
      let errorDescription = String(describing: error)
      AppLog.applyAction.error(
        "extract id=\(action.id, privacy: .public) title=\(action.title, privacy: .public) outcome=error error=\(errorDescription, privacy: .public)"
      )
      actionError = RecipeChatErrorText.describe(error)
    }
  }

  @MainActor
  private func commit(
    _ item: ChatApplyReviewItem,
    approvedText: String,
    usingSecondaryCommit: Bool
  ) async -> Bool {
    let actionID = stagedReviewAction?.id ?? "unknown"
    let actionTitle = stagedReviewAction?.title ?? "unknown"
    AppLog.applyAction.info(
      "commit-start id=\(actionID, privacy: .public) title=\(actionTitle, privacy: .public) reviewItem=\(item.title, privacy: .public)"
    )
    committingReviewItemID = item.id
    actionError = nil
    defer { committingReviewItemID = nil }

    do {
      try await item.commit(approvedText, usingSecondaryCommit: usingSecondaryCommit)
      stagedReviewItems.removeAll { $0.id == item.id }
      if stagedReviewItems.isEmpty {
        isReviewSheetPresented = false
        stagedReviewAction = nil
      }
      AppLog.applyAction.info(
        "commit-success id=\(actionID, privacy: .public) title=\(actionTitle, privacy: .public) reviewItem=\(item.title, privacy: .public)"
      )
      return true
    } catch {
      let errorDescription = String(describing: error)
      AppLog.applyAction.error(
        "commit-error id=\(actionID, privacy: .public) title=\(actionTitle, privacy: .public) reviewItem=\(item.title, privacy: .public) error=\(errorDescription, privacy: .public)"
      )
      actionError = RecipeChatErrorText.describe(error)
      return false
    }
  }

  @MainActor
  private func discard(_ item: ChatApplyReviewItem) {
    stagedReviewItems.removeAll { $0.id == item.id }
    if stagedReviewItems.isEmpty {
      isReviewSheetPresented = false
      stagedReviewAction = nil
    }
  }

  @MainActor
  private func discardAll() {
    stagedReviewItems = []
    isReviewSheetPresented = false
    stagedReviewAction = nil
  }

  private var visibleActionSubject: ChatActionSubject? {
    if let selectionSubject {
      return selectionSubject
    }
    guard !applyActions.isEmpty, applyActions.allSatisfy(\.requiresSubject) else { return nil }
    return latestReplySubject
  }

  private var finalizeAction: AnyChatApplyAction? {
    guard let finalization else { return nil }
    return applyActions.first { $0.id == finalization.actionID }
  }

  private var visibleApplyActions: [AnyChatApplyAction] {
    guard let finalization else { return applyActions }
    return applyActions.filter { $0.id != finalization.actionID }
  }

  private var canFinalize: Bool {
    latestReplySubject != nil
  }

  private var applyActionsNeedReply: Bool {
    latestReplySubject == nil
      && selectionSubject == nil
      && visibleApplyActions.contains(where: \.requiresSubject)
  }

  private func actionSubject(for action: AnyChatApplyAction) -> ChatActionSubject? {
    if let selectionSubject {
      return selectionSubject
    }
    guard action.requiresSubject else { return nil }
    return latestReplySubject
  }

  private func canRun(_ action: AnyChatApplyAction) -> Bool {
    !action.requiresSubject || actionSubject(for: action) != nil
  }

  private var selectionSubject: ChatActionSubject? {
    let selected = assistantSelection.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !selected.isEmpty {
      return ChatActionSubject(source: .selection, text: selected)
    }
    return nil
  }

  private var latestReplySubject: ChatActionSubject? {
    guard
      let reply = chatModel.messages.last(where: { $0.role == .assistant })?.text
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !reply.isEmpty
    else { return nil }
    return ChatActionSubject(source: .latestReply, text: reply)
  }

  private var applyMenuTitle: String {
    guard let applyingActionID, let action = applyActions.first(where: { $0.id == applyingActionID }) else {
      return "Apply..."
    }
    return action.extractingTitle
  }

  private var chatOptionsMenu: some View {
    Menu {
      Button(role: .destructive) {
        confirmingClearChat = true
      } label: {
        Label("Clear Chat", systemImage: "trash")
      }
      .disabled(chatModel.messages.isEmpty || chatModel.isResponding)

      Divider()

      ChatTierOptions(chatModel: chatModel)
    } label: {
      Image(systemName: "ellipsis")
        .foregroundStyle(chatOptionsTint)
    }
    .tint(chatOptionsTint)
    .accessibilityLabel(Text("Chat options"))
    .accessibilityValue(
      Text(chatModel.sendsToProvider ? chatModel.selectedProvider.displayName : "On-device")
    )
    .accessibilityHint(
      Text("Choose whether recipe context stays on device or is sent to a configured provider.")
    )
  }

  private var chatOptionsTint: Color {
    chatModel.sendsToProvider ? .blue : .green
  }

  private func clearChat() {
    assistantSelection.clear()
    stagedReviewItems = []
    isReviewSheetPresented = false
    actionError = nil
    chatModel.clear()
  }
}

private struct RecipeChatPanelNavigationChrome: ViewModifier {
  let title: String
  let showsEmbeddedHeader: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if showsEmbeddedHeader {
      content
    } else {
      content
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
  }
}

private struct ChatMessageBubble: View {
  let message: RecipeChatMessage
  let selection: ChatAssistantSelection
  let seedSummary: String?

  var body: some View {
    HStack {
      if message.role == .user {
        Spacer(minLength: 48)
      }
      bubbleContent
        .padding(10)
        .background(
          message.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
          in: RoundedRectangle(cornerRadius: 8)
        )
      if message.role == .assistant {
        Spacer(minLength: 48)
      }
    }
  }

  @ViewBuilder
  private var bubbleContent: some View {
    switch message.role {
    case .user:
      if let seedSummary {
        Text(seedSummary)
      } else {
        Text(LocalizedStringKey(message.text))
      }
    case .assistant:
      VStack(alignment: .leading, spacing: 6) {
        SelectableAssistantText(text: message.text, selection: selection)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let resolvedTier = message.resolvedTier {
          Text("Model · \(resolvedTier.displayName)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

private struct SelectableAssistantText: UIViewRepresentable {
  let text: String
  let selection: ChatAssistantSelection

  func makeUIView(context: Context) -> UITextView {
    let textView = IntrinsicTextView()
    textView.backgroundColor = .clear
    textView.delegate = context.coordinator
    textView.isEditable = false
    textView.isScrollEnabled = false
    textView.isSelectable = true
    textView.textContainerInset = .zero
    textView.textContainer.lineFragmentPadding = 0
    textView.adjustsFontForContentSizeCategory = true
    textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    // Tapping the apply menu resigns first responder without firing a selection-change
    // delegate callback. Release bubble ownership, but retain the explicit selection so
    // the action can consume it after the menu takes focus.
    let coordinator = context.coordinator
    textView.onResignFirstResponder = { [weak textView] in
      guard let textView else { return }
      coordinator.selection.relinquish(owner: textView)
    }
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.selection = selection
    let rendered = Self.attributedText(for: text)
    if textView.attributedText?.string != rendered.string {
      textView.attributedText = rendered
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: UITextView, context: Context) -> CGSize? {
    guard let width = proposal.width else { return nil }
    let targetSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    let fittingSize = textView.sizeThatFits(targetSize)
    return CGSize(width: width, height: fittingSize.height)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(selection: selection)
  }

  private static func attributedText(for text: String) -> NSAttributedString {
    let attributedString: AttributedString
    do {
      attributedString = try AttributedString(
        markdown: text,
        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
      )
    } catch {
      attributedString = AttributedString(text)
    }

    let mutable = NSMutableAttributedString(attributedString)
    let fullRange = NSRange(location: 0, length: mutable.length)
    mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
      guard value == nil else { return }
      mutable.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .body), range: range)
    }
    mutable.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
      guard value == nil else { return }
      mutable.addAttribute(.foregroundColor, value: UIColor.label, range: range)
    }
    return mutable
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var selection: ChatAssistantSelection

    init(selection: ChatAssistantSelection) {
      self.selection = selection
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      guard
        let selectedRange = textView.selectedTextRange,
        let selected = textView.text(in: selectedRange),
        !selected.isEmpty
      else {
        selection.update("", owner: textView)
        return
      }
      selection.update(selected, owner: textView)
    }
  }
}

/// Shared selection state across the assistant bubbles. Each bubble is a separate `UITextView`
/// writing into one selection, so ownership is tracked to keep a resigning bubble from wiping a
/// selection another bubble just claimed. Selection still cannot span bubbles (per-`UITextView`);
/// that is a parked ADR question, not this store's job.
@MainActor
@Observable
final class ChatAssistantSelection {
  private(set) var text: String = ""
  private var ownerID: ObjectIdentifier?

  func update(_ newText: String, owner: AnyObject) {
    let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      // Only the current owner (or an unowned selection) may collapse the shared selection.
      if ownerID == nil || ownerID == ObjectIdentifier(owner) {
        text = ""
        ownerID = nil
      }
    } else {
      text = newText
      ownerID = ObjectIdentifier(owner)
    }
  }

  func relinquish(owner: AnyObject) {
    guard ownerID == ObjectIdentifier(owner) else { return }
    // The selection is an explicit action subject, not focus state. A menu tap resigns
    // the text view before its action runs, so keep the text while allowing another
    // bubble's empty-selection callback to clear it.
    ownerID = nil
  }

  func clear() {
    text = ""
    ownerID = nil
  }

  func clear(ifMatching expectedText: String) {
    guard text == expectedText else { return }
    clear()
  }
}

private final class IntrinsicTextView: UITextView {
  var onResignFirstResponder: (() -> Void)?

  override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: contentSize.height)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    invalidateIntrinsicContentSize()
  }

  @discardableResult
  override func resignFirstResponder() -> Bool {
    let didResign = super.resignFirstResponder()
    if didResign {
      onResignFirstResponder?()
    }
    return didResign
  }
}

struct ChatApplyReviewRow: View {
  let item: ChatApplyReviewItem
  let isCommitting: Bool
  /// Set while a bulk accept is walking the list, so rows this pass has not reached yet cannot be
  /// discarded or reviewed out from under it.
  var isBulkCommitting: Bool = false
  let review: () -> Void
  let discard: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(item.title, systemImage: "checklist")
        .font(.caption.bold())
      Text(item.summary)
        .font(.callout)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack {
        Button(role: .cancel, action: discard) {
          Label("Discard", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .disabled(isCommitting || isBulkCommitting)

        Spacer(minLength: 8)

        Button(action: review) {
          Label("Review", systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.borderedProminent)
        .disabled(isCommitting || isBulkCommitting)
      }
    }
    .attentionCard()
  }
}

struct ChatApplyReviewSheet: View {
  @Environment(\.dismiss) private var dismiss

  let item: ChatApplyReviewItem
  let isCommitting: Bool
  let commit: (String, Bool) async -> Void
  let discard: () -> Void

  @State private var draftText: String
  @State private var isShowingDiscardConfirmation = false

  init(
    item: ChatApplyReviewItem,
    isCommitting: Bool,
    commit: @escaping (String, Bool) async -> Void,
    discard: @escaping () -> Void
  ) {
    self.item = item
    self.isCommitting = isCommitting
    self.commit = commit
    self.discard = discard
    _draftText = State(initialValue: item.unmodifiedApprovedText)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if item.editableText == nil {
            Text(item.summary)
              .font(.body)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else {
            VStack(alignment: .leading, spacing: 6) {
              Text(item.editableTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              TextEditor(text: $draftText)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .frame(height: ChatApplyReviewLayout.minimumEditableTextHeight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.editableText != item.summary {
              DisclosureGroup("Full proposal") {
                Text(item.summary)
                  .font(.callout)
                  .textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }

            if !item.supportingEvidenceRows.isEmpty {
              DisclosureGroup(item.supportingEvidenceTitle ?? "Supporting Evidence") {
                VStack(alignment: .leading, spacing: 10) {
                  ForEach(Array(item.supportingEvidenceRows.enumerated()), id: \.offset) { _, row in
                    Text(row)
                      .font(.callout)
                      .textSelection(.enabled)
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }
                }
              }
            }
          }
        }
        .padding()
      }
      .safeAreaPadding(.bottom)
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(item.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Discard", role: .destructive) {
            discardButtonTapped()
          }
          .disabled(isCommitting)
        }
        ToolbarItemGroup(placement: .confirmationAction) {
          // With a secondary commit the primary overwrites existing content, so the additive choice
          // leads and the destructive one carries the role — neither reads as a pre-selected default.
          if let secondaryCommit = item.secondaryCommit {
            commitButton(secondaryCommit.title, usingSecondaryCommit: true)
            commitButton(item.commitTitle, usingSecondaryCommit: false, role: .destructive)
          } else {
            commitButton(item.commitTitle, usingSecondaryCommit: false)
          }
        }
      }
    }
    .interactiveDismissDisabled(hasUnsavedEdits)
    .confirmationDialog(
      "Discard this proposal?",
      isPresented: $isShowingDiscardConfirmation,
      titleVisibility: .visible
    ) {
      Button("Discard Proposal", role: .destructive) {
        discard()
        dismiss()
      }
      Button("Keep Reviewing", role: .cancel) {}
    } message: {
      Text("Your review edits have not been saved.")
    }
    .presentationDetents([.medium, .large])
  }

  private var hasUnsavedEdits: Bool {
    guard item.editableText != nil else { return false }
    return draftText != item.unmodifiedApprovedText
  }

  private var approvedTextIsEmpty: Bool {
    draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func discardButtonTapped() {
    if hasUnsavedEdits {
      isShowingDiscardConfirmation = true
    } else {
      discard()
      dismiss()
    }
  }

  private func commitButton(
    _ title: String,
    usingSecondaryCommit: Bool,
    role: ButtonRole? = nil
  ) -> some View {
    Button(role: role) {
      Task {
        await commit(draftText, usingSecondaryCommit)
      }
    } label: {
      if isCommitting {
        ProgressView()
      } else {
        Text(title)
      }
    }
    .disabled(isCommitting || approvedTextIsEmpty)
  }
}

private enum ChatApplyReviewLayout {
  // Gives the editable review a useful starting viewport while the outer ScrollView keeps
  // long draft proposals reachable on compact sheets.
  static let minimumEditableTextHeight: CGFloat = 320
}

private struct ChatErrorBanner: View {
  let message: String

  var body: some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .font(.footnote)
      .foregroundStyle(.red)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
  }
}
