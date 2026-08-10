import SwiftUI
import YesChefCore

/// The Create Recipe destination (ADR-0053). One screen holding the **compose** material and the
/// **structured draft**, with the structured half immediately usable (D2 / OQ1): a cook typing from
/// memory just starts typing into the form; a cook with text to paste drops it in the compose box and
/// extracts. Nothing is written until Save (D4).
struct CreateRecipeView: View {
  let model: CreateRecipeModel
  /// Called with the saved recipe's ID so the app can jump to it in the library. The session is a
  /// resident sidebar destination, not a modal, so there is nothing to dismiss here.
  let onSaved: (Recipe.ID) -> Void
  @FocusState private var focusedIngredientSectionID: IngredientSection.ID?
  @FocusState private var focusedIngredientSectionNameID: IngredientSection.ID?

  var body: some View {
    @Bindable var model = model

    ScrollViewReader { proxy in
      Form {
        Section {
          StackedTextEditor(
            title: "Paste or type recipe text",
            text: $model.composeText,
            minHeight: 140
          )
          .onChange(of: model.composeText) {
            model.composeTextChanged()
          }
          PasteButton(payloadType: String.self) { strings in
            model.pastedTextReceived(strings)
          }
          .accessibilityLabel("Paste recipe text")
          Button {
            Task { await model.extractButtonTapped() }
          } label: {
            if model.isExtracting {
              ProgressView("Extracting recipe")
            } else {
              Label("Extract Recipe", systemImage: "sparkles")
            }
          }
          .disabled(!model.canExtract)

          if let extractionError = model.extractionError {
            Label {
              Text(extractionError)
            } icon: {
              Image(systemName: "exclamationmark.triangle")
            }
            .foregroundStyle(.orange)
          }
        } header: {
          Text("Source")
        } footer: {
          Text("Paste an unstructured recipe and Yes Chef will fill in the fields below without inventing anything. You can also just type into the form.")
        }

        if model.hasLabelActivity {
          CreateRecipeLabelSection(model: model)
        }

        if !model.extractionIssues.isEmpty {
          CreateRecipeIssueSection(issues: model.extractionIssues)
        }

        RecipeEditorFields(
          model: model.editorModel,
          proxy: proxy,
          focusedIngredientSectionID: $focusedIngredientSectionID,
          focusedIngredientSectionNameID: $focusedIngredientSectionNameID
        )
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if let focusedIngredientSectionID {
          IngredientFractionPillRow { fraction in
            model.editorModel.ingredientFractionTapped(fraction, sectionID: focusedIngredientSectionID)
            self.focusedIngredientSectionID = focusedIngredientSectionID
          }
          .padding(.horizontal)
          .background(.bar)
          .overlay(alignment: .top) {
            Divider()
          }
        }
      }
      .navigationTitle("Create Recipe")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Clear", role: .destructive) {
            model.reset()
          }
          .disabled(model.isEmpty || model.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            if let focusedIngredientSectionNameID {
              model.editorModel.ingredientSectionNameChanged(sectionID: focusedIngredientSectionNameID)
              self.focusedIngredientSectionNameID = nil
            }
            Task {
              if let recipeID = await model.saveButtonTapped() {
                onSaved(recipeID)
              }
            }
          } label: {
            if model.isSaving {
              ProgressView()
            } else {
              Text("Save")
            }
          }
          .disabled(model.isSavingDisabled)
        }
      }
      .onChange(of: focusedIngredientSectionNameID) { oldValue, newValue in
        guard let oldValue, oldValue != newValue else { return }
        model.editorModel.ingredientSectionNameChanged(sectionID: oldValue)
      }
      .alert("Could Not Save Recipe", isPresented: $model.isShowingError) {
        Button("OK") {}
      } message: {
        Text(model.errorMessage ?? "")
      }
      .confirmationDialog(
        "A recipe is already in progress.",
        isPresented: incomingPastedTextOfferBinding(for: model),
        titleVisibility: .visible
      ) {
        if case let .incomingPastedTextOffer(incomingText) = model.destination {
          Button("Use New Text") {
            model.acceptIncomingPastedText(incomingText.content)
          }
        }
        Button("Discard New Text", role: .destructive) {
          model.discardIncomingPastedText()
        }
        Button("Keep Current Recipe", role: .cancel) {
          model.discardIncomingPastedText()
        }
      } message: {
        Text("Use the incoming text as a new pasted source, or keep the recipe already in progress. Your current draft will not be replaced automatically.")
      }
    }
  }

  private func incomingPastedTextOfferBinding(for model: CreateRecipeModel) -> Binding<Bool> {
    Binding(
      get: {
        guard let destination = model.destination else { return false }
        if case .incomingPastedTextOffer = destination {
          return true
        } else {
          return false
        }
      },
      set: { isPresented in
        if !isPresented {
          model.discardIncomingPastedText()
        }
      }
    )
  }
}

/// Deterministic review cues from the last extraction. These are prompts for a cook to verify in the
/// editable fields, not model-provided confidence scores (ADR-0053 D6).
private struct CreateRecipeIssueSection: View {
  let issues: [RecipeExtractionIssue]

  var body: some View {
    Section("Review") {
      ForEach(issues) { issue in
        Label {
          Text(issue.message)
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(.orange)
      }
    }
  }
}

/// Assisted-label suggestions for a Create Recipe save (ADR-0053 OQ3): proposed after an extraction,
/// accepted by the cook before Save. Selection is pure until commit.
private struct CreateRecipeLabelSection: View {
  let model: CreateRecipeModel

  var body: some View {
    Section("Suggested Categories") {
      if model.isSuggestingLabels {
        ProgressView("Suggesting categories")
      }
      if let labelProposalError = model.labelProposalError {
        Label {
          Text(labelProposalError)
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(.orange)
      }
      if !model.suggestedLabels.isEmpty {
        Text("Tap a suggestion to include it when you save this recipe.")
          .font(.footnote)
          .foregroundStyle(.secondary)
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 132), alignment: .leading)],
          alignment: .leading,
          spacing: 8
        ) {
          ForEach(model.suggestedLabels) { suggestion in
            CreateRecipeLabelChip(
              suggestion: suggestion,
              isAccepted: model.isSuggestedLabelAccepted(suggestion)
            ) {
              model.suggestedLabelTapped(suggestion)
            }
          }
        }
      }
    }
  }
}

private struct CreateRecipeLabelChip: View {
  let suggestion: SuggestedLabel
  let isAccepted: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(
        suggestion.reviewTitle,
        systemImage: isAccepted ? "checkmark.circle.fill" : "plus.circle"
      )
      .font(.subheadline)
      .lineLimit(2)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(isAccepted ? Color.green.opacity(0.16) : Color.accentColor.opacity(0.12), in: Capsule())
    }
    .buttonStyle(.plain)
    .tint(isAccepted ? .green : .accentColor)
    .accessibilityAddTraits(isAccepted ? .isSelected : [])
  }
}
