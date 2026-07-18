import SwiftUI
import YesChefCore

struct RecipePlaybookView: View {
  let model: RecipeDetailModel
  let handoffTransport: HandoffInAppTransport
  let ask: () -> Void

  @State private var isMakeAheadExpanded = true
  @State private var isNotesExpanded = true
  @State private var isChefItUpExpanded = true
  @State private var isServeWithExpanded = true
  @State private var isEditingReaderFeedback = false
  @State private var readerFeedbackDrafts: [RecipeNote.ID: String] = [:]
  @State private var editingSection: PlaybookSectionKind?

  var body: some View {
    let visibleNotes = model.visibleNotes
    let readerFeedbackNotes = visibleNotes.filter { $0.noteType == .readerFeedback }
    let otherNotes = visibleNotes.filter { $0.noteType != .readerFeedback }

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
        isFilled: !model.serveWithItems.isEmpty,
        isExpanded: $isServeWithExpanded
      ) {
        serveWithContent(model.serveWithItems)
      }
      if !model.learnings.isEmpty {
        LearningsSection(
          learnings: model.learnings,
          updateLearning: model.updateLearning,
          deleteLearning: model.deleteLearning
        )
      }
    }
    .sheet(item: $editingSection) { section in
      RecipePlaybookSectionEditorSheet(
        section: section,
        initialText: editableText(for: section),
        commit: { text in
          try commit(text, for: section)
        },
        clear: {
          clear(section)
        }
      )
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

  private func handoffButton(for section: PlaybookSectionKind) -> some View {
    Button {
      Task {
        await handoffTransport.copyPrompt(for: .recipeSection(model.recipeID, section))
      }
    } label: {
      Label("Hand off", systemImage: "sparkles.square.filled.on.square")
    }
    .buttonStyle(.borderedProminent)
  }

  private func redoButton(for section: PlaybookSectionKind) -> some View {
    Button {
      Task {
        await handoffTransport.copyPrompt(for: .recipeSection(model.recipeID, section))
      }
    } label: {
      Label("Hand off again", systemImage: "sparkles.square.filled.on.square")
    }
    .buttonStyle(.bordered)
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

  private func pasteResultButton(for section: PlaybookSectionKind) -> some View {
    PasteButton(payloadType: String.self) { results in
      Task {
        await handoffTransport.pastedResultsReceived(results, source: .recipeSection(model.recipeID, section))
      }
    }
    .accessibilityLabel("Paste result into \(section.title)")
    .buttonStyle(.bordered)
  }

  private func playbookSection<Content: View>(
    _ section: PlaybookSectionKind,
    isFilled: Bool,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    DisclosureGroup(isExpanded: isExpanded) {
      VStack(alignment: .leading, spacing: 12) {
        sectionToolbar(for: section, isFilled: isFilled)
        content()
      }
        .padding(.top, 8)
    } label: {
      HStack {
        Text(section.title)
          .font(.title2.bold())
        Spacer()
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
    let lines = text
      .split(whereSeparator: \.isNewline)
      .map(String.init)
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    return Text(
      lines.count > 1
        ? lines.map { "• \($0)" }.joined(separator: "\n")
        : text
    )
    .lineSpacing(lines.count > 1 ? 8 : 0)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func serveWithContent(_ items: [ServeWithItem]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(items) { item in
        HStack(alignment: .top, spacing: 10) {
          VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
              .font(.headline)
            if let note = item.note {
              Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 8)
          Button(role: .destructive) {
            model.removeServeWithButtonTapped(item.id)
          } label: {
            Image(systemName: "xmark.circle")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(Text("Remove \(item.title)"))
        }
      }
    }
  }

  @ViewBuilder
  private func sectionToolbar(for section: PlaybookSectionKind, isFilled: Bool) -> some View {
    HStack(spacing: 8) {
      if isFilled {
        editButton(for: section)
        redoButton(for: section)
        Menu {
          pasteResultButton(for: section)
          clearButton(for: section)
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      } else {
        handoffButton(for: section)
        pasteResultButton(for: section)
        Menu {
          writeManuallyButton(for: section)
          askMenuButton
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text("\(section.title) actions"))
  }

  private func editButton(for section: PlaybookSectionKind) -> some View {
    Button("Edit") {
      editingSection = section
    }
    .buttonStyle(.bordered)
  }

  private func writeManuallyButton(for section: PlaybookSectionKind) -> some View {
    Button("Write manually") {
      editingSection = section
    }
  }

  private func clearButton(for section: PlaybookSectionKind) -> some View {
    Button("Clear", role: .destructive) {
      clear(section)
    }
  }

  private var askMenuButton: some View {
    Button("Ask", action: ask)
  }

  private func editableText(for section: PlaybookSectionKind) -> String {
    switch section {
    case .makeAhead:
      model.makeAhead ?? ""
    case .chefItUp:
      model.chefItUp ?? ""
    case .serveWith:
      ServeWithPlan(
        items: model.serveWithItems.map { ServeWithSuggestion(title: $0.title, note: $0.note) }
      )
      .editableReviewText()
    }
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
          Text(note.text)
        }
        .padding(.vertical, 4)
      }
    }
  }

  private func readerFeedbackView(_ notes: [RecipeNote]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Reader Feedback")
          .font(.title3.bold())
        Spacer()
        Button(isEditingReaderFeedback ? "Done" : "Edit") {
          if isEditingReaderFeedback {
            commitReaderFeedbackEdits(notes)
          } else {
            readerFeedbackDrafts = Dictionary(
              uniqueKeysWithValues: notes.map { ($0.id, $0.text) }
            )
          }
          isEditingReaderFeedback.toggle()
        }
        .font(.callout)
      }
      ForEach(notes) { note in
        if isEditingReaderFeedback {
          VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: readerFeedbackDraftBinding(for: note))
              .frame(minHeight: 72)
              .padding(6)
              .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            Button(role: .destructive) {
              readerFeedbackDrafts[note.id] = nil
              model.deleteReaderFeedbackNote(note)
            } label: {
              Label("Delete", systemImage: "trash")
            }
            .font(.callout)
          }
          .padding(.vertical, 4)
        } else {
          Text(note.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
      }
    }
  }

  private func readerFeedbackDraftBinding(for note: RecipeNote) -> Binding<String> {
    Binding(
      get: { readerFeedbackDrafts[note.id] ?? note.text },
      set: { readerFeedbackDrafts[note.id] = $0 }
    )
  }

  private func commitReaderFeedbackEdits(_ notes: [RecipeNote]) {
    for note in notes {
      guard let draft = readerFeedbackDrafts[note.id] else { continue }
      model.updateReaderFeedbackNote(note, text: draft)
    }
    readerFeedbackDrafts = [:]
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
  let clear: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var draftText: String
  @State private var errorMessage: String?

  init(
    section: PlaybookSectionKind,
    initialText: String,
    commit: @escaping (String) throws -> Void,
    clear: @escaping () -> Void
  ) {
    self.section = section
    self.commit = commit
    self.clear = clear
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
        ToolbarItem(placement: .topBarLeading) {
          Button("Clear", role: .destructive) {
            clear()
            dismiss()
          }
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
