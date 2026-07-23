import SwiftUI
import YesChefCore

struct RecipeVariationActions: View {
  let variation: RecipeVariation
  let model: RecipeDetailModel
  @Binding var promotingVariation: RecipeVariation?
  @Binding var splittingOffVariation: RecipeVariation?
  @Binding var splitOffTitleDraft: String

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
        splitOffTitleDraft = variation.name
        splittingOffVariation = variation
      }
      Button("Promote to Base") { promotingVariation = variation }
    } label: {
      Label("Variation Actions", systemImage: "ellipsis.circle")
        .labelStyle(.iconOnly)
    }
    .accessibilityLabel(Text("Variation Actions"))
  }
}

struct RecipeVariationPicker: View {
  let variations: [RecipeVariation]
  let activeVariationID: RecipeVariation.ID?
  let model: RecipeDetailModel
  @Binding var promotingVariation: RecipeVariation?
  @Binding var splittingOffVariation: RecipeVariation?
  @Binding var splitOffTitleDraft: String

  @State private var renamingVariation: RecipeVariation?
  @State private var variationNameDraft = ""

  private var activeVariation: RecipeVariation? {
    activeVariationID.flatMap { id in variations.first { $0.id == id } }
  }

  var body: some View {
    HStack(spacing: 8) {
      Menu {
        Button {
          model.activeVariationSelectionChanged(nil)
        } label: {
          variationMenuLabel(
            "Base Recipe",
            systemImage: "book.closed",
            isSelected: activeVariationID == nil
          )
        }
        Divider()
        ForEach(variations) { variation in
          Button {
            model.activeVariationSelectionChanged(variation.id)
          } label: {
            variationMenuLabel(
              variation.name,
              systemImage: "checkmark",
              isSelected: variation.id == activeVariationID
            )
          }
        }
      } label: {
        Label(activeVariation == nil ? "Base Recipe" : "Version", systemImage: "square.stack.3d.up")
      }
      .fixedSize(horizontal: true, vertical: false)
      .accessibilityLabel(
        Text(activeVariation.map { "Version: \($0.name)" } ?? "Version: Base Recipe")
      )

      if let activeVariation {
        Button {
          variationNameDraft = activeVariation.name
          renamingVariation = activeVariation
        } label: {
          Label("Rename Variation", systemImage: "pencil")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(Text("Rename Variation"))

        RecipeVariationActions(
          variation: activeVariation,
          model: model,
          promotingVariation: $promotingVariation,
          splittingOffVariation: $splittingOffVariation,
          splitOffTitleDraft: $splitOffTitleDraft
        )
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

  @ViewBuilder
  private func variationMenuLabel(
    _ title: String,
    systemImage: String,
    isSelected: Bool
  ) -> some View {
    if isSelected {
      Label(title, systemImage: systemImage)
    } else {
      Text(title)
    }
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
