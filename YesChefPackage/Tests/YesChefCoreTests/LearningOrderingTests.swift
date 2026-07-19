import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import YesChefCore

@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
struct LearningOrderingTests {
  @Test
  func backfillPreservesTheExistingNewestFirstDisplay() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_050)
    let oldestID = SampleUUIDSequence.uuid(38_051)
    let middleID = SampleUUIDSequence.uuid(38_052)
    let newestID = SampleUUIDSequence.uuid(38_053)
    let oldest = Date(timeIntervalSinceReferenceDate: 840_100_000)

    try database.write { db in
      for (id, text, date) in [
        (oldestID, "Oldest", oldest),
        (middleID, "Middle", oldest.addingTimeInterval(60)),
        (newestID, "Newest", oldest.addingTimeInterval(120)),
      ] {
        try LearningRepository.create(
          Learning(
            id: id,
            sourceType: .menu,
            sourceID: menuID,
            text: text,
            provenance: .externalHandoff,
            dateCreated: date,
            dateModified: date
          ),
          in: db
        )
      }

      try LearningRepository.backfillSortOrders(in: db)
      let learnings = try LearningRepository.learnings(sourceType: .menu, sourceID: menuID, in: db)
      expectNoDifference(learnings.map(\.id), [newestID, middleID, oldestID])
      expectNoDifference(learnings.map(\.sortOrder), [0, 1_024, 2_048])
    }
  }

  @Test
  func newLearningsPrependWithNegativeSparseRanks() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_060)
    let firstID = SampleUUIDSequence.uuid(38_061)
    let secondID = SampleUUIDSequence.uuid(38_062)
    var uuids = SampleUUIDSequence(start: 38_063)
    let now = Date(timeIntervalSinceReferenceDate: 840_200_000)

    try database.write { db in
      for (id, text, sortOrder) in [(firstID, "Existing first", 0), (secondID, "Existing second", 1_024)] {
        try LearningRepository.create(
          Learning(
            id: id,
            sourceType: .menu,
            sourceID: menuID,
            sortOrder: sortOrder,
            text: text,
            provenance: .externalHandoff,
            dateCreated: now,
            dateModified: now
          ),
          in: db
        )
      }

      expectNoDifference(
        try LearningRepository.insertNew(
          texts: ["New first", "New second"],
          sourceType: .menu,
          sourceID: menuID,
          provenance: .externalHandoff,
          in: db,
          now: now,
          uuid: { uuids.next() }
        ),
        2
      )
      let learnings = try LearningRepository.learnings(sourceType: .menu, sourceID: menuID, in: db)
      expectNoDifference(learnings.map(\.text), ["New first", "New second", "Existing first", "Existing second"])
      expectNoDifference(learnings.map(\.sortOrder), [-2_048, -1_024, 0, 1_024])
    }
  }

  @Test
  func reorderingUsesGapsThenRebalancesOnlyWhenNeeded() throws {
    @Dependency(\.defaultDatabase) var database
    let menuID = SampleUUIDSequence.uuid(38_070)
    let firstID = SampleUUIDSequence.uuid(38_071)
    let secondID = SampleUUIDSequence.uuid(38_072)
    let thirdID = SampleUUIDSequence.uuid(38_073)
    let createdAt = Date(timeIntervalSinceReferenceDate: 840_300_000)
    let movedAt = createdAt.addingTimeInterval(60)

    try database.write { db in
      for (id, text, sortOrder) in [(firstID, "First", 0), (secondID, "Second", 1_024), (thirdID, "Third", 2_048)] {
        try LearningRepository.create(
          Learning(
            id: id,
            sourceType: .menu,
            sourceID: menuID,
            sortOrder: sortOrder,
            text: text,
            provenance: .externalHandoff,
            dateCreated: createdAt,
            dateModified: createdAt
          ),
          in: db
        )
      }

      #expect(try LearningRepository.reorder(
        sourceType: .menu,
        sourceID: menuID,
        movingIDs: [thirdID],
        destination: .before(secondID),
        in: db,
        now: movedAt
      ))
      var learnings = try LearningRepository.learnings(sourceType: .menu, sourceID: menuID, in: db)
      expectNoDifference(learnings.map(\.id), [firstID, thirdID, secondID])
      expectNoDifference(learnings.map(\.sortOrder), [0, 512, 1_024])
      expectNoDifference(try Learning.find(firstID).fetchOne(db)?.dateModified, createdAt)
      expectNoDifference(try Learning.find(secondID).fetchOne(db)?.dateModified, createdAt)
      expectNoDifference(try Learning.find(thirdID).fetchOne(db)?.dateModified, movedAt)

      try Learning.find(thirdID).update { $0.sortOrder = #bind(2_048) }.execute(db)
      try Learning.find(secondID).update { $0.sortOrder = #bind(1) }.execute(db)
      learnings = try LearningRepository.learnings(sourceType: .menu, sourceID: menuID, in: db)
      #expect(try LearningRepository.reorder(
        sourceType: .menu,
        sourceID: menuID,
        movingIDs: [thirdID],
        destination: .before(secondID),
        in: db,
        now: movedAt
      ))
      learnings = try LearningRepository.learnings(sourceType: .menu, sourceID: menuID, in: db)
      expectNoDifference(learnings.map(\.id), [firstID, thirdID, secondID])
      expectNoDifference(learnings.map(\.sortOrder), [0, 1_024, 2_048])
    }
  }
}
