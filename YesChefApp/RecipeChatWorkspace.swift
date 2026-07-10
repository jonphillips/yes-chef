import LLMClientKit
import SwiftUI
import UIKit
import YesChefCore

enum ChatWorkspaceDetent: String, CaseIterable {
  static let storageKey = "recipeChatWorkspaceDetent"

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
  let detentRaw: Binding<String>
  let activeTierChanged: (ModelTier) -> Void
  let applyActions: (RecipeChatModel) -> [AnyChatApplyAction]
  let reader: Reader

  @State private var chatModel: RecipeChatModel
  @GestureState private var dragTranslation: CGFloat = 0

  init(
    context: RecipeChatContext,
    detentRaw: Binding<String>,
    activeTierChanged: @escaping (ModelTier) -> Void = { _ in },
    applyActions: @escaping (RecipeChatModel) -> [AnyChatApplyAction],
    @ViewBuilder reader: () -> Reader
  ) {
    self.context = context
    self.detentRaw = detentRaw
    self.activeTierChanged = activeTierChanged
    self.applyActions = applyActions
    self.reader = reader()
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
            applyActions: applyActions(chatModel),
            showsEmbeddedHeader: true
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
  }

  private var currentDetent: ChatWorkspaceDetent {
    get {
      ChatWorkspaceDetent(rawValue: detentRaw.wrappedValue) ?? .balanced
    }
    nonmutating set {
      detentRaw.wrappedValue = newValue.rawValue
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

private enum ChatWorkspaceMetrics {
  static let balancedMinimumChatWidth: CGFloat = 340
  static let balancedMaximumChatWidth: CGFloat = 460
  static let balancedWidthFraction: CGFloat = 0.34
  static let balancedAvailableWidthLimit: CGFloat = 0.5
  static let chatDiveMinimumChatWidth: CGFloat = 440
  // Dogfood batch 4: chat-dive should settle at roughly three quarters of iPad width.
  static let chatDiveWidthFraction: CGFloat = 0.75
  // 37.5% of RecipeReaderView's 640pt two-column threshold, preserving a narrow segmented reader.
  static let minimumSegmentedReaderWidth: CGFloat = 240
}

private struct ChatWorkspaceDivider: View {
  static let dividerWidth: CGFloat = 22

  let detent: ChatWorkspaceDetent
  let cycle: () -> Void
  let decrement: () -> Void
  let increment: () -> Void

  var body: some View {
    Button(action: cycle) {
      ZStack {
        Rectangle()
          .fill(.separator)
          .frame(width: 1)
        Capsule()
          .fill(.secondary.opacity(0.55))
          .frame(width: 5, height: 48)
      }
      .frame(minWidth: Self.dividerWidth, maxWidth: Self.dividerWidth, maxHeight: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("Recipe and chat split"))
    .accessibilityValue(Text(detent.title))
    .accessibilityHint(Text("Cycles between reader only, balanced, and chat dive."))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        increment()
      case .decrement:
        decrement()
      @unknown default:
        break
      }
    }
  }
}

struct RecipeChatPanel: View {
  let chatModel: RecipeChatModel
  let applyActions: [AnyChatApplyAction]
  var showsEmbeddedHeader = false

  @State private var draft = ""
  @State private var assistantSelection = ChatAssistantSelection()
  @State private var applyingActionID: AnyChatApplyAction.ID?
  @State private var stagedReviewActionID: String?
  @State private var stagedReviewActionTitle: String?
  @State private var committingReviewItemID: ChatApplyReviewItem.ID?
  @State private var stagedReviewItems: [ChatApplyReviewItem] = []
  @State private var isReviewSheetPresented = false
  @State private var actionError: String?
  @State private var confirmingClearChat = false

  var body: some View {
    @Bindable var chatModel = chatModel

    VStack(spacing: 0) {
      if showsEmbeddedHeader {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(chatModel.context.title)
            .font(.headline)
            .lineLimit(1)
          Spacer(minLength: 8)
          clearChatButton
          ChatTierMenu(chatModel: chatModel)
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 10)
        Divider()
      }

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ChatContextHeader(chatModel: chatModel)
            ForEach(chatModel.messages) { message in
              ChatMessageBubble(message: message, selection: assistantSelection)
                .id(message.id)
            }
          }
          .padding()
        }
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

        Menu {
          ForEach(applyActions) { action in
            Button {
              Task { await run(action) }
            } label: {
              Label(action.title, systemImage: "text.badge.checkmark")
            }
            .disabled(!canRun(action))
          }
        } label: {
          Label(applyMenuTitle, systemImage: applyingActionID == nil ? "wand.and.stars" : "hourglass")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(
          applyActions.isEmpty
            || chatModel.isResponding
            || applyingActionID != nil
            || committingReviewItemID != nil
            || !applyActions.contains(where: canRun)
        )

        HStack(alignment: .bottom, spacing: 8) {
          TextField("Ask about this \(chatModel.context.subject)", text: $draft, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
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
    .navigationTitle(chatModel.context.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if !showsEmbeddedHeader {
        ToolbarItem(placement: .topBarTrailing) {
          clearChatButton
        }
        ToolbarItem(placement: .topBarTrailing) {
          ChatTierMenu(chatModel: chatModel)
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
      stagedReviewActionID = nil
      stagedReviewActionTitle = nil
    }) {
      RecipeCollectionReviewSheet(
        items: stagedReviewItems,
        committingItemID: committingReviewItemID,
        commit: { item, approvedText in
          await commit(item, approvedText: approvedText)
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
  private func run(_ action: AnyChatApplyAction) async {
    let subject = actionSubject(for: action)
    let subjectSource = subject?.source.logDescription ?? "none"
    AppLog.applyAction.info(
      "invoke id=\(action.id, privacy: .public) title=\(action.title, privacy: .public) subjectSource=\(subjectSource, privacy: .public) subjectPresent=\(subject != nil, privacy: .public)"
    )
    guard !action.requiresSubject || subject != nil else { return }
    applyingActionID = action.id
    actionError = nil
    defer { applyingActionID = nil }

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
      stagedReviewActionID = action.id
      stagedReviewActionTitle = action.title
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
  private func commit(_ item: ChatApplyReviewItem, approvedText: String) async -> Bool {
    let actionID = stagedReviewActionID ?? "unknown"
    let actionTitle = stagedReviewActionTitle ?? "unknown"
    AppLog.applyAction.info(
      "commit-start id=\(actionID, privacy: .public) title=\(actionTitle, privacy: .public) reviewItem=\(item.title, privacy: .public)"
    )
    committingReviewItemID = item.id
    actionError = nil
    defer { committingReviewItemID = nil }

    do {
      try await item.commit(approvedText)
      stagedReviewItems.removeAll { $0.id == item.id }
      if stagedReviewItems.isEmpty {
        isReviewSheetPresented = false
        stagedReviewActionID = nil
        stagedReviewActionTitle = nil
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
      stagedReviewActionID = nil
      stagedReviewActionTitle = nil
    }
  }

  @MainActor
  private func discardAll() {
    stagedReviewItems = []
    isReviewSheetPresented = false
    stagedReviewActionID = nil
    stagedReviewActionTitle = nil
  }

  private var visibleActionSubject: ChatActionSubject? {
    if let selectionSubject {
      return selectionSubject
    }
    guard !applyActions.isEmpty, applyActions.allSatisfy(\.requiresSubject) else { return nil }
    return latestReplySubject
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

  private var clearChatButton: some View {
    Button {
      confirmingClearChat = true
    } label: {
      Image(systemName: "trash")
    }
    .disabled(chatModel.messages.isEmpty || chatModel.isResponding)
    .accessibilityLabel(Text("Clear Chat"))
  }

  private func clearChat() {
    assistantSelection.clear()
    stagedReviewItems = []
    isReviewSheetPresented = false
    actionError = nil
    chatModel.clear()
  }
}

private struct ChatContextHeader: View {
  let chatModel: RecipeChatModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(
        chatModel.sendsToProvider ? chatModel.selectedProvider.displayName : "On-device",
        systemImage: chatModel.sendsToProvider ? "network" : "iphone"
      )
        .font(.caption.bold())
        .foregroundStyle(.secondary)
      Text(
        chatModel.sendsToProvider
          ? chatModel.context.providerContextWarning
          : chatModel.context.seededContextDescription
      )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct ChatTierMenu: View {
  let chatModel: RecipeChatModel

  var body: some View {
    @Bindable var chatModel = chatModel

    Menu {
      Button {
        chatModel.useFrontier = false
      } label: {
        Label("On-device (private)", systemImage: "iphone")
        if !chatModel.sendsToProvider {
          Image(systemName: "checkmark")
        }
      }

      ForEach(FrontierProvider.allCases) { provider in
        Button {
          chatModel.selectedProvider = provider
          chatModel.useFrontier = true
        } label: {
          Label("\(provider.displayName) (sends data off device)", systemImage: "network")
          if chatModel.sendsToProvider, chatModel.selectedProvider == provider {
            Image(systemName: "checkmark")
          }
        }
        .disabled(!chatModel.availableProviders.contains(provider))
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: chatModel.sendsToProvider ? "network" : "iphone")
          .foregroundStyle(chatModel.sendsToProvider ? .blue : .green)
        Text(chatModel.sendsToProvider ? chatModel.selectedProvider.displayName : "On-device")
          .font(.subheadline)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityHint(Text("Choose whether recipe context stays on device or is sent to a configured provider."))
  }
}

private struct ChatActionSubject: Equatable {
  enum Source {
    case selection
    case latestReply
  }

  var source: Source
  var text: String

  var label: String {
    switch source {
    case .selection: "Acting on your selection"
    case .latestReply: "Acting on latest reply"
    }
  }

  var logDescription: String {
    switch source {
    case .selection: "explicit-selection-subject-chip"
    case .latestReply: "latestReplySubject-fallback"
    }
  }

  var snippet: String {
    let flattened = text
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard flattened.count > 120 else { return flattened }
    return "\(flattened.prefix(120))..."
  }
}

private struct ChatActionSubjectView: View {
  let subject: ChatActionSubject
  var onClear: (() -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        Text(subject.label)
          .font(.caption.bold())
          .foregroundStyle(.secondary)
        Text(subject.snippet)
          .font(.caption)
          .lineLimit(2)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if let onClear {
        Button(action: onClear) {
          Label("Clear selection", systemImage: "xmark.circle.fill")
            .labelStyle(.iconOnly)
            .font(.body)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Clear selection"))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct ChatMessageBubble: View {
  let message: RecipeChatMessage
  let selection: ChatAssistantSelection

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
      Text(LocalizedStringKey(message.text))
    case .assistant:
      SelectableAssistantText(text: message.text, selection: selection)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    // Tapping away / into another bubble resigns first responder without firing a
    // selection-change delegate callback, so clear the shared selection here — but only
    // if this bubble still owns it (a newly-selected bubble may already have claimed it).
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
    text = ""
    ownerID = nil
  }

  func clear() {
    text = ""
    ownerID = nil
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
        .disabled(isCommitting)

        Spacer(minLength: 8)

        Button(action: review) {
          Label("Review", systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.borderedProminent)
        .disabled(isCommitting)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
  }
}

struct ChatApplyReviewSheet: View {
  @Environment(\.dismiss) private var dismiss

  let item: ChatApplyReviewItem
  let isCommitting: Bool
  let commit: (String) async -> Void
  let discard: () -> Void

  @State private var draftText: String
  @State private var isShowingDiscardConfirmation = false

  init(
    item: ChatApplyReviewItem,
    isCommitting: Bool,
    commit: @escaping (String) async -> Void,
    discard: @escaping () -> Void
  ) {
    self.item = item
    self.isCommitting = isCommitting
    self.commit = commit
    self.discard = discard
    _draftText = State(initialValue: item.editableText ?? item.summary)
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        if item.editableText == nil {
          ScrollView {
            Text(item.summary)
              .font(.body)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        } else {
          VStack(alignment: .leading, spacing: 6) {
            Text(item.editableTitle)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            TextEditor(text: $draftText)
              .textInputAutocapitalization(.sentences)
              .autocorrectionDisabled(false)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

          if item.editableText != item.summary {
            DisclosureGroup("Full proposal") {
              ScrollView {
                Text(item.summary)
                  .font(.callout)
                  .textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
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
      .navigationTitle(item.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Discard", role: .destructive) {
            discardButtonTapped()
          }
          .disabled(isCommitting)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task {
              await commit(draftText)
            }
          } label: {
            if isCommitting {
              ProgressView()
            } else {
              Text(item.commitTitle)
            }
          }
          .disabled(isCommitting || approvedTextIsEmpty)
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
    guard let editableText = item.editableText else { return false }
    return draftText != editableText
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
