import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WorkbenchExperimentTests {
    @Test
    func typedExperimentFieldsPersistIndependentlyOfTheLegacyBody() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 806_255_000)
      var uuids = SampleUUIDSequence(start: 21_250)

      try database.write { db in
        let workbenchID = try WorkbenchRepository.addWorkbench(
          title: "Cookies",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let entryID = try WorkbenchRepository.addLogEntry(
          WorkbenchLogEntryDraft(
            kind: .experiment,
            body: "",
            hypothesis: "A longer rest will improve chewiness.",
            change: "Chill the dough overnight.",
            rationale: "Hydrated flour develops more gluten."
          ),
          to: workbenchID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        var entry = try #require(try WorkbenchLogEntry.find(entryID).fetchOne(db))
        expectNoDifference(entry.body, "")
        expectNoDifference(entry.hypothesis, "A longer rest will improve chewiness.")
        expectNoDifference(entry.change, "Chill the dough overnight.")
        expectNoDifference(entry.rationale, "Hydrated flour develops more gluten.")

        try WorkbenchRepository.updateLogEntry(
          entryID: entryID,
          draft: WorkbenchLogEntryDraft(
            kind: .experiment,
            body: "",
            hypothesis: "A longer rest will improve chewiness.",
            change: "Chill the dough for two nights.",
            rationale: "Hydrated flour develops more gluten."
          ),
          in: db,
          now: now.addingTimeInterval(30)
        )

        entry = try #require(try WorkbenchLogEntry.find(entryID).fetchOne(db))
        expectNoDifference(entry.change, "Chill the dough for two nights.")
        expectNoDifference(entry.hypothesis, "A longer rest will improve chewiness.")
        expectNoDifference(entry.rationale, "Hydrated flour develops more gluten.")
      }
    }
  }
}
