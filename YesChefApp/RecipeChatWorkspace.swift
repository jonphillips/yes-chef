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
  let detentRaw: Binding<String>
  let applyActions: (RecipeChatModel) -> [AnyChatApplyAction]
  let reader: Reader

  @State private var chatModel: RecipeChatModel
  @GestureState private var dragTranslation: CGFloat = 0

  init(
    context: RecipeChatContext,
    detentRaw: Binding<String>,
    applyActions: @escaping (RecipeChatModel) -> [AnyChatApplyAction],
    @ViewBuilder reader: () -> Reader
  ) {
    self.detentRaw = detentRaw
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
    let maximum = max(0, totalWidth - ChatWorkspaceDivider.dividerWidth - 360)
    return min(max(base - translation, 0), maximum)
  }

  private func chatWidth(for detent: ChatWorkspaceDetent, totalWidth: CGFloat) -> CGFloat {
    let available = max(0, totalWidth - ChatWorkspaceDivider.dividerWidth)
    switch detent {
    case .readerOnly:
      return 0
    case .balanced:
      return min(max(totalWidth * 0.34, 340), min(460, available * 0.5))
    case .chatDive:
      return min(max(totalWidth * 0.48, 440), available * 0.58)
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
  @State private var selectedAssistantText = ""
  @State private var applyingActionID: AnyChatApplyAction.ID?
  @State private var committingReviewItemID: ChatApplyReviewItem.ID?
  @State private var stagedReviewItems: [ChatApplyReviewItem] = []
  @State private var actionSummary: ChatCommittedActionSummary?
  @State private var actionError: String?

  var body: some View {
    @Bindable var chatModel = chatModel

    VStack(spacing: 0) {
      if showsEmbeddedHeader {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(chatModel.context.title)
            .font(.headline)
            .lineLimit(1)
          Spacer(minLength: 8)
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
              ChatMessageBubble(message: message, selectedAssistantText: $selectedAssistantText)
                .id(message.id)
            }
            if let actionSummary {
              ChatActionSummary(summary: actionSummary)
            }
            if let error = chatModel.errorText ?? actionError {
              Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        if !stagedReviewItems.isEmpty {
          ChatApplyReviewList(
            items: stagedReviewItems,
            committingItemID: committingReviewItemID,
            commit: { item in
              Task { await commit(item) }
            },
            discard: { item in
              discard(item)
            }
          )
        }

        if let actionSubject {
          ChatActionSubjectView(subject: actionSubject)
        }

        ForEach(applyActions) { action in
          Button {
            Task { await run(action) }
          } label: {
            Label(
              applyingActionID == action.id ? action.extractingTitle : action.title,
              systemImage: applyingActionID == action.id ? "hourglass" : "text.badge.checkmark"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.bordered)
          .disabled(
            chatModel.isResponding
              || applyingActionID != nil
              || committingReviewItemID != nil
              || actionSubject == nil
          )
        }

        HStack(alignment: .bottom, spacing: 8) {
          TextField("Ask about this \(chatModel.context.subject)", text: $draft, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
            .onSubmit {
              Task { await sendDraft() }
            }

          Button {
            Task { await sendDraft() }
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.title2)
          }
          .buttonStyle(.plain)
          .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatModel.isResponding)
          .accessibilityLabel(Text("Send"))
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
          ChatTierMenu(chatModel: chatModel)
        }
      }
    }
  }

  private func sendDraft() async {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    draft = ""
    actionSummary = nil
    actionError = nil
    stagedReviewItems = []
    await chatModel.send(text)
  }

  @MainActor
  private func run(_ action: AnyChatApplyAction) async {
    guard let actionSubject else { return }
    applyingActionID = action.id
    actionSummary = nil
    actionError = nil
    defer { applyingActionID = nil }

    do {
      let items = try await action.run(actionSubject.text, chatModel.messages)
      guard !items.isEmpty else {
        actionError = "The assistant did not return anything to review."
        return
      }
      stagedReviewItems = items
    } catch {
      actionError = RecipeChatErrorText.describe(error)
    }
  }

  @MainActor
  private func commit(_ item: ChatApplyReviewItem) async {
    committingReviewItemID = item.id
    actionError = nil
    defer { committingReviewItemID = nil }

    do {
      try await item.commit()
      stagedReviewItems.removeAll { $0.id == item.id }
      actionSummary = ChatCommittedActionSummary(title: item.committedTitle, text: item.summary)
    } catch {
      actionError = RecipeChatErrorText.describe(error)
    }
  }

  @MainActor
  private func discard(_ item: ChatApplyReviewItem) {
    stagedReviewItems.removeAll { $0.id == item.id }
  }

  private var actionSubject: ChatActionSubject? {
    let selected = selectedAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !selected.isEmpty {
      return ChatActionSubject(source: .selection, text: selected)
    }
    guard
      let reply = chatModel.messages.last(where: { $0.role == .assistant })?.text
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !reply.isEmpty
    else { return nil }
    return ChatActionSubject(source: .latestReply, text: reply)
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

  @AppStorage(recipeChatFrontierProviderKey)
  private var preferredProviderRaw = FrontierProvider.anthropic.rawValue

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
          preferredProviderRaw = provider.rawValue
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

  var body: some View {
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
  }
}

private struct ChatMessageBubble: View {
  let message: RecipeChatMessage
  @Binding var selectedAssistantText: String

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
      SelectableAssistantText(text: message.text, selectedText: $selectedAssistantText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct SelectableAssistantText: UIViewRepresentable {
  let text: String
  @Binding var selectedText: String

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
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.text = text
    context.coordinator.selectedText = $selectedText
    if textView.attributedText?.string != text {
      textView.attributedText = Self.attributedText(for: text)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(selectedText: $selectedText)
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
    var text: String = ""
    var selectedText: Binding<String>

    init(selectedText: Binding<String>) {
      self.selectedText = selectedText
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      guard let range = Range(textView.selectedRange, in: text) else {
        selectedText.wrappedValue = ""
        return
      }
      selectedText.wrappedValue = String(text[range])
    }
  }
}

private final class IntrinsicTextView: UITextView {
  override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: contentSize.height)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    invalidateIntrinsicContentSize()
  }
}

private struct ChatCommittedActionSummary: Equatable {
  var title: String
  var text: String
}

private struct ChatApplyReviewList: View {
  let items: [ChatApplyReviewItem]
  let committingItemID: ChatApplyReviewItem.ID?
  let commit: (ChatApplyReviewItem) -> Void
  let discard: (ChatApplyReviewItem) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(items) { item in
        ChatApplyReviewCard(
          item: item,
          isCommitting: committingItemID == item.id,
          commit: { commit(item) },
          discard: { discard(item) }
        )
      }
    }
  }
}

private struct ChatApplyReviewCard: View {
  let item: ChatApplyReviewItem
  let isCommitting: Bool
  let commit: () -> Void
  let discard: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(item.title, systemImage: "checklist")
        .font(.caption.bold())
      Text(item.summary)
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack {
        Button(role: .cancel, action: discard) {
          Label("Discard", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .disabled(isCommitting)

        Spacer(minLength: 8)

        Button(action: commit) {
          Label(
            isCommitting ? item.committingTitle : item.commitTitle,
            systemImage: isCommitting ? "hourglass" : "checkmark.circle"
          )
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

private struct ChatActionSummary: View {
  let summary: ChatCommittedActionSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(summary.title, systemImage: "checkmark.circle")
        .font(.caption.bold())
        .foregroundStyle(.green)
      Text(summary.text)
        .font(.callout)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
  }
}
