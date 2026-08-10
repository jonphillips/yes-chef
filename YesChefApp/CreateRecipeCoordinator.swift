import Dependencies
import Foundation
import Observation

/// Transient foreground routing for text delivered from an App Intent into the resident Create Recipe
/// session. This is deliberately separate from `HandoffReviewCoordinator`: this path creates a new
/// recipe proposal and never has a handoff subject or canonical write (ADR-0053 Amd2-D2/D4).
@Observable
@MainActor
final class CreateRecipeCoordinator {
  struct StagedText: Equatable {
    let id: UUID
    let text: String
  }

  @ObservationIgnored @Dependency(\.uuid) private var uuid
  private(set) var stagedText: StagedText?

  /// Keeps the transport payload in memory only until the app root can select Create Recipe and apply it
  /// to the live session. The content is intentionally not normalized so source fidelity is retained.
  func stage(text: String) {
    stagedText = StagedText(id: uuid(), text: text)
  }

  /// Applies a staged payload to the resident session. A blank session can safely use the ordinary paste
  /// seam and extract immediately. An existing session instead receives an explicit offer; it is never
  /// overwritten or auto-extracted over.
  func applyStagedText(to model: CreateRecipeModel) async {
    guard let stagedText else { return }

    if model.isEmpty {
      model.pastedTextReceived([stagedText.text])
      await model.extractButtonTapped()
    } else {
      model.offerIncomingPastedText(stagedText.text)
    }

    // Keep the task identity stable through fresh-session extraction. If another intent staged a newer
    // payload while extraction was suspended, leave that payload for the next app-root task to process.
    if self.stagedText?.id == stagedText.id {
      self.stagedText = nil
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
