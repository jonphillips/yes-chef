import SwiftUI
import UIKit
import WebExtractorKit
import YesChefCore

private enum ReaderFeedbackSheet: Identifiable {
  case review
  case promoteComments

  var id: String {
    switch self {
    case .review: "review-reader-feedback"
    case .promoteComments: "promote-comments"
    }
  }
}

struct RecipeCaptureView: View {
  @Environment(\.dismiss) private var dismiss
  let libraryModel: RecipeLibraryModel
  let model: RecipeCaptureModel
  @State private var readerFeedbackSheet: ReaderFeedbackSheet?
  @State private var readerFeedbackHandoffTransport = HandoffInAppTransport()

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
            model.pastedText(strings.first)
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
        RecipeCaptureReviewSections(
          model: model,
          draft: draft,
          readerFeedbackSheet: $readerFeedbackSheet,
          readerFeedbackHandoffTransport: readerFeedbackHandoffTransport
        )
      }
    }
    .sheet(item: $readerFeedbackSheet) { sheet in
      switch sheet {
      case .review:
        readerFeedbackCollectionSheet
      case .promoteComments:
        ReaderFeedbackPromotionSheet(
          comments: model.readerFeedbackComments,
          promote: { comment, commentNumber in
            _ = model.promoteReaderFeedbackComment(comment, commentNumber: commentNumber)
            readerFeedbackSheet = .review
          }
        )
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
    .handoffTransportAlert(readerFeedbackHandoffTransport)
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

  private var readerFeedbackCollectionSheet: some View {
    RecipeCollectionReviewSheet(
      items: model.readerFeedbackProposals.map { readerFeedbackReviewItem(for: $0) },
      committingItemID: nil,
      commit: { item, approvedText, usingSecondaryCommit in
        do {
          try await item.commit(approvedText, usingSecondaryCommit: usingSecondaryCommit)
          return true
        } catch {
          model.errorMessage = RecipeChatErrorText.describe(error)
          model.isShowingError = true
          return false
        }
      },
      discard: { item in
        guard let tip = model.readerFeedbackProposals.first(where: { $0.text == item.summary }) else { return }
        model.discardReaderFeedbackTip(tip)
      },
      discardAll: {
        for tip in model.readerFeedbackProposals {
          model.discardReaderFeedbackTip(tip)
        }
      },
      onEmpty: {
        readerFeedbackSheet = nil
      }
    )
  }

  private func readerFeedbackReviewItem(for tip: ReaderFeedbackTip) -> ChatApplyReviewItem {
    ChatApplyReviewItem(
      title: "Review Reader Feedback",
      summary: tip.text,
      editableTitle: "Reader Feedback",
      editableText: tip.text,
      supportingEvidenceTitle: tip.provenanceSummary,
      supportingEvidenceRows: tip.supportingEvidenceRows,
      commitTitle: "Accept",
      committingTitle: "Saving...",
      committedTitle: "Saved Reader Feedback",
      commit: { approvedText in
        model.acceptReaderFeedbackTip(tip, approvedText: approvedText)
      }
    )
  }
}

private struct RecipeCaptureReviewSections: View {
  @Bindable var model: RecipeCaptureModel
  let draft: WebRecipeCaptureDraft
  @Binding var readerFeedbackSheet: ReaderFeedbackSheet?
  let readerFeedbackHandoffTransport: HandoffInAppTransport

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

      if !model.readerFeedbackProposals.isEmpty
        || !model.readerFeedbackBlocks.isEmpty
        || !model.readerFeedbackComments.isEmpty
      {
        Section("Reader Feedback") {
          if !model.readerFeedbackProposals.isEmpty {
            Button {
              readerFeedbackSheet = .review
            } label: {
              Label(
                "Review \(model.readerFeedbackProposals.count) proposal\(model.readerFeedbackProposals.count == 1 ? "" : "s")",
                systemImage: "doc.text.magnifyingglass"
              )
            }
          }

          if !model.readerFeedbackComments.isEmpty {
            ReaderFeedbackHandoffControls(
              source: .readerFeedback(
                ReaderFeedbackHandoffContext(
                  comments: model.readerFeedbackComments,
                  sourceURL: page.sourceURL
                )
              ),
              transport: readerFeedbackHandoffTransport,
              receive: { review in
                model.stageReaderFeedback(
                  tips: review.tips,
                  comments: model.readerFeedbackComments,
                  unparsedLines: review.unparsedLines
                )
                readerFeedbackSheet = .review
              }
            )
            .buttonStyle(.bordered)
          }

          if !model.readerFeedbackHandoffEvidence.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("Couldn’t parse these returned lines")
                .font(.subheadline.weight(.semibold))
              Text(model.readerFeedbackHandoffEvidence.joined(separator: "\n"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
          }

          ForEach(model.readerFeedbackBlocks.indices, id: \.self) { index in
            TextField("Reader feedback", text: readerFeedbackBlockTextBinding(at: index), axis: .vertical)
              .lineLimit(2...8)
          }
          .onDelete { offsets in
            model.removeReaderFeedbackBlocks(atOffsets: offsets)
          }

          if !model.readerFeedbackComments.isEmpty {
            Button {
              readerFeedbackSheet = .promoteComments
            } label: {
              Label("Promote Comment", systemImage: "plus.bubble")
            }
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

private struct ReaderFeedbackPromotionSheet: View {
  @Environment(\.dismiss) private var dismiss
  let comments: [RawComment]
  let promote: (RawComment, Int) -> Void

  var body: some View {
    NavigationStack {
      List {
        ForEach(commentRows) { row in
          VStack(alignment: .leading, spacing: 8) {
            Label(row.subtitle, systemImage: "text.bubble")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            Text(row.comment.text)
              .font(.callout)
              .textSelection(.enabled)
            Button {
              promote(row.comment, row.commentNumber)
            } label: {
              Label("Review This Comment", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)
          }
          .padding(.vertical, 4)
        }
      }
      .navigationTitle("Promote Comment")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
      }
    }
  }

  private var commentRows: [ReaderFeedbackCommentRow] {
    comments.enumerated().map { index, comment in
      ReaderFeedbackCommentRow(commentNumber: index + 1, comment: comment)
    }
  }
}

private struct ReaderFeedbackCommentRow: Identifiable {
  var id: Int { commentNumber }
  var commentNumber: Int
  var comment: RawComment

  var subtitle: String {
    "Comment \(commentNumber) - \(comment.helpfulCount) helpful"
  }
}

private extension ReaderFeedbackTip {
  var provenanceSummary: String {
    "\(supportCount) \(supportCount == 1 ? "comment" : "comments") - \(provenanceKind.displayName)"
  }

  var provenanceSystemImage: String {
    switch provenanceKind {
    case .consensusDistilled: "person.2"
    case .singularPreserved: "person"
    }
  }

  var supportingEvidenceRows: [String] {
    backingComments.map { comment in
      "Comment \(comment.commentNumber) (\(comment.helpfulCount) helpful):\n\(comment.text)"
    }
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
