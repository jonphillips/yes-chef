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

  func stageReview(for result: String) async {
    do {
      let review = try await HandoffAppOperations.stageReview(
        handoffID: nil,
        result: result,
        in: database,
        now: now
      )
      handoffReviewCoordinator.present(review)
    } catch {
      present(error)
    }
  }

  private func present(_ error: Error) {
    errorMessage = String(describing: error)
    isShowingError = true
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
        Label("Copy Prompt", systemImage: "doc.on.doc")
      }

      PasteButton(payloadType: String.self) { results in
        guard let result = results.first else { return }
        Task {
          await transport.stageReview(for: result)
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
  }
}

extension View {
  func handoffTransportAlert(_ transport: HandoffInAppTransport) -> some View {
    modifier(HandoffTransportAlert(transport: transport))
  }
}
