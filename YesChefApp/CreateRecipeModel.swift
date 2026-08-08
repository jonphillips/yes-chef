import Dependencies
import Foundation
import Observation
import YesChefCore

/// The Create Recipe destination's model (ADR-0053). It owns the **source material** — an ordered list
/// of what the cook supplied (D5) — and drives the two-tier text→recipe front-end into the shared
/// structured sink held by `editorModel` (D2). Nothing here is canonical until an explicit Save: the
/// session is transient, never persisted, never synced (D4). A failed extraction never destroys the
/// supplied material — the source stays in `sources` and the compose box, and a malformed model
/// response surfaces as a loud error rather than a partial recipe.
@Observable
@MainActor
final class CreateRecipeModel {
  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Dependency(\.labelProposer) private var labelProposer

  /// The structured half. A Create Recipe session opens with this immediately usable, so a cook typing
  /// a recipe from memory just starts typing (ADR-0053 D2 / OQ1).
  let editorModel = RecipeEditorModel(seededDraft: RecipeEditorDraft())

  /// The ordered source list (ADR-0053 D5). V1 records `pastedText` only; the list and the `kind` ship
  /// so images are an addition later, not a rewrite.
  private(set) var sources: [CreateRecipeSourceItem] = []
  var composeText = ""
  var isExtracting = false
  var extractionError: String?
  private(set) var extractionIssues: [RecipeExtractionIssue] = []
  private var composeSourceID: CreateRecipeSourceItem.ID?
  private var composeSourceIsLocked = false

  var isSaving = false
  var errorMessage: String?
  var isShowingError = false

  // Assisted labeling (ADR-0049), proposed pre-save from an extraction and accepted by the cook
  // (ADR-0053 OQ3). Selection stays pure until Save, exactly as capture does.
  private(set) var suggestedLabels: [SuggestedLabel] = []
  var acceptedSuggestedLabelIDs: Set<SuggestedLabel.ID> = []
  private(set) var isSuggestingLabels = false
  private(set) var labelProposalError: String?
  private var labelGeneration = 0

  var canExtract: Bool {
    !composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isExtracting && !isSaving
  }

  /// True when there is nothing for Clear to discard — an empty compose box, no recorded source, and a
  /// title-less draft. Drives whether the Clear affordance is enabled.
  var isEmpty: Bool {
    composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && sources.isEmpty
      && editorModel.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && editorModel.draft.ingredientSections.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      && editorModel.draft.instructionSections.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }

  /// Discards the whole in-progress session and returns to a blank form. The session is in-memory only
  /// (ADR-0053 D4), so this simply resets that memory — nothing persisted is touched.
  func reset() {
    composeText = ""
    sources = []
    isExtracting = false
    extractionError = nil
    extractionIssues = []
    composeSourceID = nil
    composeSourceIsLocked = false
    editorModel.applyExtractedDraft(RecipeEditorDraft())
    suggestedLabels = []
    acceptedSuggestedLabelIDs = []
    labelProposalError = nil
    isSuggestingLabels = false
    labelGeneration += 1
  }

  /// Save requires a title, matching the plain editor. The structured half is what gets saved, so its
  /// gate is authoritative.
  var isSavingDisabled: Bool {
    isSaving || editorModel.isSavingDisabled
  }

  var hasLabelActivity: Bool {
    isSuggestingLabels || !suggestedLabels.isEmpty || labelProposalError != nil
  }

  func isSuggestedLabelAccepted(_ suggestion: SuggestedLabel) -> Bool {
    acceptedSuggestedLabelIDs.contains(suggestion.id)
  }

  func suggestedLabelTapped(_ suggestion: SuggestedLabel) {
    if acceptedSuggestedLabelIDs.contains(suggestion.id) {
      acceptedSuggestedLabelIDs.remove(suggestion.id)
    } else {
      acceptedSuggestedLabelIDs.insert(suggestion.id)
    }
  }

  /// Records text entered into the compose field as typed source material. The value stays in the transient
  /// source list even if extraction fails. Before an extraction attempt, edits update that item rather than
  /// creating a row per keystroke; after an attempt, it is frozen so later corrections cannot rewrite the
  /// material that produced the reviewed draft (ADR-0053 D4/D5).
  func composeTextChanged() {
    guard !composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    if let composeSourceID,
      let index = sources.firstIndex(where: { $0.id == composeSourceID }) {
      if sources[index].content == composeText {
        return
      }
      if !composeSourceIsLocked {
        sources[index].content = composeText
        return
      }
    }

    let source = CreateRecipeSourceItem(id: uuid(), kind: .typedText, content: composeText)
    sources.append(source)
    composeSourceID = source.id
    composeSourceIsLocked = false
  }

  /// Accepts user-initiated clipboard text as its own pasted source item. Editing it remains possible in the
  /// compose field, but the source list preserves that it arrived through the paste path.
  func pastedTextReceived(_ strings: [String]) {
    guard let text = strings.first, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let source = CreateRecipeSourceItem(id: uuid(), kind: .pastedText, content: text)
    sources.append(source)
    composeSourceID = source.id
    composeSourceIsLocked = false
    composeText = text
  }

  /// Runs the two-tier front-end over the compose box (ADR-0051 D4): deterministic schema.org first,
  /// the faithful LLM engine otherwise. On success the structured half is (re)seeded and the source is
  /// recorded; on failure the material is preserved and the error is shown.
  func extractButtonTapped() async {
    let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isExtracting else { return }
    composeTextChanged()
    composeSourceIsLocked = true
    isExtracting = true
    extractionError = nil
    defer { isExtracting = false }

    do {
      let extraction = try await CreateRecipeExtraction.extract(text: text)
      let makeUUID = uuid
      let extractedDraft = extraction.editorDraft(uuid: { makeUUID() })
      editorModel.applyExtractedDraft(extractedDraft)
      extractionIssues = RecipeExtractionIssueDetector.issues(in: extraction, sources: sources)
      proposeLabels(for: extraction)
    } catch {
      extractionError = RecipeChatErrorText.describe(error)
    }
  }

  /// Commits the reviewed draft (`save(draft:)` — the app-authored identity class, ADR-0051 Amd 1) and
  /// applies the labels the cook accepted, both in one write so a save is all-or-nothing.
  func saveButtonTapped() async -> Recipe.ID? {
    guard !isSavingDisabled else { return nil }
    isSaving = true
    defer { isSaving = false }

    let draft = editorModel.draft
    let accepted = acceptedLabelSuggestions
    let saveDate = now
    let makeUUID = uuid

    do {
      let recipeID = try await database.write { db in
        let recipeID = try RecipeRepository.save(draft: draft, in: db, now: saveDate, uuid: { makeUUID() })
        try RecipeRepository.reconcileSuggestedLabels(
          accepted,
          recipeID: recipeID,
          in: db,
          now: saveDate,
          uuid: { makeUUID() }
        )
        return recipeID
      }
      return recipeID
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return nil
    }
  }

  private var acceptedLabelSuggestions: [SuggestedLabel] {
    suggestedLabels.filter { acceptedSuggestedLabelIDs.contains($0.id) }
  }

  private func proposeLabels(for extraction: RecipeExtraction) {
    suggestedLabels = []
    acceptedSuggestedLabelIDs = []
    labelProposalError = nil
    isSuggestingLabels = true
    labelGeneration += 1
    let generation = labelGeneration
    let proposalRecipe = LabelProposalRecipe(
      title: extraction.title?.nonEmptyValue ?? "Untitled Recipe",
      summary: extraction.summary,
      publisherName: extraction.publisherName,
      ingredientLines: extraction.ingredientSections.flatMap(\.lines)
    )

    Task { [weak self] in
      guard let self else { return }
      do {
        let vocabulary = try await database.read { db in
          LabelVocabulary(
            facets: try Facet.fetchAll(db),
            categories: try Category.fetchAll(db)
          )
        }
        let proposal = try await labelProposer(recipe: proposalRecipe, vocabulary: vocabulary)
        guard labelGeneration == generation else { return }
        suggestedLabels = proposal.accepted
      } catch is CancellationError {
      } catch {
        guard labelGeneration == generation else { return }
        labelProposalError = RecipeChatErrorText.describe(error)
      }
      if labelGeneration == generation {
        isSuggestingLabels = false
      }
    }
  }
}

private extension String {
  var nonEmptyValue: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
