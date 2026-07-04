import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct PantrySuppressionTests {
    @Test
    func unlimitedPolicyRoutesItemToAssumedPantry() {
      let row = groceryRow(
        id: SampleUUIDSequence.uuid(52_001),
        title: "olive oil",
        canonicalName: "olive oil",
        quantity: 2,
        quantityText: "2",
        unit: "tablespoons"
      )
      let policy = pantryItem(
        id: SampleUUIDSequence.uuid(52_101),
        title: "Olive oil",
        policy: .unlimited
      )

      let evaluation = PantrySuppression.evaluate(list: [row], policies: [policy])

      expectNoDifference(evaluation.shown.map(\.id), [])
      expectNoDifference(evaluation.assumedInPantry.map(\.id), [row.id])
      expectNoDifference(evaluation.needsReview.map(\.id), [])
    }

    @Test
    func thresholdUnderIsAssumedAndThresholdOverNeedsReview() {
      let under = groceryRow(
        id: SampleUUIDSequence.uuid(52_002),
        title: "soy sauce",
        canonicalName: "soy sauce",
        quantity: 2,
        quantityText: "2",
        unit: "tablespoons",
        sortOrder: 0
      )
      let over = groceryRow(
        id: SampleUUIDSequence.uuid(52_003),
        title: "soy sauce",
        canonicalName: "soy sauce",
        quantity: 0.75,
        quantityText: "0.75",
        unit: "cup",
        sortOrder: 1
      )
      let policy = pantryItem(
        id: SampleUUIDSequence.uuid(52_102),
        title: "Soy sauce",
        policy: .threshold(quantity: 0.5, unit: "cup")
      )

      let underEvaluation = PantrySuppression.evaluate(list: [under], policies: [policy])
      let overEvaluation = PantrySuppression.evaluate(list: [over], policies: [policy])

      expectNoDifference(underEvaluation.assumedInPantry.map(\.id), [under.id])
      expectNoDifference(underEvaluation.needsReview.map(\.id), [])
      expectNoDifference(overEvaluation.assumedInPantry.map(\.id), [])
      expectNoDifference(overEvaluation.needsReview.map(\.id), [over.id])
    }

    @Test
    func thresholdUsesCrossRecipeConsolidatedTotal() {
      let soySauce = groceryRow(
        id: SampleUUIDSequence.uuid(52_004),
        title: "soy sauce",
        canonicalName: "soy sauce",
        quantity: 9,
        quantityText: "9",
        unit: "tablespoons",
        sources: [
          grocerySource(
            id: SampleUUIDSequence.uuid(52_201),
            itemID: SampleUUIDSequence.uuid(52_004),
            ingredientText: "3 tablespoons soy sauce"
          ),
          grocerySource(
            id: SampleUUIDSequence.uuid(52_202),
            itemID: SampleUUIDSequence.uuid(52_004),
            ingredientText: "3 tablespoons soy sauce"
          ),
          grocerySource(
            id: SampleUUIDSequence.uuid(52_203),
            itemID: SampleUUIDSequence.uuid(52_004),
            ingredientText: "3 tablespoons soy sauce"
          ),
        ]
      )
      let policy = pantryItem(
        id: SampleUUIDSequence.uuid(52_103),
        title: "Soy sauce",
        policy: .threshold(quantity: 0.5, unit: "cup")
      )

      let evaluation = PantrySuppression.evaluate(list: [soySauce], policies: [policy])

      expectNoDifference(evaluation.assumedInPantry.map(\.id), [])
      expectNoDifference(evaluation.needsReview.map(\.id), [soySauce.id])
    }

    @Test
    func incomparableThresholdUnitsNeedReview() {
      let row = groceryRow(
        id: SampleUUIDSequence.uuid(52_005),
        title: "brown sugar",
        canonicalName: "brown sugar",
        quantity: 1,
        quantityText: "1",
        unit: "pound"
      )
      let policy = pantryItem(
        id: SampleUUIDSequence.uuid(52_104),
        title: "Brown sugar",
        policy: .threshold(quantity: 0.5, unit: "cup")
      )

      let evaluation = PantrySuppression.evaluate(list: [row], policies: [policy])

      expectNoDifference(evaluation.shown.map(\.id), [])
      expectNoDifference(evaluation.assumedInPantry.map(\.id), [])
      expectNoDifference(evaluation.needsReview.map(\.id), [row.id])
    }

    @Test
    func addBackMovesAssumedRowToShownWithoutChangingPolicy() {
      let row = groceryRow(
        id: SampleUUIDSequence.uuid(52_006),
        title: "kosher salt",
        canonicalName: "kosher salt"
      )
      let policy = pantryItem(
        id: SampleUUIDSequence.uuid(52_105),
        title: "Kosher salt",
        policy: .unlimited
      )
      let evaluation = PantrySuppression.evaluate(list: [row], policies: [policy])

      let addBackEvaluation = PantrySuppression.addBack(itemID: row.id, to: evaluation)

      expectNoDifference(addBackEvaluation.shown.map(\.id), [row.id])
      expectNoDifference(addBackEvaluation.assumedInPantry.map(\.id), [])
      expectNoDifference(policy.policy, .unlimited)
    }

    private func groceryRow(
      id: GroceryItem.ID,
      title: String,
      canonicalName: String?,
      quantity: Double? = nil,
      quantityText: String? = nil,
      unit: String? = nil,
      sortOrder: Int = 0,
      sources: [GroceryItemSource] = []
    ) -> GroceryItemRowData {
      let now = Date(timeIntervalSinceReferenceDate: 825_000_000)
      return GroceryItemRowData(
        item: GroceryItem(
          id: id,
          groceryListID: SampleUUIDSequence.uuid(52_900),
          title: title,
          canonicalName: canonicalName,
          quantity: quantity,
          quantityText: quantityText,
          unit: unit,
          sortOrder: sortOrder,
          dateCreated: now,
          dateModified: now
        ),
        sources: sources
      )
    }

    private func pantryItem(
      id: PantryItem.ID,
      title: String,
      policy: PantryPolicy
    ) -> PantryItem {
      let now = Date(timeIntervalSinceReferenceDate: 825_100_000)
      let storageValues = policy.storageValues
      return PantryItem(
        id: id,
        title: title,
        isUnlimited: storageValues.isUnlimited,
        thresholdQuantity: storageValues.thresholdQuantity,
        thresholdUnit: storageValues.thresholdUnit,
        sortOrder: 0,
        dateCreated: now,
        dateModified: now
      )
    }

    private func grocerySource(
      id: GroceryItemSource.ID,
      itemID: GroceryItem.ID,
      ingredientText: String
    ) -> GroceryItemSource {
      GroceryItemSource(
        id: id,
        groceryItemID: itemID,
        origin: .recipe,
        ingredientText: ingredientText,
        dateCreated: Date(timeIntervalSinceReferenceDate: 825_200_000)
      )
    }
  }
}
