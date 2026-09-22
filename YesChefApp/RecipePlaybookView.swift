import SwiftUI
import UIKit
import YesChefCore

struct RecipePlaybookView: View {
  let model: RecipeDetailModel
  let handoffTransport: HandoffInAppTransport
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  var isComfortablePlaybookWidth = false
  var onReadFull: () -> Void = {}

  @State private var isMakeAheadExpanded = false
  @State private var isRelatedRecipesExpanded = false
  @State private var isNotesExpanded = false
  @State private var isChefItUpExpanded = false
  @State private var isDeliberationLogExpanded = false
  @State private var editingSection: PlaybookSectionKind?
  @State private var clearingSection: PlaybookSectionKind?
  @State private var isWritingNote = false
  var body: some View {
    let visibleNotes = model.visibleNotes
    let readerFeedbackNotes = visibleNotes.filter { $0.noteType == .readerFeedback }
    let otherNotes = visibleNotes.filter { $0.noteType != .readerFeedback }
    let serveWith = model.serveWith
    let serveWithNeedsRepair = model.serveWithRepairError != nil

    VStack(alignment: .leading, spacing: 18) {
      playbookSection(
        "Notes",
        isFilled: !visibleNotes.isEmpty,
        preview: notesPreview(visibleNotes),
        isExpanded: $isNotesExpanded,
        showsActions: false,
        actions: { EmptyView() }
      ) {
        notesContent(
          visibleNotes: visibleNotes,
          readerFeedbackNotes: readerFeedbackNotes,
          otherNotes: otherNotes
        )
      }
      playbookSection(
        .chefItUp,
        isFilled: model.chefItUp != nil,
        preview: firstMeaningfulLine(model.chefItUp),
        isExpanded: $isChefItUpExpanded
      ) {
        chefItUpContent(model.chefItUp)
      }
      playbookSection(
        .makeAhead,
        isFilled: model.makeAhead != nil,
        preview: firstMeaningfulLine(model.makeAhead),
        isExpanded: $isMakeAheadExpanded
      ) {
        makeAheadContent(model.makeAhead)
      }
      playbookSection(
        "Related Recipes",
        isFilled: !model.relatedRecipes.isEmpty,
        isExpanded: $isRelatedRecipesExpanded,
        showsActions: false,
        actions: { EmptyView() }
      ) {
        RecipeRelatedRecipeChoices(
          relatedRecipes: model.relatedRecipes,
          model: model,
          onRecipeSelected: onRecipeSelected,
          showsSectionTitle: false
        )
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
      LearningsSection(
        learnings: model.learnings,
        addLearning: model.createLearning,
        updateLearning: model.updateLearning,
        deleteLearning: model.deleteLearning,
        reorderLearnings: model.reorderLearnings
      )
      RecipeServeWithStrip(
        model: model,
        items: serveWith,
        needsRepair: serveWithNeedsRepair
      )
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
    .sheet(isPresented: $isWritingNote) {
      RecipePlaybookNoteEditorSheet(save: model.createGeneralNote)
    }
  }

  private func playbookSection<Content: View>(
    _ section: PlaybookSectionKind,
    isFilled: Bool,
    preview: String? = nil,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    playbookSection(
      section.title,
      isFilled: isFilled,
      preview: preview,
      isExpanded: isExpanded,
      showsActions: true,
      actions: { sectionMenu(for: section, isFilled: isFilled) },
      content: content
    )
  }

  private func playbookSection<Actions: View, Content: View>(
    _ title: String,
    isFilled: Bool,
    preview: String? = nil,
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
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.title2.bold())
          if let preview {
            Text(preview)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
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

  private func makeAheadContent(_ makeAhead: String?) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let makeAhead {
        enrichmentContent(makeAhead)
      } else {
        Button("Add make-ahead", systemImage: "plus") { editingSection = .makeAhead }
          .buttonStyle(.plain)
      }
    }
  }

  private func chefItUpContent(_ chefItUp: String?) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let chefItUp {
        enrichmentContent(chefItUp)
      } else {
        Button("Add an idea", systemImage: "plus") { editingSection = .chefItUp }
          .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private func enrichmentContent(_ text: String) -> some View {
    if isComfortablePlaybookWidth, text.count > 280 {
      VStack(alignment: .leading, spacing: 8) {
        RecipeMarkdownText(String(text.prefix(260)).trimmingCharacters(in: .whitespacesAndNewlines) + "…")
          .frame(maxWidth: .infinity, alignment: .leading)
        Button("Read full") { onReadFull() }
          .font(.caption.weight(.semibold))
          .buttonStyle(.plain)
      }
    } else {
      enrichmentText(text)
    }
  }

  private func enrichmentText(_ text: String) -> some View {
    let display = PlaybookEnrichmentText.displayText(for: text)

    return RecipeMarkdownText(display.text)
      .lineSpacing(display.hasBulletedLines ? 8 : 0)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func notesContent(
    visibleNotes: [RecipeNote],
    readerFeedbackNotes: [RecipeNote],
    otherNotes: [RecipeNote]
  ) -> some View {
    if visibleNotes.isEmpty {
      Button("Write a note", systemImage: "plus") { isWritingNote = true }
        .buttonStyle(.plain)
    } else if isComfortablePlaybookWidth,
      let longNote = visibleNotes.first(where: { $0.text.count > 280 }) {
      VStack(alignment: .leading, spacing: 8) {
        RecipeMarkdownText(String(longNote.text.prefix(260)).trimmingCharacters(in: .whitespacesAndNewlines) + "…")
        Button("Read full") { onReadFull() }
          .font(.caption.weight(.semibold))
          .buttonStyle(.plain)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      if !readerFeedbackNotes.isEmpty {
        readerFeedbackView(readerFeedbackNotes)
      }
      if !otherNotes.isEmpty {
        notesView(otherNotes)
      }
    }
  }

  private func notesPreview(_ notes: [RecipeNote]) -> String? {
    guard let firstNote = notes.first, let firstLine = firstMeaningfulLine(firstNote.text) else { return nil }
    let count = notes.count
    return "\(count) note\(count == 1 ? "" : "s") · \(firstLine)"
  }

  private func firstMeaningfulLine(_ text: String?) -> String? {
    guard let text else { return nil }
    let line = text
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
    guard var line else { return nil }
    while let first = line.first, ["#", "-", "*", "•", "–"].contains(String(first)) {
      line.removeFirst()
      line = line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard !line.isEmpty else { return nil }
    if line.count > 96 {
      return String(line.prefix(93)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
    return line
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

private struct RecipeServeWithStrip: View {
  let model: RecipeDetailModel
  let items: [RecipeServeWith]
  let needsRepair: Bool

  @State private var editor: ServeWithItemEditorRoute?
  @State private var isManaging = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Serve With")
          .font(.title3.bold())
        Spacer()
        if !items.isEmpty {
          Button {
            isManaging = true
          } label: {
            Image(systemName: "slider.horizontal.3")
              .frame(width: 44, height: 44)
          }
          .accessibilityLabel("Manage Serve With")
        }
      }

      if needsRepair {
        ServeWithRepairBanner(repair: model.repairServeWithButtonTapped)
      }

      if items.isEmpty {
        Button {
          editor = .add
        } label: {
          Label("Add", systemImage: "plus")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .background(.quaternary.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Serve With item")
      } else {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(items) { item in
              Button {
                editor = .edit(item)
              } label: {
                Text(item.title)
                  .font(.subheadline.weight(.medium))
                  .lineLimit(1)
                  .padding(.horizontal, 12)
                  .frame(minHeight: 38)
                  .background(.quaternary.opacity(0.55), in: Capsule())
              }
              .buttonStyle(.plain)
              .accessibilityLabel(item.title)
              .accessibilityHint("Opens the full note and editing actions.")
            }
            Button {
              editor = .add
            } label: {
              Label("Add", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(.quaternary.opacity(0.55), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Serve With item")
          }
        }
        .scrollIndicators(.visible)
        .overlay(alignment: .trailing) {
          LinearGradient(
            colors: [.clear, Color(uiColor: .systemBackground)],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: 12)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }
      }
    }
    .sheet(item: $editor) { route in
      ServeWithItemEditorSheet(
        item: route.item,
        save: { title, note in
          if let item = route.item {
            model.updateServeWith(item, title: title, note: note)
            return true
          }
          return model.createServeWith(title: title, note: note)
        },
        delete: {
          guard let item = route.item else { return }
          model.deleteServeWith(item.id)
        }
      )
    }
    .sheet(isPresented: $isManaging) {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if needsRepair {
              ServeWithRepairBanner(repair: model.repairServeWithButtonTapped)
            }
            EditableRowsSection(
              title: "Accompaniments",
              titleFont: .headline,
              editorLabel: "Accompaniment title",
              items: items,
              itemText: \.title,
              addItem: model.createServeWith,
              addButtonLabel: "Add Serve With",
              updateItem: { model.updateServeWith($0, text: $1) },
              deleteItem: { model.deleteServeWith($0.id) },
              reorderItems: { ids, destinationID in
                model.reorderServeWith(
                  ids,
                  destination: destinationID.map(ServeWithReorderDestination.before) ?? .end
                )
              }
            ) {
              Text("No Serve With items yet.")
                .foregroundStyle(.secondary)
            } itemContent: { item in
              VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline)
                if let note = item.note {
                  Text(note).font(.callout).foregroundStyle(.secondary)
                }
              }
            } badge: { item in
              Label(
                item.provenance == .handAuthored ? "Hand-authored" : "Suggested",
                systemImage: item.provenance == .handAuthored ? "pencil" : "sparkles"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
          .padding()
        }
        .navigationTitle("Manage Serve With")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { isManaging = false }
          }
        }
      }
      .presentationDetents([.medium, .large])
    }
  }
}

private enum ServeWithItemEditorRoute: Identifiable {
  case add
  case edit(RecipeServeWith)

  var id: String {
    switch self {
    case .add: "new"
    case let .edit(item): item.id.uuidString
    }
  }

  var item: RecipeServeWith? {
    guard case let .edit(item) = self else { return nil }
    return item
  }
}

private struct ServeWithItemEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  let item: RecipeServeWith?
  let save: (String, String?) -> Bool
  let delete: () -> Void

  @State private var title: String
  @State private var note: String
  @State private var isConfirmingDelete = false

  init(item: RecipeServeWith?, save: @escaping (String, String?) -> Bool, delete: @escaping () -> Void) {
    self.item = item
    self.save = save
    self.delete = delete
    _title = State(initialValue: item?.title ?? "")
    _note = State(initialValue: item?.note ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Accompaniment", text: $title)
        Section("Note") {
          TextEditor(text: $note)
            .frame(minHeight: 130)
        }
        if item != nil {
          Section {
            Button("Delete Serve With", role: .destructive) { isConfirmingDelete = true }
          }
        }
      }
      .navigationTitle(item == nil ? "Add Serve With" : item?.title ?? "Serve With")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if save(title, cleanNote.isEmpty ? nil : cleanNote) { dismiss() }
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .confirmationDialog("Delete this accompaniment?", isPresented: $isConfirmingDelete) {
        Button("Delete", role: .destructive) {
          delete()
          dismiss()
        }
        Button("Cancel", role: .cancel) {}
      }
    }
  }
}

private struct RecipePlaybookNoteEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  let save: (String) -> Bool
  @State private var text = ""

  var body: some View {
    NavigationStack {
      TextEditor(text: $text)
        .padding()
        .navigationTitle("New Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              if save(text) { dismiss() }
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
    }
  }
}

private struct ServeWithRepairBanner: View {
  let repair: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Label("Couldn't read Serve With", systemImage: "exclamationmark.triangle")
        .foregroundStyle(.secondary)
      Spacer(minLength: 8)
      Button("Repair", action: repair)
        .buttonStyle(.bordered)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Couldn't read Serve With — Repair")
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
