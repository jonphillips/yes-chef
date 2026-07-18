import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension AIHandoffTests {
  @Suite
  struct LearningRepositoryTests {
    @Test
    func learningsForSourceFilterAndSortInDescendingCreationOrder() throws {
      @Dependency(\.defaultDatabase) var database
      let recipeID = SampleUUIDSequence.uuid(38_040)
      let otherRecipeID = SampleUUIDSequence.uuid(38_041)
      let oldestID = SampleUUIDSequence.uuid(38_042)
      let tiedEarlierID = SampleUUIDSequence.uuid(38_043)
      let tiedLaterID = SampleUUIDSequence.uuid(38_044)
      let oldestDate = Date(timeIntervalSinceReferenceDate: 840_000_000)
      let newestDate = oldestDate.addingTimeInterval(60)

      try database.write { db in
        for learning in [
          Learning(
            id: oldestID,
            sourceType: .recipe,
            sourceID: recipeID,
            text: "Salt beans early.",
            provenance: .externalHandoff,
            dateCreated: oldestDate,
            dateModified: oldestDate
          ),
          Learning(
            id: tiedEarlierID,
            sourceType: .recipe,
            sourceID: recipeID,
            text: "Toast dried chiles.",
            provenance: .inApp,
            dateCreated: newestDate,
            dateModified: newestDate
          ),
          Learning(
            id: tiedLaterID,
            sourceType: .recipe,
            sourceID: recipeID,
            text: "Finish with lime.",
            provenance: .externalHandoff,
            dateCreated: newestDate,
            dateModified: newestDate
          ),
          Learning(
            id: SampleUUIDSequence.uuid(38_045),
            sourceType: .recipe,
            sourceID: otherRecipeID,
            text: "Keep this elsewhere.",
            provenance: .inApp,
            dateCreated: newestDate.addingTimeInterval(60),
            dateModified: newestDate.addingTimeInterval(60)
          ),
          Learning(
            id: SampleUUIDSequence.uuid(38_046),
            sourceType: .menu,
            sourceID: recipeID,
            text: "A menu uses a different source type.",
            provenance: .inApp,
            dateCreated: newestDate.addingTimeInterval(60),
            dateModified: newestDate.addingTimeInterval(60)
          ),
        ] {
          try LearningRepository.create(learning, in: db)
        }
      }

      try database.read { db in
        expectNoDifference(
          try LearningRepository.learnings(sourceType: .recipe, sourceID: recipeID, in: db).map(\.id),
          [tiedLaterID, tiedEarlierID, oldestID]
        )
      }
    }
  }
}
