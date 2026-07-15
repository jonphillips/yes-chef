import Dependencies
import Observation
import SwiftUI
import UIKit
import YesChefCore

@Observable
@MainActor
final class HandoffInAppTransport {
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.handoffReviewCoordinator) private var handoffReviewCoordinator
  @ObservationIgnored @Dependency(\.uuid) private var uuid

  var errorMessage: String?
  var isShowingError = false
  var unmatchedResult: String?
  var unmatchedSource: HandoffExportSource?
  var isShowingUnmatchedConfirmation = false

  func copyPrompt(for source: HandoffExportSource) async {
    do {
      let handoff = try await HandoffAppOperations.export(
        source: source,
        mode: .discuss,
        in: database,
        now: now,
        handoffID: uuid()
      )
      UIPasteboard.general.string = handoff.prompt
    } catch {
      present(error)
    }
  }

  func stageReview(for result: String, source: HandoffExportSource) async {
    do {
      guard let routedText = AIHandoffToken.stripping(from: result) else {
        presentUnmatched(result: result, source: source)
        return
      }
      guard let handoff = try await database.read({ db in
        try AIHandoffRepository.handoff(id: routedText.handoffID, in: db)
      }), source.matches(handoff) else {
        presentUnmatched(result: result, source: source)
        return
      }
      let review = try await HandoffAppOperations.stageReview(
        handoffID: handoff.id,
        result: result,
        in: database,
        now: now
      )
      handoffReviewCoordinator.present(review)
    } catch {
      present(error)
    }
  }

  func pastedResultsReceived(_ results: [String], source: HandoffExportSource) async {
    guard let result = results.first, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      errorMessage = "No handoff result was pasted."
      isShowingError = true
      return
    }
    await stageReview(for: result, source: source)
  }

  func reviewUnmatchedResult() async {
    guard let unmatchedResult, let unmatchedSource else { return }
    dismissUnmatchedConfirmation()

    do {
      let review = try await HandoffAppOperations.stageReviewForKnownSource(
        source: unmatchedSource,
        result: unmatchedResult,
        in: database,
        now: now,
        handoffID: uuid()
      )
      handoffReviewCoordinator.present(review)
    } catch {
      present(error)
    }
  }

  func dismissUnmatchedConfirmation() {
    unmatchedResult = nil
    unmatchedSource = nil
    isShowingUnmatchedConfirmation = false
  }

  private func present(_ error: Error) {
    errorMessage = String(describing: error)
    isShowingError = true
  }

  private func presentUnmatched(result: String, source: HandoffExportSource) {
    unmatchedResult = result
    unmatchedSource = source
    isShowingUnmatchedConfirmation = true
  }
}

struct HandoffCopyPasteControls: View {
  let source: HandoffExportSource
  let transport: HandoffInAppTransport

  var body: some View {
    HStack(spacing: 8) {
      Button {
        Task {
          await transport.copyPrompt(for: source)
        }
      } label: {
        Label("Copy Prompt", systemImage: "sparkles.square.filled.on.square")
      }

      PasteButton(payloadType: String.self) { results in
        Task {
          await transport.pastedResultsReceived(results, source: source)
        }
      }
      .accessibilityLabel("Paste Result")
    }
  }
}

private struct HandoffTransportAlert: ViewModifier {
  let transport: HandoffInAppTransport

  func body(content: Content) -> some View {
    @Bindable var transport = transport

    content.alert("Could Not Process Handoff", isPresented: $transport.isShowingError) {
      Button("OK") {}
    } message: {
      Text(transport.errorMessage ?? "Something went wrong.")
    }
    .alert("Unmatched Handoff", isPresented: $transport.isShowingUnmatchedConfirmation) {
      Button("Review Anyway") {
        Task {
          await transport.reviewUnmatchedResult()
        }
      }
      Button("Cancel", role: .cancel) {
        transport.dismissUnmatchedConfirmation()
      }
    } message: {
      Text(
        "The handoff ID is missing or doesn't match this \(transport.unmatchedSource?.unmatchedSubject ?? "item"). Review the pasted result against it anyway — check it carefully before committing."
      )
    }
  }
}

extension View {
  func handoffTransportAlert(_ transport: HandoffInAppTransport) -> some View {
    modifier(HandoffTransportAlert(transport: transport))
  }
}
