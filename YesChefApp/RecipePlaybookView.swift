import SwiftUI
import YesChefCore

struct RecipePlaybookView: View {
  let model: RecipeDetailModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  @State private var isMakeAheadExpanded = false
  @State private var isRelatedRecipesExpanded = false
  @State private var isNotesExpanded = false
  @State private var isChefItUpExpanded = false
  @State private var isLearningsExpanded = false
  @State private var isDeliberationLogExpanded = false
  @State private var editingSection: PlaybookSectionKind?
  @State private var isWritingNote = false
  @State private var fullText: RecipePlaybookFullText?
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
      playbookSection(
        "Learnings",
        isFilled: !model.learnings.isEmpty,
        isExpanded: $isLearningsExpanded,
        showsActions: false,
        actions: { EmptyView() }
      ) {
        LearningsSection(
          learnings: model.learnings,
          showsTitle: false,
          showsEmptyPlaceholder: false,
          addLearning: model.createLearning,
          updateLearning: model.updateLearning,
          deleteLearning: model.deleteLearning,
          reorderLearnings: model.reorderLearnings
        )
      }
      RecipeServeWithStrip(
        model: model,
        items: serveWith,
        needsRepair: serveWithNeedsRepair,
        onRecipeSelected: onRecipeSelected
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
          clear: model.clearMakeAheadButtonTapped,
          commit: { text in
            try commit(text, for: section)
          }
        )
      case .chefItUp:
        RecipePlaybookSectionEditorSheet(
          section: section,
          initialText: model.chefItUp ?? "",
          clear: model.clearChefItUpButtonTapped,
          commit: { text in
            try commit(text, for: section)
          }
        )
      }
    }
    .sheet(isPresented: $isWritingNote) {
      RecipePlaybookNoteEditorSheet(save: model.createGeneralNote)
    }
    .sheet(item: $fullText) { item in
      NavigationStack {
        ScrollView {
          RecipeMarkdownText(item.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { fullText = nil }
          }
        }
      }
      .presentationDetents([.medium, .large])
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
      actions: { sectionEditButton(for: section, isFilled: isFilled) },
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
      // The disclosure symbol communicates both content status and expansion.
      HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.title2.bold())
            .foregroundStyle(.tint)
          if let preview {
            Text(preview)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 12)
        if showsActions {
          actions()
            .padding(.trailing, 12)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture { withAnimation { isExpanded.wrappedValue.toggle() } }
    }
    .disclosureGroupStyle(PlaybookDisclosureStyle(title: title, isFilled: isFilled))
    .accessibilityValue(Text(isFilled ? "Contains content" : "Empty"))
  }

  private func makeAheadContent(_ makeAhead: String?) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let makeAhead {
        enrichmentContent(makeAhead, title: "Make-ahead")
      } else {
        Button("Add make-ahead", systemImage: "plus") { editingSection = .makeAhead }
          .buttonStyle(.plain)
      }
    }
  }

  private func chefItUpContent(_ chefItUp: String?) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let chefItUp {
        enrichmentContent(chefItUp, title: "Chef It Up")
      } else {
        Button("Add an idea", systemImage: "plus") { editingSection = .chefItUp }
          .buttonStyle(.plain)
      }
    }
  }

  @ViewBuilder
  private func enrichmentContent(_ text: String, title: String) -> some View {
    if text.count > 280 {
      excerpt(text, title: title)
    } else {
      enrichmentText(text)
    }
  }

  private func excerpt(_ text: String, title: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      RecipeMarkdownText(String(text.prefix(260)).trimmingCharacters(in: .whitespacesAndNewlines) + "…")
        .frame(maxWidth: .infinity, alignment: .leading)
      Button("Read full") {
        fullText = RecipePlaybookFullText(title: title, text: text)
      }
      .font(.caption.weight(.semibold))
      .buttonStyle(.plain)
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

  private func sectionEditButton(for section: PlaybookSectionKind, isFilled: Bool) -> some View {
    Button { editingSection = section } label: {
      Image(symbol: .editRow)
    }
      .accessibilityLabel("\(isFilled ? "Edit" : "Write") \(section.title)")
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

  private func notesView(_ notes: [RecipeNote]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(notes) { note in
        VStack(alignment: .leading, spacing: 4) {
          Text(note.noteType.displayTitle)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
          if note.text.count > 280 {
            excerpt(note.text, title: note.noteType.displayTitle)
          } else {
            RecipeMarkdownText(note.text)
          }
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

private struct RecipePlaybookFullText: Identifiable {
  let id = UUID()
  let title: String
  let text: String
}

private struct RecipeServeWithStrip: View {
  let model: RecipeDetailModel
  let items: [RecipeServeWith]
  let needsRepair: Bool
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  @State private var editor: ServeWithItemEditorRoute?
  @State private var managingEditor: ServeWithItemEditorRoute?
  @State private var isManaging = false
  @State private var isConfirmingClear = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Serve With")
          .font(.title3.bold())
        Spacer()
        if !items.isEmpty {
          Button { isManaging = true } label: {
            Image(symbol: .editRow)
          }
          .accessibilityLabel("Edit Serve With")
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
                if let id = item.linkedRecipeID, model.detail?.resolvedServeWithRecipeIDs.contains(id) == true {
                  onRecipeSelected(RecipeDetailPresentation(recipeID: id))
                } else {
                  editor = .edit(item)
                }
              } label: {
                Label {
                  Text(item.title)
                } icon: {
                  if let id = item.linkedRecipeID, model.detail?.resolvedServeWithRecipeIDs.contains(id) == true {
                    Image(systemName: "link")
                  }
                }
                  .font(.subheadline.weight(.medium))
                  .lineLimit(1)
                  .padding(.horizontal, 12)
                  .frame(minHeight: 38)
                  .background(.quaternary.opacity(0.55), in: Capsule())
              }
              .buttonStyle(.plain)
              .accessibilityLabel(item.title)
              .accessibilityHint(item.linkedRecipeID.map { model.detail?.resolvedServeWithRecipeIDs.contains($0) == true } == true
                ? "Opens the linked recipe. Use Edit to change this accompaniment."
                : "Opens the full note and editing actions.")
              .contextMenu { Button("Edit") { editor = .edit(item) } }
              .accessibilityAction(named: "Edit") { editor = .edit(item) }
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
        model: model,
        save: { title, note, linkedRecipeID in
          if let item = route.item {
            return model.saveServeWith(item, title: title, note: note, linkedRecipeID: linkedRecipeID)
          }
          return model.createServeWith(title: title, note: note, linkedRecipeID: linkedRecipeID)
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
              editItem: { managingEditor = .edit($0) },
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
                Label { Text(item.title).font(.headline) } icon: {
                  if let id = item.linkedRecipeID, model.detail?.resolvedServeWithRecipeIDs.contains(id) == true {
                    Image(systemName: "link")
                  }
                }
                if let note = item.note {
                  Text(note).font(.callout).foregroundStyle(.secondary)
                }
              }
            } badge: { item in
              Label(
                item.provenance == .handAuthored ? "Hand-authored" : "Suggested",
                symbol: item.provenance == .handAuthored ? .editRow : AppSymbol("sparkles")
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            if !items.isEmpty {
              Button("Clear Serve With", role: .destructive) { isConfirmingClear = true }
                .frame(maxWidth: .infinity)
            }
          }
          .padding()
        }
        .sheet(item: $managingEditor) { route in
          ServeWithItemEditorSheet(
            item: route.item, model: model,
            save: { title, note, linkedRecipeID in
              guard let item = route.item else { return false }
              return model.saveServeWith(item, title: title, note: note, linkedRecipeID: linkedRecipeID)
            },
            delete: { if let item = route.item { model.deleteServeWith(item.id) } }
          )
        }
        .confirmationDialog("Clear Serve With?", isPresented: $isConfirmingClear) {
          Button("Clear Serve With", role: .destructive) {
            model.clearServeWithButtonTapped()
            isManaging = false
          }
        } message: {
          Text("This permanently clears the Serve With section. This cannot be undone.")
        }
        .navigationTitle("Edit Serve With")
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
  let model: RecipeDetailModel
  let save: (String, String?, Recipe.ID?) -> Bool
  let delete: () -> Void

  @State private var linkedRecipeID: Recipe.ID?
  @State private var linkedRecipeTitle: String?
  @State private var isPickingRecipe = false
  @State private var title: String
  @State private var note: String
  @State private var isConfirmingDelete = false

  init(item: RecipeServeWith?, model: RecipeDetailModel, save: @escaping (String, String?, Recipe.ID?) -> Bool, delete: @escaping () -> Void) {
    self.item = item
    self.model = model
    self.save = save
    self.delete = delete
    _linkedRecipeID = State(initialValue: item?.linkedRecipeID)
    _linkedRecipeTitle = State(initialValue: nil)
    _title = State(initialValue: item?.title ?? "")
    _note = State(initialValue: item?.note ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Accompaniment", text: $title)
        Section("Recipe") {
          if linkedRecipeID != nil {
            Text(linkedRecipeTitle ?? "Linked recipe")
            Button("Remove Link", role: .destructive) { linkedRecipeID = nil; linkedRecipeTitle = nil }
          } else {
            Button("Link a Recipe") {
              Task { if await model.loadServeWithPickerRows() { isPickingRecipe = true } }
            }
          }
        }
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
            if save(title, cleanNote.isEmpty ? nil : cleanNote, linkedRecipeID) { dismiss() }
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .task {
        if let linkedRecipeID {
          linkedRecipeTitle = await model.serveWithLinkedRecipeTitle(linkedRecipeID)
        }
      }
      .sheet(isPresented: $isPickingRecipe) {
        RelatedRecipePicker(
          recipeRows: model.relatedRecipePickerRows,
          excludedRecipeIDs: Set(model.serveWith.filter { $0.id != item?.id }.compactMap(\.linkedRecipeID)).union([model.recipeID]),
          link: { row in
            linkedRecipeID = row.id
            linkedRecipeTitle = row.title
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { title = row.title }
          }
        )
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
  let clear: () -> Void
  let commit: (String) throws -> Void
  let isFilled: Bool

  @Environment(\.dismiss) private var dismiss
  @State private var draftText: String
  @State private var errorMessage: String?
  @State private var isConfirmingClear = false

  init(
    section: PlaybookSectionKind,
    initialText: String,
    clear: @escaping () -> Void,
    commit: @escaping (String) throws -> Void
  ) {
    self.section = section
    self.clear = clear
    self.commit = commit
    self.isFilled = !initialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
          if isFilled {
            Button("Clear \(section.title)", role: .destructive) { isConfirmingClear = true }
              .frame(maxWidth: .infinity)
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
    .confirmationDialog("Clear \(section.title)?", isPresented: $isConfirmingClear) {
      Button("Clear \(section.title)", role: .destructive) {
        clear()
        dismiss()
      }
    } message: {
      Text("This permanently clears the \(section.title) section. This cannot be undone.")
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

private struct PlaybookDisclosureStyle: DisclosureGroupStyle {
  let title: String
  let isFilled: Bool

  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        configuration.label
        Button {
          withAnimation { configuration.isExpanded.toggle() }
        } label: {
          Image(systemName: isFilled ? "chevron.right.circle.fill" : "chevron.right.circle")
            .foregroundStyle(isFilled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(configuration.isExpanded ? "Collapse" : "Expand") \(title)")
        .accessibilityValue("\(configuration.isExpanded ? "Expanded" : "Collapsed"), \(isFilled ? "Contains content" : "Empty")")
      }
      if configuration.isExpanded { configuration.content }
    }
  }
}
