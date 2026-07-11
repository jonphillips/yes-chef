import Dependencies
import Foundation
import OSLog
import YesChefCore

struct RecipeAdjustmentReviewState: Identifiable, Equatable {
  let id = UUID()
  var currentDetail: RecipeDetailData
  var proposedDetail: RecipeDetailData
  var proposal: RecipeAdjustmentProposal
}

struct RecipeAdjustmentRestorePoint: Equatable {
  var recipeTitle: String
  var data: Data
}

extension RecipeDetailModel {
  func presentAdjustmentReview(_ proposal: RecipeAdjustmentProposal) throws {
    guard let detail else { return }
    let proposedDetail = try proposal.proposedDetail(applyingTo: detail, now: now, uuid: { uuid() })
    destination = .adjustmentReview(
      RecipeAdjustmentReviewState(
        currentDetail: detail,
        proposedDetail: proposedDetail,
        proposal: proposal
      )
    )
  }

  func overwriteAdjustmentButtonTapped(_ review: RecipeAdjustmentReviewState) -> Bool {
    do {
      let restorePoint = try database.write { db in
        try RecipeRepository.overwriteRecipeWithAdjustmentProposal(
          review.proposal,
          recipeID: recipeID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      adjustmentRestorePoint = RecipeAdjustmentRestorePoint(
        recipeTitle: review.currentDetail.recipe.title,
        data: restorePoint
      )
      destination = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }

  func keepAdjustmentAsVariationButtonTapped(
    _ review: RecipeAdjustmentReviewState,
    name: String
  ) -> Bool {
    do {
      try database.write { db in
        _ = try RecipeRepository.keepAdjustmentProposalAsVariation(
          review.proposal,
          recipeID: recipeID,
          name: name,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      destination = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }

  func renameVariation(_ variationID: RecipeVariation.ID, to name: String) {
    Task {
      let now = now
      do {
        try await database.write { db in
          try RecipeRepository.renameVariation(
            variationID,
            to: name,
            in: db,
            now: now
          )
        }
      } catch {
        errorMessage = String(describing: error)
        isShowingError = true
      }
    }
  }

  /// Switches the active variation, instrumented per ADR-0029 Amendment 2 S5a to
  /// split the tap→publish latency into its four phases:
  ///
  /// 1. **writer-wait** — handler entry → write-closure entry (the Finding-5 convoy,
  ///    if the theory holds: our write queued behind the sync engine's observation
  ///    re-fetches on the shared writer);
  /// 2. **SQL** — write-closure entry → the last statement in the two-statement write;
  /// 3. **write-return envelope** — the last statement → `database.write` returning;
  /// 4. **publish-gap** — write return → the `@Fetch` delivering the new
  ///    `activeVariationID`.
  ///
  /// The SQL and write-return-envelope boundaries are signposted for Instruments
  /// and mirrored, with WAL and sync state, to `AppLog.performance` so a plain
  /// console capture is enough. Cheap; left in permanently, no DEBUG gating.
  func activeVariationSelectionChanged(_ variationID: RecipeVariation.ID?) {
    let clock = ContinuousClock()
    let handlerEntry = clock.now
    let signposter = AppLog.performanceSignposter
    let signpostID = signposter.makeSignpostID()
    let correlationToken = String(describing: signpostID)
    let interval = signposter.beginInterval("variationSwitch", id: signpostID)
    Task {
      let now = now
      let makeUUID = uuid
      let walBefore = await readWALCheckpoint()
      let syncBefore = syncActivity
      let writeStart = InstantBox()
      let sqlDone = InstantBox()
      do {
        try await database.write { db in
          writeStart.instant = clock.now
          signposter.emitEvent("writer-wait", id: signpostID)
          try RecipeRepository.setActiveVariation(
            variationID,
            recipeID: recipeID,
            in: db,
            now: now,
            uuid: { makeUUID() }
          )
          sqlDone.instant = clock.now
          signposter.emitEvent("variationSQLDone", id: signpostID)
        }
        let writeExit = clock.now
        let entryToWrite = writeStart.instant ?? writeExit
        let lastStatementDone = sqlDone.instant ?? writeExit
        let writerWait = handlerEntry.duration(to: entryToWrite).milliseconds
        let sqlDuration = entryToWrite.duration(to: lastStatementDone).milliseconds
        let writeReturnEnvelope = lastStatementDone.duration(to: writeExit).milliseconds
        signposter.emitEvent("variationWriteReturnEnvelopeDone", id: signpostID)
        let syncAfter = syncActivity
        let walAfter = await readWALCheckpoint()
        let syncOverall = syncBefore.isActive || syncAfter.isActive ? "active" : "idle"
        AppLog.performance.log(
          "variation-switch correlation=\(correlationToken, privacy: .public) writer-wait=\(writerWait, format: .fixed(precision: 1))ms sql=\(sqlDuration, format: .fixed(precision: 1))ms write-return-envelope=\(writeReturnEnvelope, format: .fixed(precision: 1))ms wal-before=\(walBefore.description, privacy: .public) wal-after=\(walAfter.description, privacy: .public) sync=\(syncOverall, privacy: .public) sync-before=\(syncBefore.description, privacy: .public) sync-after=\(syncAfter.description, privacy: .public)"
        )

        await awaitActiveVariationDelivery(variationID)
        let publishGap = writeExit.duration(to: clock.now).milliseconds
        AppLog.performance.log(
          "variation-switch publish-gap=\(publishGap, format: .fixed(precision: 1))ms"
        )
        signposter.endInterval("variationSwitch", interval)
      } catch {
        signposter.endInterval("variationSwitch", interval)
        errorMessage = String(describing: error)
        isShowingError = true
      }
    }
  }

  /// Waits until the observed `detail` reflects the just-written active variation.
  /// `detail` is `@ObservationIgnored`, so `withObservationTracking` can't see it;
  /// a light main-actor poll is enough for a one-off diagnostic repro.
  private func awaitActiveVariationDelivery(_ target: RecipeVariation.ID?) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(30))
    while detail?.activeVariationID != target, clock.now < deadline {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  func undoLastAdjustmentButtonTapped() {
    guard let restorePoint = adjustmentRestorePoint else { return }
    Task {
      let now = now
      let makeUUID = uuid
      do {
        try await database.write { db in
          try RecipeRepository.restoreRecipeAdjustment(
            restorePoint.data,
            recipeID: recipeID,
            in: db,
            now: now,
            uuid: { makeUUID() }
          )
        }
        adjustmentRestorePoint = nil
      } catch {
        errorMessage = String(describing: error)
        isShowingError = true
      }
    }
  }

}

private extension RecipeDetailModel {
  var syncActivity: SyncActivitySnapshot {
    SyncActivitySnapshot(
      isRunning: syncEngine.isRunning,
      isSending: syncEngine.isSendingChanges,
      isFetching: syncEngine.isFetchingChanges
    )
  }

  func readWALCheckpoint() async -> WALCheckpointObservation {
    do {
      let state = try await database.read { db in
        try WALCheckpointState.read(from: db)
      }
      return WALCheckpointObservation(state: state)
    } catch {
      return WALCheckpointObservation(error: String(describing: error))
    }
  }
}

private struct SyncActivitySnapshot: Sendable, CustomStringConvertible {
  let isRunning: Bool
  let isSending: Bool
  let isFetching: Bool

  var isActive: Bool { isSending || isFetching }

  var description: String {
    let phase = isActive ? "active" : "idle"
    return "\(phase)(running=\(isRunning),sending=\(isSending),fetching=\(isFetching))"
  }
}

private struct WALCheckpointState: Sendable {
  let busy: Int
  let logPages: Int
  let checkpointedPages: Int

  var description: String {
    "busy=\(busy),log=\(logPages),checkpointed=\(checkpointedPages)"
  }

  static func read(from db: Database) throws -> Self {
    guard let result = try #sql("PRAGMA wal_checkpoint(NOOP)", as: (Int, Int, Int).self)
      .fetchOne(db)
    else {
      throw WALCheckpointProbeError.noResult
    }
    let busy = result.0
    let logPages = result.1
    let checkpointedPages = result.2
    return Self(busy: busy, logPages: logPages, checkpointedPages: checkpointedPages)
  }
}

private struct WALCheckpointObservation: Sendable {
  let state: WALCheckpointState?
  let error: String?

  init(state: WALCheckpointState) {
    self.state = state
    self.error = nil
  }

  init(error: String) {
    self.state = nil
    self.error = error
  }

  var description: String {
    state?.description ?? "unavailable(error=\(error ?? "unknown"))"
  }
}

private enum WALCheckpointProbeError: Error {
  case noResult
}

/// One-shot carrier for the write-closure entry timestamp captured off the main
/// actor inside `database.write`. Written once inside the closure and read only
/// after it returns (happens-after), so unchecked `Sendable` is safe.
private final class InstantBox: @unchecked Sendable {
  var instant: ContinuousClock.Instant?
}

private extension Duration {
  var milliseconds: Double {
    Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}
