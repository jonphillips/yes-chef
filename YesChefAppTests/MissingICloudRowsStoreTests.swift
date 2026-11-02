import CloudSyncKit
import Foundation
import Testing
@testable import YesChef

@Suite
@MainActor
struct MissingICloudRowsStoreTests {
  @Test
  func findingsArePresentedAndSurviveANewModel() {
    let defaults = makeDefaults()
    let rows = [
      CloudSyncMissingRow(recordType: "recipes", primaryKey: "recipe-1"),
      CloudSyncMissingRow(recordType: "recipeSources", primaryKey: "source-1"),
    ]
    let model = SyncHealthModel(defaults: defaults)
    model.recordMissingRows(rows)

    #expect(model.missingCount == 2)
    #expect(model.missingRows == rows)
    #expect(SyncHealthModel(defaults: defaults).missingRows == rows)
  }

  @Test
  func uploadAgainQueuesTheFindingAndClearsIt() async {
    let defaults = makeDefaults()
    let rows = [CloudSyncMissingRow(recordType: "recipes", primaryKey: "recipe-1")]
    var queued: [CloudSyncMissingRow] = []
    let model = SyncHealthModel(defaults: defaults, missingRowsReuploader: { values in
      queued = values
      return values.count
    })
    model.recordMissingRows(rows)

    await model.reuploadMissingRows()

    #expect(queued == rows)
    #expect(model.missingRows.isEmpty)
    #expect(model.missingReuploadSummary == "Queued 1 record to upload again.")
    #expect(SyncHealthModel(defaults: defaults).missingRows.isEmpty)
  }

  @Test
  func cleanCheckAndRestoreClearTheFinding() {
    let defaults = makeDefaults()
    let model = SyncHealthModel(defaults: defaults)
    model.recordMissingRows([CloudSyncMissingRow(recordType: "recipes", primaryKey: "recipe-1")])

    model.recordMissingRows([])
    #expect(SyncHealthModel(defaults: defaults).missingRows.isEmpty)

    model.recordMissingRows([CloudSyncMissingRow(recordType: "recipes", primaryKey: "recipe-2")])
    model.clearMissingRowsAfterRestore()
    #expect(model.missingRows.isEmpty)
    #expect(SyncHealthModel(defaults: defaults).missingRows.isEmpty)
  }

  private func makeDefaults() -> UserDefaults {
    let name = "MissingICloudRowsStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }
}
