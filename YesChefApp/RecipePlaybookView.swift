import SwiftUI
import UIKit
import YesChefCore

struct RecipePlaybookView: View {
  let model: RecipeDetailModel
  let handoffTransport: HandoffInAppTransport
  let ask: () -> Void

  @State private var isMakeAheadExpanded = true
  @State private var isNotesExpanded = true
  @State private var isChefItUpExpanded = true
  @State private var isServeWithExpanded = true
  @State private var isDeliberationLogExpanded = false
  @State private var editingSection: PlaybookSectionKind?
  @State private var clearingSection: PlaybookSectionKind?

  var body: some View {
    let visibleNotes = model.visibleNotes
    let readerFeedbackNotes = visibleNotes.filter { $0.noteType == .readerFeedback }
    let otherNotes = visibleNotes.filter { $0.noteType != .readerFeedback }
    let serveWith = model.serveWith

    VStack(alignment: .leading, spacing: 18) {
      playbookHeader
      playbookSection(
        .makeAhead,
        isFilled: model.makeAhead != nil,
        isExpanded: $isMakeAheadExpanded
      ) {
        makeAheadContent(model.makeAhead)
      }
      notesSection(
        "Notes",
        isFilled: !visibleNotes.isEmpty,
        isExpanded: $isNotesExpanded
      ) {
        if !readerFeedbackNotes.isEmpty {
          readerFeedbackView(readerFeedbackNotes)
        }
        if !otherNotes.isEmpty {
          notesView(otherNotes)
        }
      }
      playbookSection(
        .chefItUp,
        isFilled: model.chefItUp != nil,
        isExpanded: $isChefItUpExpanded
      ) {
        chefItUpContent(model.chefItUp)
      }
      playbookSection(
        .serveWith,
        isFilled: !serveWith.isEmpty,
        isExpanded: $isServeWithExpanded
      ) {
        serveWithContent(serveWith)
      }
      if !model.deliberationLogEntries.isEmpty {
        playbookSection(
          "Deliberation Log",
          isFilled: true,
          isExpanded: $isDeliberationLogExpanded,
          showsActions: false,
          actions: { EmptyView() }
        ) {
          RecipeDeliberationLogEntriesView(
            entries: model.deliberationLogEntries,
            variations: model.variations
          )
        }
      }
      if !model.learnings.isEmpty {
        LearningsSection(
          learnings: model.learnings,
          updateLearning: model.updateLearning,
          deleteLearning: model.deleteLearning,
          reorderLearnings: model.reorderLearnings
        )
      }
    }
    .sheet(item: $editingSection) { section in
      switch section {
      case .serveWith:
        EmptyView()
      case .makeAhead:
        RecipePlaybookSectionEditorSheet(
          section: section,
          initialText: model.makeAhead ?? "",
          commit: { text in
            try commit(text, for: section)
          }
        )
      case .chefItUp:
        RecipePlaybookSectionEditorSheet(
          section: section,
          initialText: model.chefItUp ?? "",
          commit: { text in
            try commit(text, for: section)
          }
        )
      }
    }
    .confirmationDialog("Clear section?", item: $clearingSection) { section in
      Button("Clear \(section.title)", role: .destructive) {
        clear(section)
      }
    } message: { section in
      switch section {
      case .makeAhead, .chefItUp, .serveWith:
        Text("This permanently clears the \(section.title) section. This cannot be undone.")
      }
    }
  }

  private var playbookHeader: some View {
    HStack(alignment: .top, spacing: 12) {
      Spacer()
      askButton
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Playbook actions")
  }

  private var isAskActive: Bool {
    model.destination.chat != nil
  }

  private var askButton: some View {
    Button(action: ask) {
      Label("Ask", systemImage: "sparkles")
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.roundedRectangle(radius: 8))
    .overlay {
      // Light the trigger up in the activity color while its panel is open.
      if isAskActive {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(.tint, lineWidth: 3)
      }
    }
    .accessibilityValue(isAskActive ? Text("Panel open") : Text("Panel closed"))
  }

  private func playbookSection<Content: View>(
    _ section: PlaybookSectionKind,
    isFilled: Bool,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    playbookSection(
      section.title,
      isFilled: isFilled,
      isExpanded: isExpanded,
      showsActions: true,
      actions: { sectionMenu(for: section, isFilled: isFilled) },
      content: content
    )
  }

  private func playbookSection<Actions: View, Content: View>(
    _ title: String,
    isFilled: Bool,
    isExpanded: Binding<Bool>,
    showsActions: Bool,
    @ViewBuilder actions: @escaping () -> Actions,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    DisclosureGroup(isExpanded: isExpanded) {
      VStack(alignment: .leading, spacing: 12) {
        content()
      }
        .padding(.top, 8)
    } label: {
      // The fill-dot and the disclosure chevron read as one status pair hugging the trailing edge; the menu
      // sits well clear of them so its tap target can't be confused for the disclosure's.
      HStack(spacing: 0) {
        Text(title)
          .font(.title2.bold())
        Spacer(minLength: 12)
        if showsActions, isExpanded.wrappedValue {
          actions()
            .padding(.trailing, 12)
        }
        Image(systemName: isFilled ? "circle.fill" : "circle")
          .foregroundStyle(isFilled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
          .accessibilityLabel(Text(isFilled ? "Contains content" : "Empty"))
      }
    }
    .accessibilityValue(Text(isFilled ? "Contains content" : "Empty"))
  }

  private func notesSection<Content: View>(
    _ title: String,
    isFilled: Bool,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    DisclosureGroup(isExpanded: isExpanded) {
      content()
        .padding(.top, 8)
    } label: {
      HStack {
        Text(title)
          .font(.title2.bold())
        Spacer()
        Image(systemName: isFilled ? "circle.fill" : "circle")
          .foregroundStyle(isFilled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
          .accessibilityLabel(Text(isFilled ? "Contains content" : "Empty"))
      }
    }
    .accessibilityValue(Text(isFilled ? "Contains content" : "Empty"))
  }

  private func makeAheadContent(_ makeAhead: String?) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let makeAhead {
        enrichmentText(makeAhead)
      }
    }
  }

  private func chefItUpContent(_ chefItUp: String?) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let chefItUp {
        enrichmentText(chefItUp)
      }
    }
  }

  private func enrichmentText(_ text: String) -> some View {
    let display = PlaybookEnrichmentText.displayText(for: text)

    return RecipeMarkdownText(display.text)
      .lineSpacing(display.hasBulletedLines ? 8 : 0)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func serveWithContent(_ items: [RecipeServeWith]) -> some View {
    EditableRowsSection(
      title: "Serve With",
      titleFont: .title3.bold(),
      editorLabel: "Serve With",
      items: items,
      itemText: \.title,
      addItem: model.createServeWith,
      addButtonLabel: "Add Serve With",
      updateItem: model.updateServeWith,
      deleteItem: { model.deleteServeWith($0.id) },
      reorderItems: { ids, destinationID in
        model.reorderServeWith(ids, destination: destinationID.map(ServeWithReorderDestination.before) ?? .end)
      }
    ) {
      ContentUnavailableView(
        "No Serve With Yet",
        systemImage: "fork.knife",
        description: Text("Add an accompaniment or save one from an AI handoff here.")
      )
    } itemContent: { item in
      VStack(alignment: .leading, spacing: 3) {
        Text(item.title)
          .font(.headline)
        if let note = item.note {
          Text(note)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
    } badge: { item in
      if item.provenance == .handAuthored {
        Label("Hand-authored", systemImage: "pencil")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func sectionMenu(for section: PlaybookSectionKind, isFilled: Bool) -> some View {
    return Menu {
      Button {
        Task {
          await handoffTransport.copyPrompt(for: .recipeSection(model.recipeID, section))
        }
      } label: {
        Label(
          isFilled ? "Hand off again" : "Hand off",
          systemImage: "sparkles.square.filled.on.square"
        )
      }

      Button {
        // A declined paste alert (or a non-string clipboard) yields nil. Hand the empty case to the
        // transport rather than returning silently, so the tap always produces visible feedback.
        let results = UIPasteboard.general.string.map { [$0] } ?? []
        Task {
          await handoffTransport.pastedResultsReceived(
            results,
            source: .recipeSection(model.recipeID, section)
          )
        }
      } label: {
        Label("Paste", systemImage: "doc.on.clipboard")
      }
      .disabled(!UIPasteboard.general.hasStrings)

      if section != .serveWith {
        Button(isFilled ? "Edit" : "Write manually") {
          editingSection = section
        }
      }

      // No per-section "Ask" here — the playbook opens an unseeded panel, and its Discuss ▾ switcher
      // is the one home for section-scoped discussion (ADR-0045 Amd 3).

      if isFilled {
        Button("Clear", role: .destructive) {
          clearingSection = section
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .frame(width: 44, height: 44)
        .contentShape(.rect)
    }
    .accessibilityLabel("\(section.title) actions")
  }

  private func commit(_ text: String, for section: PlaybookSectionKind) throws {
    switch section {
    case .makeAhead:
      try model.commitMakeAheadText(text)
    case .chefItUp:
      try model.commitChefItUpText(text)
    case .serveWith:
      try model.commitServeWithText(text)
    }
  }

  private func clear(_ section: PlaybookSectionKind) {
    switch section {
    case .makeAhead:
      model.clearMakeAheadButtonTapped()
    case .chefItUp:
      model.clearChefItUpButtonTapped()
    case .serveWith:
      model.clearServeWithButtonTapped()
    }
  }

  private func notesView(_ notes: [RecipeNote]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(notes) { note in
        VStack(alignment: .leading, spacing: 4) {
          Text(note.noteType.displayTitle)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
          RecipeMarkdownText(note.text)
        }
        .padding(.vertical, 4)
      }
    }
  }

  private func readerFeedbackView(_ notes: [RecipeNote]) -> some View {
    EditableRowsSection(
      title: "Reader Feedback",
      titleFont: .title3.bold(),
      editorLabel: "Reader Feedback",
      items: notes,
      itemText: \.text,
      updateItem: model.updateReaderFeedbackNote,
      deleteItem: model.deleteReaderFeedbackNote
    ) {
      EmptyView()
    } itemContent: { note in
      RecipeMarkdownText(note.text)
    }
  }
}

private extension PlaybookSectionKind {
  var title: String {
    switch self {
    case .makeAhead:
      "Make-ahead"
    case .chefItUp:
      "Chef It Up"
    case .serveWith:
      "Serve With"
    }
  }
}

private struct RecipePlaybookSectionEditorSheet: View {
  let section: PlaybookSectionKind
  let commit: (String) throws -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var draftText: String
  @State private var errorMessage: String?

  init(
    section: PlaybookSectionKind,
    initialText: String,
    commit: @escaping (String) throws -> Void
  ) {
    self.section = section
    self.commit = commit
    _draftText = State(initialValue: initialText)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Text("Review and edit this \(section.title) section before saving it.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

          VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            TextEditor(text: $draftText)
              .textInputAutocapitalization(.sentences)
              .autocorrectionDisabled(false)
              .frame(minHeight: 320)
          }
        }
        .padding()
      }
      .safeAreaPadding(.bottom)
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle("Edit \(section.title)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            save()
          }
          .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .alert("Could Not Save \(section.title)", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK") {}
    } message: {
      Text(errorMessage ?? "Something went wrong.")
    }
    .presentationDetents([.medium, .large])
  }

  private func save() {
    do {
      try commit(draftText)
      dismiss()
    } catch {
      errorMessage = String(describing: error)
    }
  }
}
