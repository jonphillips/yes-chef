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
  static let admittedReferralRecipeIDsDefaultsKey = "cockpitFindAdmittedRecipeIDs"

  struct StagedText: Equatable {
    let id: UUID
    let text: String
    let referral: FindReferral?
  }

  enum SaveResult {
    case failed
    case saved(recipeID: Recipe.ID, sessionComplete: Bool)
  }

  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored @Dependency(\.findReturnEmitter) private var findReturnEmitter
  private let defaults: UserDefaults
  private(set) var stagedText: StagedText?
  private(set) var referralID: String?
  private(set) var admittedRecipeIDs: [Recipe.ID] = []
  private var savingReferralID: String?
  private var savingReferralWasAbandoned = false
  private var savingReferralCloseReason: FindDeclineReason = .dismissed
  private var saveCompletionContinuation: CheckedContinuation<Void, Never>?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Keeps the transport payload in memory only until the app root can select Create Recipe and apply it
  /// to the live session. The content is intentionally not normalized so source fidelity is retained.
  func stage(text: String) async {
    await declineReferral(.dismissed)
    await waitForSaveToFinish()
    await reconcilePersistedReferral()
    referralID = nil
    admittedRecipeIDs = []
    stagedText = StagedText(id: uuid(), text: text, referral: nil)
  }

  @discardableResult
  func stage(referral: FindReferral) async -> Bool {
    if referralID == referral.referralID { return true }
    if referralID != nil {
      let activeReferralID = referralID
      await declineReferral(.dismissed)
      await waitForSaveToFinish()
      if let activeReferralID,
         defaults.string(forKey: Self.outstandingReferralDefaultsKey) == activeReferralID {
        return false
      }
    }
    if let persistedReferralID = defaults.string(forKey: Self.outstandingReferralDefaultsKey),
       persistedReferralID != referral.referralID {
      // A prior process may have died before completing review. Resolve its admitted set before
      // accepting the new referral. Keep both persisted values if the mailbox write fails.
      guard await closeReferral(id: persistedReferralID, reason: .dismissed) else { return false }
    }
    if defaults.string(forKey: Self.outstandingReferralDefaultsKey) == referral.referralID {
      admittedRecipeIDs = persistedAdmittedRecipeIDs
    } else {
      admittedRecipeIDs = []
    }
    referralID = referral.referralID
    stagedText = StagedText(id: uuid(), text: referral.rawText, referral: referral)
    defaults.set(referral.referralID, forKey: Self.outstandingReferralDefaultsKey)
    defaults.set(admittedRecipeIDs.map(\.uuidString), forKey: Self.admittedReferralRecipeIDsDefaultsKey)
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
    guard referralID != nil else { return }
    if model.foundNoRecipe {
      await declineReferral(.noRecipeFound)
    } else if let extractionError = model.extractionError {
      await declineReferral(.extractionFailed(extractionError))
    }
  }

  func saveButtonTapped(for model: CreateRecipeModel) async -> SaveResult {
    guard !model.isSavingDisabled else { return .failed }
    let savingReferralID = referralID
    if let savingReferralID {
      self.savingReferralID = savingReferralID
      savingReferralWasAbandoned = false
      savingReferralCloseReason = .dismissed
    }

    guard let recipeID = await model.saveButtonTapped() else {
      if let savingReferralID, savingReferralWasAbandoned {
        await finishSavingReferral(id: savingReferralID, reason: savingReferralCloseReason)
      } else {
        clearSavingReferral()
      }
      return .failed
    }

    if let savingReferralID {
      if !admittedRecipeIDs.contains(recipeID) {
        admittedRecipeIDs.append(recipeID)
      }
      defaults.set(admittedRecipeIDs.map(\.uuidString), forKey: Self.admittedReferralRecipeIDsDefaultsKey)
      if model.isSessionComplete || savingReferralWasAbandoned {
        await finishSavingReferral(id: savingReferralID, reason: savingReferralCloseReason)
      } else {
        clearSavingReferral()
      }
    }

    return .saved(recipeID: recipeID, sessionComplete: model.isSessionComplete)
  }

  func declineReferral(_ reason: FindDeclineReason = .dismissed) async {
    guard let referralID else { return }
    if savingReferralID == referralID {
      savingReferralWasAbandoned = true
      savingReferralCloseReason = reason
      return
    }
    await closeReferral(id: referralID, reason: reason)
  }

  /// Reconciles a referral when the cook leaves Create Recipe or another intake supersedes it. A save
  /// already in flight is allowed to finish and admit; if that save fails, the prior admitted set is closed.
  func abandonOutstandingReferral() async {
    await declineReferral(.dismissed)
  }

  /// Called once after dependency preparation at process launch. The referral id and admitted recipe ids
  /// survive a crash so a partial multi-save is returned accurately instead of being dismissed.
  func reconcilePersistedReferralAfterLaunch() async {
    guard referralID == nil,
          let referralID = defaults.string(forKey: Self.outstandingReferralDefaultsKey)
    else { return }
    await closeReferral(id: referralID, reason: .dismissed)
  }

  private func reconcilePersistedReferral() async {
    guard let referralID = defaults.string(forKey: Self.outstandingReferralDefaultsKey) else { return }
    await closeReferral(id: referralID, reason: .dismissed)
  }

  @discardableResult
  private func closeReferral(id: String, reason: FindDeclineReason) async -> Bool {
    if savingReferralID == id {
      savingReferralWasAbandoned = true
      savingReferralCloseReason = reason
      return false
    }
    let recipeIDs = referralID == id ? admittedRecipeIDs : persistedAdmittedRecipeIDs
    if referralID == id {
      referralID = nil
      admittedRecipeIDs = []
    }
    let verdict: FindVerdict
    if recipeIDs.isEmpty {
      verdict = .declined(referralID: id, reason)
    } else {
      verdict = FindVerdict(referralID: id, outcomes: recipeIDs.map { .admitted(FindRecipeRef($0)) })
    }
    return await emit(verdict)
  }

  private func finishSavingReferral(id: String, reason: FindDeclineReason) async {
    if referralID == id {
      referralID = nil
      admittedRecipeIDs = []
    }
    clearSavingReferral()
    await closeReferral(id: id, reason: reason)
    saveCompletionContinuation?.resume()
    saveCompletionContinuation = nil
  }

  private func clearSavingReferral() {
    savingReferralID = nil
    savingReferralWasAbandoned = false
    savingReferralCloseReason = .dismissed
  }

  private func waitForSaveToFinish() async {
    guard savingReferralID != nil else { return }
    await withCheckedContinuation { continuation in
      saveCompletionContinuation = continuation
    }
  }

  private var persistedAdmittedRecipeIDs: [Recipe.ID] {
    (defaults.stringArray(forKey: Self.admittedReferralRecipeIDsDefaultsKey) ?? []).compactMap { UUID(uuidString: $0) }
  }

  private func emit(_ verdict: FindVerdict) async -> Bool {
    do {
      try await findReturnEmitter(verdict)
      if defaults.string(forKey: Self.outstandingReferralDefaultsKey) == verdict.referralID {
        defaults.removeObject(forKey: Self.outstandingReferralDefaultsKey)
        defaults.removeObject(forKey: Self.admittedReferralRecipeIDsDefaultsKey)
      }
      return true
    } catch {
      AppLog.handoff.error("Find verdict emission failed: \(String(describing: error), privacy: .public)")
      return false
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
