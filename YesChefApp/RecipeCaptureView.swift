import SwiftUI
import UIKit
import WebExtractorKit
import YesChefCore

struct RecipeCaptureView: View {
  @Environment(\.dismiss) private var dismiss
  let libraryModel: RecipeLibraryModel
  let model: RecipeCaptureModel

  var body: some View {
    @Bindable var model = model

    Form {
      Section {
        TextField("Recipe URL", text: $model.urlText)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .onSubmit {
            Task { await model.fetchButtonTapped() }
          }

        HStack {
          PasteButton(payloadType: String.self) { strings in
            model.pastedText(strings.first ?? "")
          }
          .labelStyle(.titleAndIcon)

          Spacer()

          Button {
            model.isPresentingBrowser = true
          } label: {
            Label("Open in browser", systemImage: "safari")
          }
          .disabled(model.isCommitting)

          Button {
            Task { await model.fetchButtonTapped() }
          } label: {
            Label("Fetch", systemImage: "arrow.down.doc")
          }
          .disabled(!model.canFetch)
        }
      } footer: {
        if model.isFetching {
          ProgressView("Fetching recipe page")
        }
      }

      if let draft = model.draft {
        RecipeCaptureReviewSections(model: model, draft: draft)
      }
    }
    .navigationTitle("Capture Recipe")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          if model.cancelButtonTapped() {
            dismiss()
          }
        }
        .disabled(model.isCommitting)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button {
          Task {
            if let result = await model.commitButtonTapped() {
              libraryModel.webCaptureCompleted(result)
              dismiss()
            }
          }
        } label: {
          if model.isCommitting {
            ProgressView()
          } else {
            Text("Save")
          }
        }
        .disabled(!model.canCommit)
      }
    }
    .alert("Capture Error", isPresented: $model.isShowingError) {
      Button("OK") {}
    } message: {
      Text(model.errorMessage ?? "")
    }
    .confirmationDialog(
      "Discard this captured recipe?",
      isPresented: $model.isShowingDiscardConfirmation,
      titleVisibility: .visible
    ) {
      Button("Discard Capture", role: .destructive) {
        dismiss()
      }
      Button("Keep Editing", role: .cancel) {}
    } message: {
      Text("Your review edits have not been saved.")
    }
    .interactiveDismissDisabled(model.hasUnsavedReviewChanges)
    .fullScreenCover(isPresented: $model.isPresentingBrowser) {
      WebExtractorBrowser(
        startURL: model.browserStartURL,
        title: "Capture from Site",
        confirmLabel: "Capture",
        onExtract: { html, url in
          await model.ingestBrowserCapture(html: html, sourceURL: url)
        }
      )
    }
  }
}

private struct RecipeCaptureReviewSections: View {
  @Bindable var model: RecipeCaptureModel
  let draft: WebRecipeCaptureDraft
  @State private var presentedReaderFeedbackTip: ReaderFeedbackTip?

  private var page: ParsedRecipePage {
    draft.page
  }

  var body: some View {
    Group {
      Section("Review") {
        StackedTextField(title: "Title", text: $model.reviewTitle)
        StackedTextField(title: "Summary", text: $model.reviewSummary, axis: .vertical)
        StackedTextField(title: "Servings", text: $model.reviewServingsText)
        StackedTextField(title: "Total Time", text: $model.reviewTotalTimeText)
          .keyboardType(.numberPad)
        if draft.usedRenderedFallback {
          LabeledContent("Fetch") {
            Text("Rendered page")
          }
        }
        if draft.capturedInBrowser {
          LabeledContent("Fetch") {
            Text("Captured in browser")
          }
        }
      }

      Section("Source") {
        if let sourceURL = page.sourceURL {
          LabeledContent("URL") {
            Text(sourceURL.absoluteString)
              .textSelection(.enabled)
          }
        }
        if let publisherName = page.publisherName {
          LabeledContent("Source") {
            Text(publisherName)
          }
        }
        if let author = page.author {
          LabeledContent("Author") {
            Text(author)
          }
        }
      }

      if let heroImage {
        Section("Photo") {
          Image(uiImage: heroImage)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      }

      if !page.warnings.isEmpty {
        Section("Warnings") {
          Text(page.warnings.map(\.reviewTitle).joined(separator: "\n"))
            .foregroundStyle(.secondary)
        }
      }

      if !model.editorialBlocks.isEmpty {
        Section("Notes") {
          ForEach(model.editorialBlocks.indices, id: \.self) { index in
            VStack(alignment: .leading, spacing: 8) {
              Text(model.editorialBlocks[index].label)
                .font(.headline)
                .foregroundStyle(.secondary)
              TextField("Note", text: editorialBlockTextBinding(at: index), axis: .vertical)
                .lineLimit(3...8)
            }
            .padding(.vertical, 4)
          }
          .onDelete { offsets in
            model.removeEditorialBlocks(atOffsets: offsets)
          }
        }
      }

      if !model.readerFeedbackProposals.isEmpty || !model.readerFeedbackBlocks.isEmpty {
        Section("Reader Feedback") {
          ForEach(model.readerFeedbackProposals) { tip in
            VStack(alignment: .leading, spacing: 8) {
              Text(tip.text)
                .font(.callout)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
              HStack {
                Button(role: .cancel) {
                  model.discardReaderFeedbackTip(tip)
                } label: {
                  Label("Discard", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 8)

                Button {
                  presentedReaderFeedbackTip = tip
                } label: {
                  Label("Review", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
              }
            }
            .padding(.vertical, 4)
          }

          ForEach(model.readerFeedbackBlocks.indices, id: \.self) { index in
            TextField("Reader feedback", text: readerFeedbackBlockTextBinding(at: index), axis: .vertical)
              .lineLimit(2...8)
          }
          .onDelete { offsets in
            model.removeReaderFeedbackBlocks(atOffsets: offsets)
          }
        }
      }

      Section("Ingredients") {
        if ingredientText.isEmpty {
          Text("No ingredients found")
            .foregroundStyle(.secondary)
        } else {
          Text(ingredientText)
            .textSelection(.enabled)
        }
      }

      Section("Instructions") {
        if instructionText.isEmpty {
          Text("No instructions found")
            .foregroundStyle(.secondary)
        } else {
          Text(instructionText)
            .textSelection(.enabled)
        }
      }

      if let bodyText = page.bodyText, page.ingredientSections.isEmpty || page.instructionSections.isEmpty {
        Section("Page Text") {
          Text(bodyText)
            .lineLimit(8)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
    }
    .sheet(item: $presentedReaderFeedbackTip) { tip in
      let item = readerFeedbackReviewItem(for: tip)
      ChatApplyReviewSheet(
        item: item,
        isCommitting: false,
        commit: { approvedText in
          do {
            try await item.commit(approvedText)
            presentedReaderFeedbackTip = nil
          } catch {
            model.errorMessage = RecipeChatErrorText.describe(error)
            model.isShowingError = true
          }
        },
        discard: {
          model.discardReaderFeedbackTip(tip)
          presentedReaderFeedbackTip = nil
        }
      )
    }
  }

  private func readerFeedbackReviewItem(for tip: ReaderFeedbackTip) -> ChatApplyReviewItem {
    ChatApplyReviewItem(
      title: "Review Reader Feedback",
      summary: tip.text,
      editableTitle: "Reader Feedback",
      editableText: tip.text,
      commitTitle: "Accept",
      committingTitle: "Saving...",
      committedTitle: "Saved Reader Feedback",
      commit: { approvedText in
        model.acceptReaderFeedbackTip(tip, approvedText: approvedText)
      }
    )
  }

  private var ingredientText: String {
    page.ingredientSections
      .flatMap { section -> [String] in
        if let name = section.name {
          return [name] + section.lines
        }
        return section.lines
      }
      .joined(separator: "\n")
  }

  private var heroImage: UIImage? {
    guard let heroURL = page.imageURLs.first,
      let photo = page.processedImages[heroURL]
    else { return nil }
    return UIImage(data: photo.thumbnailData ?? photo.displayData)
  }

  private func editorialBlockTextBinding(at index: Int) -> Binding<String> {
    Binding {
      guard model.editorialBlocks.indices.contains(index) else { return "" }
      return model.editorialBlocks[index].text
    } set: { text in
      model.updateEditorialBlockText(text, at: index)
    }
  }

  private func readerFeedbackBlockTextBinding(at index: Int) -> Binding<String> {
    Binding {
      guard model.readerFeedbackBlocks.indices.contains(index) else { return "" }
      return model.readerFeedbackBlocks[index].text
    } set: { text in
      model.updateReaderFeedbackBlockText(text, at: index)
    }
  }

  private var instructionText: String {
    page.instructionSections
      .flatMap { section -> [String] in
        if let name = section.name {
          return [name] + section.steps
        }
        return section.steps
      }
      .joined(separator: "\n")
  }
}

private extension WebRecipeCaptureWarning {
  var reviewTitle: String {
    switch self {
    case .noStructuredRecipeData:
      "No structured recipe data found."
    case .truncatedStructuredData:
      "Structured recipe data appears truncated."
    case .untitledRecipe:
      "No title found."
    case .noIngredients:
      "No ingredients found."
    case .noInstructions:
      "No instructions found."
    }
  }
}
