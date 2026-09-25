import Dependencies
import Foundation
import Observation
import YesChefCore

/// Transient foreground routing for text delivered from an App Intent into the resident Create Recipe
/// session. This is deliberately separate from `HandoffReviewCoordinator`: this path creates a new
/// recipe proposal and never has a handoff subject or canonical write (ADR-0053 Amd2-D2/D4).
@Observable
@MainActor
final class CreateRecipeCoordinator {
  static let outstandingReferralDefaultsKey = "cockpitFindOutstandingReferralID"

  struct StagedText: Equatable {
    let id: UUID
    let text: String
    let referral: FindReferral?
  }

  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored @Dependency(\.findReturnEmitter) private var findReturnEmitter
  private let defaults: UserDefaults
  private(set) var stagedText: StagedText?
  private(set) var referralID: String?
  private var savingReferralID: String?
  private var savingReferralWasAbandoned = false

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Keeps the transport payload in memory only until the app root can select Create Recipe and apply it
  /// to the live session. The content is intentionally not normalized so source fidelity is retained.
  func stage(text: String) async {
    await reconcileOutstandingReferral()
    referralID = nil
    stagedText = StagedText(id: uuid(), text: text, referral: nil)
  }

  @discardableResult
  func stage(referral: FindReferral) async -> Bool {
    if let activeReferralID = referralID {
      // Reopening the same referral should preserve its live review session.
      if activeReferralID == referral.referralID { return true }
      await declineReferral(.dismissed)
    } else if let persistedReferralID = defaults.string(forKey: Self.outstandingReferralDefaultsKey),
              persistedReferralID != referral.referralID {
      // A prior process may have died before completing review. Dismiss that stale referral, then
      // continue intake even if writing its verdict fails; the newly received id becomes outstanding.
      await emit(.declined(referralID: persistedReferralID, .dismissed))
    }
    referralID = referral.referralID
    stagedText = StagedText(id: uuid(), text: referral.rawText, referral: referral)
    defaults.set(referral.referralID, forKey: Self.outstandingReferralDefaultsKey)
    return true
  }

  @discardableResult
  func receiveReferral(id: String, from mailbox: FindReferralMailbox) async throws -> Bool {
    guard let referral = try mailbox.readReferral(id: id) else { return false }
    guard await stage(referral: referral) else { throw FindMailboxError.outstandingReferralPending }
    try mailbox.deleteReferral(id: id)
    return true
  }

  /// Applies a staged payload to the resident session. A blank session can safely use the ordinary paste
  /// seam and extract immediately. An existing session instead receives an explicit offer; it is never
  /// overwritten or auto-extracted over.
  func applyStagedText(to model: CreateRecipeModel) async {
    guard let stagedText else { return }

    if model.isEmpty {
      model.beginReferral(stagedText.referral)
      model.pastedTextReceived([stagedText.text])
      await extractButtonTapped(for: model)
    } else {
      model.offerIncomingPastedText(stagedText.text, referral: stagedText.referral)
    }

    // Keep the task identity stable through fresh-session extraction. If another intent staged a newer
    // payload while extraction was suspended, leave that payload for the next app-root task to process.
    if self.stagedText?.id == stagedText.id {
      self.stagedText = nil
    }
  }

  func extractButtonTapped(for model: CreateRecipeModel) async {
    await model.extractButtonTapped()
    guard let referralID else { return }
    if model.foundNoRecipe {
      await resolve(.declined(referralID: referralID, .noRecipeFound))
    } else if let extractionError = model.extractionError {
      await resolve(.declined(referralID: referralID, .extractionFailed(extractionError)))
    }
  }

  func saveButtonTapped(for model: CreateRecipeModel) async -> Recipe.ID? {
    let savingReferralID = referralID
    self.savingReferralID = savingReferralID
    savingReferralWasAbandoned = false
    guard let recipeID = await model.saveButtonTapped() else {
      let shouldDismiss = savingReferralWasAbandoned
      self.savingReferralID = nil
      savingReferralWasAbandoned = false
      if shouldDismiss, let savingReferralID {
        await emit(.declined(referralID: savingReferralID, .dismissed))
      }
      return nil
    }
    guard let savingReferralID else { return recipeID }

    await resolve(
      FindVerdict(
        referralID: savingReferralID,
        outcomes: [.admitted(FindRecipeRef(recipeID))]
      )
    )
    self.savingReferralID = nil
    savingReferralWasAbandoned = false
    return recipeID
  }

  func declineReferral(_ reason: FindDeclineReason = .dismissed) async {
    guard let referralID else { return }
    if savingReferralID == referralID {
      savingReferralWasAbandoned = true
      return
    }
    await resolve(.declined(referralID: referralID, reason))
  }

  /// Reconciles a referral when the cook leaves Create Recipe or another intake supersedes it. A save
  /// already in flight is allowed to finish and admit; if that save fails, the abandonment becomes the
  /// resulting dismissal instead.
  func abandonOutstandingReferral() async {
    await declineReferral(.dismissed)
  }

  /// Called once after dependency preparation at process launch. Only the correlation id survives a
  /// crash; without an in-memory review session, that referral is now a dismissal.
  func reconcilePersistedReferralAfterLaunch() async {
    guard referralID == nil,
          let referralID = defaults.string(forKey: Self.outstandingReferralDefaultsKey)
    else { return }
    await emit(.declined(referralID: referralID, .dismissed), preservingLiveSession: true)
  }

  private func reconcileOutstandingReferral() async {
    await declineReferral(.dismissed)
  }

  private func resolve(_ verdict: FindVerdict) async {
    guard referralID == verdict.referralID || savingReferralID == verdict.referralID else { return }
    if referralID == verdict.referralID {
      referralID = nil
    }
    await emit(verdict)
  }

  private func emit(_ verdict: FindVerdict, preservingLiveSession: Bool = false) async {
    do {
      try await findReturnEmitter(verdict)
      if defaults.string(forKey: Self.outstandingReferralDefaultsKey) == verdict.referralID,
         !preservingLiveSession || referralID != verdict.referralID {
        defaults.removeObject(forKey: Self.outstandingReferralDefaultsKey)
      }
    } catch {
      AppLog.handoff.error("Find verdict emission failed: \(String(describing: error), privacy: .public)")
    }
  }
}

extension CreateRecipeCoordinator: DependencyKey {
  nonisolated static var liveValue: CreateRecipeCoordinator {
    MainActor.assumeIsolated { CreateRecipeCoordinator() }
  }
}

extension DependencyValues {
  var createRecipeCoordinator: CreateRecipeCoordinator {
    get { self[CreateRecipeCoordinator.self] }
    set { self[CreateRecipeCoordinator.self] = newValue }
  }
}
