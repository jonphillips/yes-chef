import SwiftUI
import YesChefCore

struct RecipeAdjustmentReviewView: View {
  let review: RecipeAdjustmentReviewState
  let overwrite: (RecipeAdjustmentReviewState) -> Bool
  let keepAsVariation: (RecipeAdjustmentReviewState, String) -> Bool

  @Environment(\.dismiss) private var dismiss
  @State private var segment = Segment.ingredients
  @State private var variationName: String
  @State private var isOverwriting = false
  @State private var isKeepingVariation = false

  init(
    review: RecipeAdjustmentReviewState,
    overwrite: @escaping (RecipeAdjustmentReviewState) -> Bool,
    keepAsVariation: @escaping (RecipeAdjustmentReviewState, String) -> Bool
  ) {
    self.review = review
    self.overwrite = overwrite
    self.keepAsVariation = keepAsVariation
    _variationName = State(initialValue: review.defaultVariationName)
  }

  private enum Segment: String, CaseIterable, Identifiable {
    case ingredients = "Ingredients"
    case method = "Method"

    var id: String { rawValue }
  }

  private var comparison: IngredientComparison {
    WorkbenchCompare.ingredientComparison(
      working: review.currentDetail,
      candidates: [review.proposedDetail]
    )
  }

  var body: some View {
    NavigationStack {
      Group {
        switch segment {
        case .ingredients:
          VStack(spacing: 0) {
            variationNameField
            Divider()
            IngredientMatrixView(comparison: comparison)
          }
        case .method:
          VStack(spacing: 0) {
            variationNameField
            Divider()
            MethodBeforeAfterView(
              current: review.currentDetail,
              proposed: review.proposedDetail,
              methodNote: review.proposal.methodNote
            )
          }
        }
      }
      .navigationTitle("Adjust Recipe")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Picker("Review", selection: $segment) {
            ForEach(Segment.allCases) { segment in
              Text(segment.rawValue).tag(segment)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 260)
        }
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
          .disabled(isBusy)
        }
        ToolbarItemGroup(placement: .confirmationAction) {
          Button {
            keepAsVariationButtonTapped()
          } label: {
            if isKeepingVariation {
              Label("Keeping", systemImage: "hourglass")
            } else {
              Label("Keep as Variation", systemImage: "square.stack.3d.up")
            }
          }
          .disabled(isBusy || variationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

          Button {
            overwriteButtonTapped()
          } label: {
            if isOverwriting {
              Label("Overwriting", systemImage: "hourglass")
            } else {
              Label("Overwrite", systemImage: "checkmark.circle")
            }
          }
          .disabled(isBusy)
        }
      }
    }
  }

  private var isBusy: Bool {
    isOverwriting || isKeepingVariation
  }

  private var variationNameField: some View {
    LabeledContent {
      TextField("Variation name", text: $variationName)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 360)
    } label: {
      Label("Variation", systemImage: "square.stack.3d.up")
        .font(.subheadline.bold())
    }
    .padding()
    .background(.bar)
  }

  private func keepAsVariationButtonTapped() {
    isKeepingVariation = true
    if keepAsVariation(review, variationName) {
      dismiss()
    } else {
      isKeepingVariation = false
    }
  }

  private func overwriteButtonTapped() {
    isOverwriting = true
    if overwrite(review) {
      dismiss()
    } else {
      isOverwriting = false
    }
  }
}

private extension RecipeAdjustmentReviewState {
  var defaultVariationName: String {
    // A proposal summary can be a sentence. A concise default keeps the active
    // version readable if the cook chooses to keep it without renaming first.
    "Variation"
  }
}

private struct MethodBeforeAfterView: View {
  let current: RecipeDetailData
  let proposed: RecipeDetailData
  let methodNote: String?

  var body: some View {
    ScrollView {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 0) {
          methodColumn(title: "Current", detail: current)
          Divider()
          methodColumn(title: "Proposed", detail: proposed, methodNote: methodNote)
        }
        VStack(alignment: .leading, spacing: 18) {
          methodColumn(title: "Current", detail: current)
          Divider()
          methodColumn(title: "Proposed", detail: proposed, methodNote: methodNote)
        }
      }
      .padding()
    }
  }

  private func methodColumn(title: String, detail: RecipeDetailData, methodNote: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title)
        .font(.headline)
      let steps = detail.instructionSteps.sorted { $0.sortOrder < $1.sortOrder }
      if steps.isEmpty {
        Text("No instructions")
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
          HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
              .font(.caption.bold())
              .foregroundStyle(.white)
              .frame(width: 24, height: 24)
              .background(Circle().fill(Color.accentColor))
            Text(step.text)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      if let methodNote = methodNote?.trimmingCharacters(in: .whitespacesAndNewlines), !methodNote.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Label("Method note", systemImage: "note.text")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
          Text(methodNote)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .padding(.horizontal, 8)
  }
}
