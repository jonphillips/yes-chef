import SwiftUI
import YesChefCore

struct RecipePlaybookView: View {
  let model: RecipeDetailModel
  let handoffTransport: HandoffInAppTransport

  @State private var isMakeAheadExpanded = true
  @State private var isNotesExpanded = true
  @State private var isChefItUpExpanded = true
  @State private var isServeWithExpanded = true
  @State private var isEditingReaderFeedback = false
  @State private var readerFeedbackDrafts: [RecipeNote.ID: String] = [:]

  var body: some View {
    let visibleNotes = model.visibleNotes
    let readerFeedbackNotes = visibleNotes.filter { $0.noteType == .readerFeedback }
    let otherNotes = visibleNotes.filter { $0.noteType != .readerFeedback }

    VStack(alignment: .leading, spacing: 18) {
      playbookSection(
        "Make-ahead",
        isFilled: model.makeAhead != nil,
        isExpanded: $isMakeAheadExpanded
      ) {
        makeAheadContent(model.makeAhead)
      }
      playbookSection(
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
        "Chef It Up",
        isFilled: model.chefItUp != nil,
        isExpanded: $isChefItUpExpanded
      ) {
        if let chefItUp = model.chefItUp {
          chefItUpContent(chefItUp)
        }
      }
      playbookSection(
        "Serve With",
        isFilled: !model.serveWithItems.isEmpty,
        isExpanded: $isServeWithExpanded
      ) {
        if !model.serveWithItems.isEmpty {
          serveWithContent(model.serveWithItems)
        }
      }
    }
  }

  private func playbookSection<Content: View>(
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
      HStack {
        Spacer()
        HandoffCopyPasteControls(
          source: .recipe(model.recipeID),
          transport: handoffTransport
        )
        .buttonStyle(.bordered)
        if makeAhead != nil {
          Button(role: .destructive) {
            model.clearMakeAheadButtonTapped()
          } label: {
            Label("Clear", systemImage: "xmark.circle")
          }
          .buttonStyle(.bordered)
        }
      }
      if let makeAhead {
        Text(makeAhead)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func chefItUpContent(_ chefItUp: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Spacer()
        Button(role: .destructive) {
          model.clearChefItUpButtonTapped()
        } label: {
          Label("Clear", systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
      }
      Text(chefItUp)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
