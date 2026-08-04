import Dependencies
import Observation
import SwiftUI
import YesChefCore

private enum LabelingBackfillError: LocalizedError {
  case recipeNotFound

  var errorDescription: String? { "The recipe is no longer available." }
}

struct RecipeSuggestedLabelsSheet: View {
  let model: RecipeDetailModel

  var body: some View {
    @Bindable var model = model

    NavigationStack {
      Form {
        if model.labelState.isSuggesting {
          Section {
            ProgressView("Suggesting labels")
          }
        } else if model.labelState.suggestions.isEmpty {
          ContentUnavailableView("No Suggestions", systemImage: "tag", description: Text("Try again after adding more recipe detail."))
        } else {
          Section("Suggested Categories") {
            Text("Choose the labels to add to this recipe.")
              .font(.footnote)
              .foregroundStyle(.secondary)
            ForEach(model.labelState.suggestions) { suggestion in
              Button {
                model.suggestedLabelTapped(suggestion)
              } label: {
                Label(
                  suggestion.reviewTitle,
                  systemImage: model.isSuggestedLabelAccepted(suggestion) ? "checkmark.circle.fill" : "circle"
                )
              }
              .tint(model.isSuggestedLabelAccepted(suggestion) ? .green : .accentColor)
            }
          }
        }
      }
      .navigationTitle("Suggest Labels")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { model.destination = nil }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add Selected") {
            Task { _ = await model.saveSuggestedLabelsButtonTapped() }
          }
          .disabled(!model.hasAcceptedSuggestedLabels || model.labelState.isSuggesting)
        }
      }
    }
  }
}

@Observable
@MainActor
final class RecipeLabelBackfillModel {
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.labelProposer) private var labelProposer
  @ObservationIgnored @Dependency(\.uuid) private var uuid

  let recipeIDs: [Recipe.ID]
  private var nextIndex = 0
  private var prefetched: [Recipe.ID: LabelProposal] = [:]
  var currentDetail: RecipeDetailData?
  var suggestions: [SuggestedLabel] = []
  var acceptedSuggestionIDs: Set<SuggestedLabel.ID> = []
  var isLoading = false
  var errorMessage: String?
  var isShowingError = false

  init(recipeIDs: [Recipe.ID]) {
    self.recipeIDs = recipeIDs
  }

  var currentRecipeID: Recipe.ID? { currentDetail?.recipe.id }
  var remainingCount: Int { recipeIDs.count - nextIndex + (currentDetail == nil ? 0 : 1) }

  func start() async {
    guard currentDetail == nil else { return }
    await loadNextRecipe()
  }

  func toggle(_ suggestion: SuggestedLabel) {
    if acceptedSuggestionIDs.contains(suggestion.id) {
      acceptedSuggestionIDs.remove(suggestion.id)
    } else {
      acceptedSuggestionIDs.insert(suggestion.id)
    }
  }

  func skipButtonTapped() async {
    await loadNextRecipe()
  }

  func saveButtonTapped() async {
    guard let recipeID = currentRecipeID else { return }
    let accepted = suggestions.filter { acceptedSuggestionIDs.contains($0.id) }
    do {
      if !accepted.isEmpty {
        let currentNow = now
        let makeUUID = uuid
        try await database.write { db in
          try RecipeRepository.reconcileSuggestedLabels(
            accepted,
            recipeID: recipeID,
            in: db,
            now: currentNow,
            uuid: { makeUUID() }
          )
        }
      }
      await loadNextRecipe()
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
    }
  }

  private func loadNextRecipe() async {
    guard nextIndex < recipeIDs.count else {
      currentDetail = nil
      suggestions = []
      acceptedSuggestionIDs = []
      return
    }
    let recipeID = recipeIDs[nextIndex]
    nextIndex += 1
    isLoading = true
    acceptedSuggestionIDs = []
    do {
      let loaded = try await database.read { db -> (RecipeDetailData, LabelVocabulary) in
        guard let detail = try RecipeRepository.fetchDetail(recipeID: recipeID, in: db) else {
          throw LabelingBackfillError.recipeNotFound
        }
        return (
          detail,
          LabelVocabulary(facets: try Facet.fetchAll(db), categories: try Category.fetchAll(db))
        )
      }
      currentDetail = loaded.0
      if let proposal = prefetched.removeValue(forKey: recipeID) {
        suggestions = proposal.accepted
      } else {
        suggestions = try await labelProposer(recipe: loaded.0.labelProposalRecipe, vocabulary: loaded.1)
          .accepted
      }
      prefetchNextRecipe()
    } catch is CancellationError {
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
    }
    isLoading = false
  }

  private func prefetchNextRecipe() {
    guard nextIndex < recipeIDs.count else { return }
    let recipeID = recipeIDs[nextIndex]
    Task { [weak self] in
      guard let self else { return }
      do {
        let loaded = try await database.read { db -> (RecipeDetailData, LabelVocabulary) in
          guard let detail = try RecipeRepository.fetchDetail(recipeID: recipeID, in: db) else {
            throw LabelingBackfillError.recipeNotFound
          }
          return (detail, LabelVocabulary(facets: try Facet.fetchAll(db), categories: try Category.fetchAll(db)))
        }
        let proposal = try await labelProposer(recipe: loaded.0.labelProposalRecipe, vocabulary: loaded.1)
        guard nextIndex < recipeIDs.count, recipeIDs[nextIndex] == recipeID else { return }
        prefetched[recipeID] = proposal
      } catch {
      }
    }
  }
}

struct RecipeLabelBackfillSheet: View {
  @State private var model: RecipeLabelBackfillModel
  let coverageView: RecipeFacetCoverageView

  init(recipeIDs: [Recipe.ID], coverageView: RecipeFacetCoverageView) {
    _model = State(initialValue: RecipeLabelBackfillModel(recipeIDs: recipeIDs))
    self.coverageView = coverageView
  }

  var body: some View {
    @Environment(\.dismiss) var dismiss

    NavigationStack {
      Group {
        if model.isLoading {
          ProgressView("Preparing recipe…")
        } else if let detail = model.currentDetail {
          Form {
            Section {
              Text(detail.recipe.title).font(.headline)
              Text("\(model.remainingCount) recipes remaining in \(coverageView.title.lowercased()).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section("Suggested Categories") {
              if model.suggestions.isEmpty {
                Text("No suggestions for this recipe.")
                  .foregroundStyle(.secondary)
              }
              ForEach(model.suggestions) { suggestion in
                Button { model.toggle(suggestion) } label: {
                  Label(
                    suggestion.reviewTitle,
                    systemImage: model.acceptedSuggestionIDs.contains(suggestion.id) ? "checkmark.circle.fill" : "circle"
                  )
                }
                .tint(model.acceptedSuggestionIDs.contains(suggestion.id) ? .green : .accentColor)
              }
            }
          }
        } else {
          ContentUnavailableView("Labeling Queue Complete", systemImage: "checkmark.circle", description: Text("This pass has no more recipes to review."))
        }
      }
      .navigationTitle("Label Recipes")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
        if model.currentDetail != nil {
          ToolbarItem(placement: .bottomBar) {
            Button("Skip") { Task { await model.skipButtonTapped() } }
          }
          ToolbarItem(placement: .bottomBar) {
            Spacer()
          }
          ToolbarItem(placement: .bottomBar) {
            Button("Save & Next") { Task { await model.saveButtonTapped() } }
          }
        }
      }
      .task { await model.start() }
      .alert("Couldn’t Label Recipe", isPresented: $model.isShowingError) {
        Button("OK") { model.errorMessage = nil }
      } message: {
        Text(model.errorMessage ?? "Something went wrong.")
      }
    }
  }
}
