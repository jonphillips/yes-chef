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
  struct StagedText: Equatable {
    let id: UUID
    let text: String
    let referral: FindReferral?
  }

  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored @Dependency(\.findReturnEmitter) private var findReturnEmitter
  private(set) var stagedText: StagedText?
  private(set) var referralID: String?
  private var savingReferralID: String?
  private var savingReferralWasAbandoned = false

  /// Keeps the transport payload in memory only until the app root can select Create Recipe and apply it
  /// to the live session. The content is intentionally not normalized so source fidelity is retained.
  func stage(text: String) async {
    await reconcileOutstandingReferral()
    referralID = nil
    stagedText = StagedText(id: uuid(), text: text, referral: nil)
  }

  func stage(referral: FindReferral) async {
    await reconcileOutstandingReferral()
    referralID = referral.referralID
    stagedText = StagedText(id: uuid(), text: referral.rawText, referral: referral)
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

  private func emit(_ verdict: FindVerdict) async {
    do {
      try await findReturnEmitter(verdict)
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
