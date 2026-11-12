import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct BuiltInKnowledgeTests {
    @Test
    func shippedFileDecodesAndAllAreasAreRecognized() throws {
      let knowledge = BuiltInKnowledge.current
      try knowledge.validate()
      #expect(knowledge.version == 1)
      #expect(!knowledge.aliases.isEmpty)
      #expect(!knowledge.keepers.isEmpty)
      #expect(!knowledge.pantryStaples.isEmpty)
      #expect(knowledge.areas.values.allSatisfy { GroceryStoreArea.normalized($0) != nil })
    }

    @Test
    func aliasesAreFlatAndAllowIdentityEntries() throws {
      let knowledge = BuiltInKnowledge.current
      try knowledge.validate()
      #expect(knowledge.aliases["anchovies"] == "anchovies")
      #expect(knowledge.aliases["green onion"] == "green onions")
    }
  }
}
