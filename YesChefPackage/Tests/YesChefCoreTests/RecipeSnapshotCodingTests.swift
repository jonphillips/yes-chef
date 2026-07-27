import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeSnapshotCodingTests {
    @Test
    func originalSnapshotRoundTripsReadableRecipeDataWithoutRawBlobs() throws {
      let now = Date(timeIntervalSinceReferenceDate: 802_000_000)
      let recipeID = SampleUUIDSequence.uuid(1)
      let sectionID = SampleUUIDSequence.uuid(2)
      let recipe = Recipe(
        id: recipeID,
        title: "Test Recipe",
        summary: "A useful fixture",
        servingsText: "Serves 4",
        dateCreated: now,
        dateModified: now,
        originalImportText: "<html>debug source</html>"
      )
      let displayData = Data(repeating: 0x42, count: 20_000)
      let thumbnailData = Data(repeating: 0x24, count: 4_000)
      let data = try RecipeBundleCoding.snapshotData(
        recipe: recipe,
        source: RecipeSource(id: SampleUUIDSequence.uuid(3), recipeID: recipeID, name: "Personal"),
        ingredientSections: [IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)],
        ingredientLines: [
          IngredientLine(
            id: SampleUUIDSequence.uuid(4),
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "1 onion",
            quantity: 1,
            quantityText: "1",
            unit: nil,
            item: "onion",
            sortOrder: 0
          )
        ],
        instructionSections: [],
        instructionSteps: [],
        notes: [],
        tagNames: ["weeknight"],
        categoryNames: ["Mains"],
        photos: [
          RecipePhoto(
            id: SampleUUIDSequence.uuid(5),
            recipeID: recipeID,
            imageDataReference: "recipePhotos/\(SampleUUIDSequence.uuid(5).uuidString)",
            displayData: displayData,
            thumbnailData: thumbnailData,
            mediaType: "image/jpeg",
            pixelWidth: 1_200,
            pixelHeight: 900,
            sourceURL: "https://example.com/photo.jpg",
            checksum: "abc123",
            kind: .hero,
            caption: "Finished dish",
            source: .imported,
            sortOrder: 0,
            dateCreated: now
          )
        ]
      )

      let snapshot = try RecipeBundleCoding.decodeSnapshot(data)

      #expect(data.count < 5_000)
      expectNoDifference(snapshot.recipe.title, "Test Recipe")
      expectNoDifference(snapshot.recipe.originalImportText, nil)
      expectNoDifference(snapshot.ingredients, ["1 onion"])
      expectNoDifference(snapshot.ingredientLines.first?.quantity, 1)
      expectNoDifference(snapshot.tags, ["weeknight"])
      expectNoDifference(snapshot.photos.map(\.sourceURL), ["https://example.com/photo.jpg"])
      expectNoDifference(snapshot.photos.map(\.displayData), [nil])
      expectNoDifference(snapshot.photos.map(\.thumbnailData), [nil])
      expectNoDifference(snapshot.photos.map(\.mediaType), ["image/jpeg"])
      expectNoDifference(snapshot.photos.map(\.pixelWidth), [1_200])
      expectNoDifference(snapshot.photos.map(\.pixelHeight), [900])
      expectNoDifference(snapshot.photos.map(\.checksum), ["abc123"])
      expectNoDifference(snapshot.photos.map(\.kind), [.hero])
      expectNoDifference(snapshot.photos.map(\.caption), ["Finished dish"])
    }

    @Test
    func transferRecipeBundleKeepsPhotoBytes() throws {
      let now = Date(timeIntervalSinceReferenceDate: 802_000_000)
      let recipeID = SampleUUIDSequence.uuid(11)
      let displayData = Data(repeating: 0x42, count: 20)
      let thumbnailData = Data(repeating: 0x24, count: 10)
      let bundle = RecipeBundleCoding.RecipeBundle(
        recipe: Recipe(
          id: recipeID,
          title: "Transfer Recipe",
          dateCreated: now,
          dateModified: now
        ),
        photos: [
          RecipePhoto(
            id: SampleUUIDSequence.uuid(12),
            recipeID: recipeID,
            imageDataReference: "recipePhotos/\(SampleUUIDSequence.uuid(12).uuidString)",
            displayData: displayData,
            thumbnailData: thumbnailData,
            mediaType: "image/jpeg",
            kind: .hero,
            source: .imported,
            sortOrder: 0,
            dateCreated: now
          )
        ]
      )

      let data = try JSONEncoder().encode(bundle)
      let decoded = try JSONDecoder().decode(RecipeBundleCoding.RecipeBundle.self, from: data)

      expectNoDifference(decoded.photos.first?.displayData, displayData)
      expectNoDifference(decoded.photos.first?.thumbnailData, thumbnailData)
    }

    @Test
    func snapshotsOrderInstructionStepsBySectionBeforeStep() throws {
      let recipeID = SampleUUIDSequence.uuid(13)
      let prepSectionID = SampleUUIDSequence.uuid(14)
      let cookSectionID = SampleUUIDSequence.uuid(15)
      let recipe = Recipe(
        id: recipeID,
        title: "Sectioned Snapshot",
        dateCreated: .distantPast,
        dateModified: .distantPast
      )
      let snapshot = try RecipeBundleCoding.decodeSnapshot(
        RecipeBundleCoding.snapshotData(
          recipe: recipe,
          source: nil,
          ingredientSections: [],
          ingredientLines: [],
          instructionSections: [
            InstructionSection(id: cookSectionID, recipeID: recipeID, name: "Cook", sortOrder: 1),
            InstructionSection(id: prepSectionID, recipeID: recipeID, name: "Prep", sortOrder: 0),
          ],
          instructionSteps: [
            InstructionStep(
              id: SampleUUIDSequence.uuid(16),
              recipeID: recipeID,
              sectionID: cookSectionID,
              text: "Roast until browned.",
              sortOrder: 0
            ),
            InstructionStep(
              id: SampleUUIDSequence.uuid(17),
              recipeID: recipeID,
              sectionID: prepSectionID,
              text: "Season the chicken.",
              sortOrder: 1
            ),
            InstructionStep(
              id: SampleUUIDSequence.uuid(18),
              recipeID: recipeID,
              sectionID: prepSectionID,
              text: "Heat the oven.",
              sortOrder: 0
            ),
          ],
          notes: [],
          tagNames: [],
          categoryNames: []
        )
      )

      expectNoDifference(
        snapshot.instructions,
        ["Heat the oven.", "Season the chicken.", "Roast until browned."]
      )
      expectNoDifference(
        snapshot.instructionSteps.map(\.text),
        ["Heat the oven.", "Season the chicken.", "Roast until browned."]
      )
    }
  }
}
