import Dependencies
import Foundation
import Observation
import SQLiteData
import YesChefCore

// TEMPORARY: PROD-CUTOVER Step 10a
@MainActor
@Observable
final class InstructionStepRecoveryModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database

  private(set) var plan: InstructionStepRecovery.Plan?
  private(set) var isWorking = false
  private(set) var errorMessage: String?
  private(set) var insertedCount: Int?

  var hasPlan: Bool { plan != nil }
  var missingStepCount: Int { plan?.stepCount ?? 0 }
  var recipeCount: Int { plan?.recipeCount ?? 0 }
  var skippedCount: Int { plan?.skippedCount ?? 0 }

  func prepare(from url: URL) async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    plan = nil
    insertedCount = nil
    errorMessage = nil
    let hasSecurityScope = url.startAccessingSecurityScopedResource()
    defer {
      if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
    }
    do {
      plan = try InstructionStepRecovery.plan(from: url, in: database)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func apply() async {
    guard let plan, !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      insertedCount = try InstructionStepRecovery.apply(plan, in: database)
      self.plan = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func dismissResult() {
    insertedCount = nil
    errorMessage = nil
  }

  func recordImportFailure(_ error: any Error) {
    errorMessage = error.localizedDescription
  }

  func discardPlan() {
    plan = nil
  }
}
