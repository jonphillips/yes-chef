import SwiftUI
import UIKit
import YesChefCore

struct RecipeVariationChoices: View {
  let variations: [RecipeVariation]
  let activeVariationID: RecipeVariation.ID?
  let model: RecipeDetailModel
  let handoffTransport: HandoffInAppTransport
  @Binding var promotingVariation: RecipeVariation?
  @Binding var splittingOffVariation: RecipeVariation?
  @Binding var splitOffTitleDraft: String

  @State private var renamingVariation: RecipeVariation?
  @State private var variationNameDraft = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(variations) { variation in
        variationRow(variation)
      }
    }
    .alert(
      "Rename Variation",
      isPresented: Binding(
        get: { renamingVariation != nil },
        set: { if !$0 { renamingVariation = nil } }
      )
    ) {
      TextField("Name", text: $variationNameDraft)
      Button("Save") {
        if let variation = renamingVariation {
          model.renameVariation(variation.id, to: variationNameDraft)
        }
        renamingVariation = nil
      }
      Button("Cancel", role: .cancel) {
        renamingVariation = nil
      }
    } message: {
      Text("Give this variation a new name.")
    }
    .alert(
      "Split Off as Recipe",
      isPresented: Binding(
        get: { splittingOffVariation != nil },
        set: { if !$0 { splittingOffVariation = nil } }
      )
    ) {
      TextField("Recipe name", text: $splitOffTitleDraft)
      Button("Save") {
        guard let variation = splittingOffVariation else { return }
        let title = splitOffTitleDraft
        splittingOffVariation = nil
        Task { await model.splitVariationOffButtonTapped(variation.id, title: title) }
      }
      Button("Cancel", role: .cancel) {
        splittingOffVariation = nil
      }
    } message: {
      Text("This creates a new standalone recipe and removes the variation.")
    }
  }

  private func variationRow(_ variation: RecipeVariation) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Button {
        model.activeVariationSelectionChanged(variation.id)
      } label: {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: variation.id == activeVariationID ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(variation.id == activeVariationID ? .tint : .secondary)
            .frame(minWidth: 20)
            .padding(.top, 2)
          VStack(alignment: .leading, spacing: 3) {
            Text(variation.name)
              .font(.headline)
              .foregroundStyle(.primary)
            if let note = variation.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
              Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(variation.name)
      .accessibilityValue(variation.id == activeVariationID ? "Selected" : "Not selected")

      Menu {
        Button("Hand Off") {
          Task {
            await handoffTransport.copyPrompt(
              for: .recipeAdjustment(model.recipeID, variationID: variation.id)
            )
          }
        }
        Button("Paste") {
          let results = UIPasteboard.general.string.map { [$0] } ?? []
          Task {
            await handoffTransport.pastedResultsReceived(
              results,
              source: .recipeAdjustment(model.recipeID, variationID: variation.id)
            )
          }
        }
        .disabled(!UIPasteboard.general.hasStrings)
        Divider()
        Button("Rename") {
          variationNameDraft = variation.name
          renamingVariation = variation
        }
        Button("Edit Variation") {
          model.editVariationButtonTapped(variation.id)
        }
        Button("Split Off as Recipe") {
          splitOffTitleDraft = variation.name
          splittingOffVariation = variation
        }
        Button("Promote to Base") {
          promotingVariation = variation
        }
      } label: {
        Label("\(variation.name) actions", systemImage: "ellipsis.circle")
          .labelStyle(.iconOnly)
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("\(variation.name) actions")
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .contain)
  }
}

/// The variation the cook chose to promote, carried into the second (removal) dialog so it
/// never has to be guessed from the active selection. Promoting a *non-active* variation that
/// needs a removal confirmation must act on the promoted variation, not on whatever is active.
struct PendingVariationRemoval: Equatable {
  let variation: RecipeVariation
  let names: [String]
}

private struct RecipeVariationPromotionPresentation: ViewModifier {
  let model: RecipeDetailModel
  @Binding var promotingVariation: RecipeVariation?
  @Binding var pendingVariationRemoval: PendingVariationRemoval?

  func body(content: Content) -> some View {
    content
      .confirmationDialog(
        "Promote this variation to the base recipe?",
        isPresented: Binding(
          get: { promotingVariation != nil },
          set: { if !$0 { promotingVariation = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Promote to Base") {
          guard let variation = promotingVariation else { return }
          Task {
            switch await model.promoteVariationButtonTapped(variation.id) {
            case .promoted:
              promotingVariation = nil
            case let .needsConfirmation(names):
              // Capture the promoted variation with its names; the first dialog's
              // isPresented setter is about to nil `promotingVariation` on dismissal.
              pendingVariationRemoval = PendingVariationRemoval(variation: variation, names: names)
              promotingVariation = nil
            case nil:
              break
            }
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("The current base will stay available as a variation.")
      }
      .confirmationDialog(
        "Remove variations that cannot follow the new base?",
        isPresented: Binding(
          get: { pendingVariationRemoval != nil },
          set: { if !$0 { pendingVariationRemoval = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Promote and Remove Variations", role: .destructive) {
          guard let pending = pendingVariationRemoval else { return }
          Task {
            _ = await model.promoteVariationButtonTapped(
              pending.variation.id,
              confirmingRemovalOfUnrepresentableVariations: true
            )
            pendingVariationRemoval = nil
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text((pendingVariationRemoval?.names ?? []).joined(separator: ", ") + " cannot be re-anchored to the new base.")
      }
  }
}

extension View {
  func recipeVariationPromotionPresentation(
    model: RecipeDetailModel,
    promotingVariation: Binding<RecipeVariation?>,
    pendingVariationRemoval: Binding<PendingVariationRemoval?>
  ) -> some View {
    modifier(
      RecipeVariationPromotionPresentation(
        model: model,
        promotingVariation: promotingVariation,
        pendingVariationRemoval: pendingVariationRemoval
      )
    )
  }
}
