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
        let restorePoint = try RecipeRepository.overwriteRecipeWithAdjustmentProposal(
          review.proposal,
          recipeID: recipeID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        try addAdjustmentRationaleToWorkbenchIfNeeded(review, in: db)
        return restorePoint
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
        try addAdjustmentRationaleToWorkbenchIfNeeded(review, in: db)
      }
      destination = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }

  private func addAdjustmentRationaleToWorkbenchIfNeeded(
    _ review: RecipeAdjustmentReviewState,
    in db: Database
  ) throws {
    guard let workbenchID else { return }
    try WorkbenchRepository.addLogEntry(
      WorkbenchLogEntryDraft(
        kind: .rationale,
        body: review.proposal.reviewSummary(),
        relatedRecipeID: recipeID
      ),
      to: workbenchID,
      in: db,
      now: now,
      uuid: { uuid() }
    )
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

  /// Switches the active variation, instrumented per ADR-0029 Amendment 5 S6c.
  /// The write helper explicitly leaves the main actor, which lets the capture
  /// distinguish writer completion from the waiting time before this model task
  /// resumes on the main actor.
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
      let database = database
      let recipeID = recipeID
      let syncBefore = syncActivity
      let detailFetchAnimation = detailFetchAnimationDescription
      do {
        let timing = try await writeActiveVariation(
          variationID,
          recipeID: recipeID,
          database: database,
          now: now,
          makeUUID: { makeUUID() },
          clock: clock,
          signposter: signposter,
          signpostID: signpostID
        )
        let mainActorResume = clock.now
        let writerWait = handlerEntry.duration(to: timing.writeStart).milliseconds
        let sqlDuration = timing.writeStart.duration(to: timing.sqlDone).milliseconds
        let writerAPIReturn = timing.sqlDone.duration(to: timing.writerAPIReturn).milliseconds
        let mainActorResumeDelay = timing.writerAPIReturn.duration(to: mainActorResume).milliseconds
        signposter.emitEvent("variationMainActorResumed", id: signpostID)
        let syncAfter = syncActivity
        let syncOverall = syncBefore.isActive || syncAfter.isActive ? "active" : "idle"
        AppLog.performance.log(
          "variation-switch correlation=\(correlationToken, privacy: .public) writer-wait=\(writerWait, format: .fixed(precision: 1))ms sql=\(sqlDuration, format: .fixed(precision: 1))ms writer-api-return=\(writerAPIReturn, format: .fixed(precision: 1))ms main-actor-resume=\(mainActorResumeDelay, format: .fixed(precision: 1))ms detail-fetch-animation=\(detailFetchAnimation, privacy: .public) sync=\(syncOverall, privacy: .public) sync-before=\(syncBefore.description, privacy: .public) sync-after=\(syncAfter.description, privacy: .public)"
        )
        signposter.endInterval("variationSwitch", interval)
      } catch {
        signposter.endInterval("variationSwitch", interval)
        errorMessage = String(describing: error)
        isShowingError = true
      }
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

private struct VariationWriteTiming: Sendable {
  let writeStart: ContinuousClock.Instant
  let sqlDone: ContinuousClock.Instant
  let writerAPIReturn: ContinuousClock.Instant
}

@concurrent
private func writeActiveVariation(
  _ variationID: RecipeVariation.ID?,
  recipeID: Recipe.ID,
  database: any DatabaseWriter,
  now: Date,
  makeUUID: @escaping @Sendable () -> UUID,
  clock: ContinuousClock,
  signposter: OSSignposter,
  signpostID: OSSignpostID
) async throws -> VariationWriteTiming {
  let timing = try await database.write { db in
    let writeStart = clock.now
    signposter.emitEvent("writer-wait", id: signpostID)
    try RecipeRepository.setActiveVariation(
      variationID,
      recipeID: recipeID,
      in: db,
      now: now,
      uuid: makeUUID
    )
    let sqlDone = clock.now
    signposter.emitEvent("variationSQLDone", id: signpostID)
    return (writeStart, sqlDone)
  }
  let writerAPIReturn = clock.now
  signposter.emitEvent("variationWriterAPIReturn", id: signpostID)
  return VariationWriteTiming(
    writeStart: timing.0,
    sqlDone: timing.1,
    writerAPIReturn: writerAPIReturn
  )
}

private extension Duration {
  var milliseconds: Double {
    Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}
