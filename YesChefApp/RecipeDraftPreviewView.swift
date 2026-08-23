import SwiftUI
import YesChefCore

/// A read-only rendering of the unsaved Create Recipe draft. It deliberately consumes only the
/// transient editor value so opening Preview cannot create or mutate a persisted recipe (ADR-0053 D4).
struct RecipeDraftPreviewView: View {
  @Environment(\.dismiss) private var dismiss
  let draft: RecipeEditorDraft

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let data = heroPhotoData {
          RecipeHeroPhotoPreview(data: data)
        }

        header
        timingAndYield
        ingredients
        instructions
        proseSections
        sourceMetadata
        categories
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("Preview")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
      }
    }
  }

  @ViewBuilder
  private var header: some View {
    if let title = draft.title.previewNonEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.largeTitle.bold())
        if let subtitle = draft.subtitle.previewNonEmpty {
          Text(subtitle)
            .font(.title3.weight(.medium))
            .foregroundStyle(.secondary)
        }
        if let summary = draft.summary.previewNonEmpty {
          RecipeMarkdownText(summary)
            .font(.body)
        }
      }
    }
  }

  @ViewBuilder
  private var timingAndYield: some View {
    let values = [
      draft.servingsText.previewNonEmpty.map { DraftPreviewMetadata(label: "Servings", value: $0) },
      draft.yieldText.previewNonEmpty.map { DraftPreviewMetadata(label: "Yield", value: $0) },
      draft.prepTimeMinutes > 0 ? DraftPreviewMetadata(label: "Prep", value: "\(draft.prepTimeMinutes) min") : nil,
      draft.cookTimeMinutes > 0 ? DraftPreviewMetadata(label: "Cook", value: "\(draft.cookTimeMinutes) min") : nil,
    ].compactMap { $0 }

    if !values.isEmpty {
      DraftPreviewBlock(title: "Timing and Yield") {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading) {
          ForEach(values) { value in
            Label(value.value, systemImage: value.systemImage)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var ingredients: some View {
    let sections = draft.ingredientSections.filter { section in
      section.name.previewNonEmpty != nil || !ingredientLines(for: section).isEmpty
    }

    if !sections.isEmpty {
      DraftPreviewBlock(title: "Ingredients") {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 6) {
              if let name = section.name.previewNonEmpty {
                Text(name)
                  .font(.headline)
              }
              ForEach(ingredientLines(for: section)) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                  Text("•")
                    .foregroundStyle(.secondary)
                  IngredientLineText(line.text)
                }
              }
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var instructions: some View {
    let sections = draft.instructionSections.filter { section in
      section.name.previewNonEmpty != nil || !instructionSteps(for: section).isEmpty
    }

    if !sections.isEmpty {
      DraftPreviewBlock(title: "Instructions") {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 8) {
              if let name = section.name.previewNonEmpty {
                Text(name)
                  .font(.headline)
              }
              ForEach(instructionSteps(for: section)) { step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                  Text(step.number)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, alignment: .leading)
                  RecipeMarkdownText(step.text)
                }
              }
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var proseSections: some View {
    if draft.makeAhead.previewNonEmpty != nil
      || draft.chefItUp.previewNonEmpty != nil
      || draft.noteText.previewNonEmpty != nil
    {
      VStack(alignment: .leading, spacing: 16) {
        if let makeAhead = draft.makeAhead.previewNonEmpty {
          DraftPreviewProse(title: "Make-ahead", text: makeAhead)
        }
        if let chefItUp = draft.chefItUp.previewNonEmpty {
          DraftPreviewProse(title: "Chef it up", text: chefItUp)
        }
        if let notes = draft.noteText.previewNonEmpty {
          DraftPreviewProse(title: "Notes", text: notes)
        }
      }
    }
  }

  @ViewBuilder
  private var sourceMetadata: some View {
    let values = [
      DraftPreviewMetadata(label: "Source", value: draft.sourceName),
      DraftPreviewMetadata(label: "Author", value: draft.sourceAuthor),
      DraftPreviewMetadata(label: "Publication", value: draft.sourcePublicationName),
      DraftPreviewMetadata(label: "Book", value: draft.sourceBookTitle),
      DraftPreviewMetadata(label: "Page", value: draft.sourcePageNumber),
    ].filter { $0.value.previewNonEmpty != nil }

    if !values.isEmpty || draft.sourceURL.previewNonEmpty != nil || draft.sourceNotes.previewNonEmpty != nil {
      DraftPreviewBlock(title: "Source") {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(values) { value in
            DraftPreviewMetadataRow(metadata: value)
          }
          if let urlString = draft.sourceURL.previewNonEmpty {
            if let url = URL(string: urlString) {
              Link(urlString, destination: url)
            } else {
              Text(urlString)
            }
          }
          if let notes = draft.sourceNotes.previewNonEmpty {
            RecipeMarkdownText(notes)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var categories: some View {
    let values = [
      DraftPreviewMetadata(label: "Categories", value: draft.categoryNames),
      DraftPreviewMetadata(label: "Cuisine", value: draft.cuisine),
      DraftPreviewMetadata(label: "Course", value: draft.course),
    ].filter { $0.value.previewNonEmpty != nil }

    if !values.isEmpty {
      DraftPreviewBlock(title: "Categories") {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(values) { value in
            DraftPreviewMetadataRow(metadata: value)
          }
        }
      }
    }
  }

  private var heroPhotoData: Data? {
    let heroPhoto = draft.pendingPhotos.last { $0.kind == .hero }
    return heroPhoto?.processedPhoto.thumbnailData ?? heroPhoto?.processedPhoto.displayData
  }

  private func ingredientLines(for section: RecipeEditorIngredientSectionDraft) -> [DraftPreviewLine] {
    let drafts = section.lineDrafts.sorted { $0.sortOrder < $1.sortOrder }
    if !drafts.isEmpty {
      return drafts.compactMap { line in
        guard let text = line.originalText.previewNonEmpty else { return nil }
        return DraftPreviewLine(id: line.id.uuidString, text: text)
      }
    }
    return section.text
      .components(separatedBy: .newlines)
      .enumerated()
      .compactMap { index, text in
        guard let text = text.previewNonEmpty else { return nil }
        return DraftPreviewLine(id: "\(section.id.uuidString)-\(index)", text: text)
      }
  }

  private func instructionSteps(for section: RecipeEditorInstructionSectionDraft) -> [DraftPreviewStep] {
    let nonEmptySteps: [(index: Int, text: String)] = section.text
      .components(separatedBy: .newlines)
      .enumerated()
      .compactMap { index, text in
        guard let text = text.previewNonEmpty else { return nil }
        return (index: index, text: text)
      }

    return nonEmptySteps.enumerated().map { number, step in
      DraftPreviewStep(
        id: "\(section.id.uuidString)-\(step.index)",
        number: "\(number + 1)",
        text: step.text
      )
    }
  }
}

private struct DraftPreviewBlock<Content: View>: View {
  let title: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.title3.weight(.semibold))
      content()
    }
  }
}

private struct DraftPreviewProse: View {
  let title: String
  let text: String

  var body: some View {
    DraftPreviewBlock(title: title) {
      RecipeMarkdownText(text)
    }
  }
}

private struct DraftPreviewMetadata: Identifiable {
  let label: String
  let value: String

  var id: String { label }

  var systemImage: String {
    switch label {
    case "Servings": "person.2"
    case "Prep", "Cook": "clock"
    default: "info.circle"
    }
  }
}

private struct DraftPreviewMetadataRow: View {
  let metadata: DraftPreviewMetadata

  var body: some View {
    LabeledContent(metadata.label) {
      Text(metadata.value.previewNonEmpty ?? metadata.value)
        .multilineTextAlignment(.trailing)
    }
  }
}

private struct DraftPreviewLine: Identifiable {
  let id: String
  let text: String
}

private struct DraftPreviewStep: Identifiable {
  let id: String
  let number: String
  let text: String
}

private extension String {
  var previewNonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
