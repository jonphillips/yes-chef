import SwiftUI
import YesChefCore

struct RecipeVariationActions: View {
  let variation: RecipeVariation
  let model: RecipeDetailModel
  @Binding var promotingVariation: RecipeVariation?

  var body: some View {
    Button {
      model.editVariationButtonTapped(variation.id)
    } label: {
      Label("Edit Variation", systemImage: "square.and.pencil")
        .labelStyle(.iconOnly)
    }
    .buttonStyle(.bordered)
    .accessibilityLabel(Text("Edit Variation"))

    Menu {
      Button("Split Off as Recipe") {
        Task { await model.splitVariationOffButtonTapped(variation.id) }
      }
      Button("Promote to Base") { promotingVariation = variation }
    } label: {
      Label("Variation Actions", systemImage: "ellipsis.circle")
        .labelStyle(.iconOnly)
    }
    .accessibilityLabel(Text("Variation Actions"))
  }
}

private struct RecipeVariationPromotionPresentation: ViewModifier {
  let model: RecipeDetailModel
  @Binding var promotingVariation: RecipeVariation?
  @Binding var unrepresentablePromotionNames: [String]

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
              promotingVariation = nil
              unrepresentablePromotionNames = names
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
          get: { !unrepresentablePromotionNames.isEmpty },
          set: { if !$0 { unrepresentablePromotionNames = [] } }
        ),
        titleVisibility: .visible
      ) {
        Button("Promote and Remove Variations", role: .destructive) {
          guard let variation = promotingVariation ?? model.detail?.activeVariation else { return }
          Task {
            _ = await model.promoteVariationButtonTapped(
              variation.id,
              confirmingRemovalOfUnrepresentableVariations: true
            )
            promotingVariation = nil
            unrepresentablePromotionNames = []
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(unrepresentablePromotionNames.joined(separator: ", ") + " cannot be re-anchored to the new base.")
      }
  }
}

extension View {
  func recipeVariationPromotionPresentation(
    model: RecipeDetailModel,
    promotingVariation: Binding<RecipeVariation?>,
    unrepresentablePromotionNames: Binding<[String]>
  ) -> some View {
    modifier(
      RecipeVariationPromotionPresentation(
        model: model,
        promotingVariation: promotingVariation,
        unrepresentablePromotionNames: unrepresentablePromotionNames
      )
    )
  }
}
