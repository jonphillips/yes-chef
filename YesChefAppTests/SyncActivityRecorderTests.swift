import Foundation
import Testing
@testable import YesChef

@MainActor
@Suite
struct SyncActivityRecorderTests {
  @Test
  func fetchStateFlipsAreRecordedUsingInjectedSource() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefSyncActivityRecorder-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let enabled = true
    var fetching = false
    var countCalls = 0
    let recorder = SyncActivityRecorder(
      source: SyncActivitySource(
        isEnabled: { enabled },
        isFetching: { fetching },
        counts: {
          countCalls += 1
          return ["recipes": 10]
        }
      ),
      ledgerURL: root.appendingPathComponent("activity.json")
    )
    let start = Date(timeIntervalSince1970: 10_000)

    await recorder.poll(now: start)
    fetching = true
    await recorder.poll(now: start.addingTimeInterval(1))
    fetching = false
    await recorder.poll(now: start.addingTimeInterval(2))

    #expect(recorder.ledger.entries.map(\.kind) == [.launch, .fetchStarted, .fetchEnded])
    #expect(countCalls == 1)
    #expect(recorder.latestCounts.map(\.name) == ["recipes"])
  }

  @Test
  func countsAreThrottledAndSyncOffRecordsNothing() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefSyncActivityRecorder-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var enabled = false
    var countCalls = 0
    let recorder = SyncActivityRecorder(
      source: SyncActivitySource(
        isEnabled: { enabled },
        isFetching: { false },
        counts: {
          countCalls += 1
          return ["recipes": countCalls]
        }
      ),
      ledgerURL: root.appendingPathComponent("activity.json")
    )
    let start = Date(timeIntervalSince1970: 20_000)

    await recorder.poll(now: start)
    #expect(recorder.ledger.entries.isEmpty)
    enabled = true
    await recorder.poll(now: start.addingTimeInterval(1))
    await recorder.scenePhaseChanged(isForeground: true, now: start.addingTimeInterval(15))
    await recorder.scenePhaseChanged(isForeground: false, now: start.addingTimeInterval(29))
    #expect(countCalls == 1)
    await recorder.scenePhaseChanged(isForeground: true, now: start.addingTimeInterval(31))

    #expect(countCalls == 2)
    #expect(recorder.ledger.entries.map(\.kind) == [.launch, .foreground, .background, .foreground])
  }
}
