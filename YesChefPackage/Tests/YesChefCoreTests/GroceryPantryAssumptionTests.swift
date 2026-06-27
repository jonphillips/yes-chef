import CustomDump
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct GroceryPantryAssumptionTests {
    @Test
    func identifiesConservativePantryStaples() {
      expectNoDifference(
        GroceryPantryAssumptions.isPantryStaple(
          IngredientLine(
            id: SampleUUIDSequence.uuid(18_201),
            recipeID: SampleUUIDSequence.uuid(18_202),
            sectionID: SampleUUIDSequence.uuid(18_203),
            originalText: "2 tablespoons olive oil",
            quantity: 2,
            quantityText: "2",
            unit: "tablespoons",
            item: "olive oil",
            sortOrder: 0
          )
        ),
        true
      )
      expectNoDifference(
        GroceryPantryAssumptions.isPantryStaple(
          IngredientLine(
            id: SampleUUIDSequence.uuid(18_204),
            recipeID: SampleUUIDSequence.uuid(18_205),
            sectionID: SampleUUIDSequence.uuid(18_206),
            originalText: "Salt and freshly ground black pepper",
            item: "Salt and freshly ground black pepper",
            sortOrder: 1
          )
        ),
        true
      )
      expectNoDifference(
        GroceryPantryAssumptions.isPantryStaple(
          IngredientLine(
            id: SampleUUIDSequence.uuid(18_207),
            recipeID: SampleUUIDSequence.uuid(18_208),
            sectionID: SampleUUIDSequence.uuid(18_209),
            originalText: "1 cup sugar",
            quantity: 1,
            quantityText: "1",
            unit: "cup",
            item: "sugar",
            sortOrder: 2
          )
        ),
        false
      )
    }

    @Test
    func identifiesEditablePantryStaples() {
      expectNoDifference(
        GroceryPantryAssumptions.isPantryStaple(
          IngredientLine(
            id: SampleUUIDSequence.uuid(18_210),
            recipeID: SampleUUIDSequence.uuid(18_211),
            sectionID: SampleUUIDSequence.uuid(18_212),
            originalText: "1 cup sugar",
            quantity: 1,
            quantityText: "1",
            unit: "cup",
            item: "sugar",
            sortOrder: 0
          ),
          pantryStaples: ["sugar"]
        ),
        true
      )
    }
  }
}
