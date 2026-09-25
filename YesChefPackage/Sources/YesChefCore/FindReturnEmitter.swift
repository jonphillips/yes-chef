import Dependencies
import Foundation

/// The transport seam for returning a ``FindVerdict`` to Cockpit at the moment of admit/decline
/// (M6 Gate 5, return half). Modeled as a closure-struct dependency client to match the house idiom
/// (see `RecipeExtractionClient`), not a `protocol`.
///
/// The live value atomically writes to the pair-scoped App Group mailbox. The seam keeps transport
/// behavior replaceable in tests without moving filesystem logic into the app model. This path is
/// intentionally separate from the `AIHandoff*` types, which serve external-chat round trips.
///
/// - Note: This is intentionally **not** entangled with the `AIHandoff*` token machinery — that axis is
///   the outboard-to-external-chat (copy prompt / paste result) flow. This is app-to-app; keep it separate.
public struct FindReturnEmitter: Sendable {
  public var emit: @Sendable (_ verdict: FindVerdict) async throws -> Void

  public init(emit: @escaping @Sendable (_ verdict: FindVerdict) async throws -> Void) {
    self.emit = emit
  }

  public func callAsFunction(_ verdict: FindVerdict) async throws {
    try await emit(verdict)
  }
}

extension FindReturnEmitter: DependencyKey {
  public static var liveValue: FindReturnEmitter {
    FindReturnEmitter { verdict in
      guard let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.jonphillips.cockpit-yeschef"
      ) else { throw FindMailboxError.sharedContainerUnavailable }
      try FindReferralMailbox(rootURL: container).write(verdict: verdict)
    }
  }

  /// Silent no-op for tests and previews. Tests that assert on the verdict should inject their own
  /// recording emitter (see `FindReturnEmitterTests`) rather than reading the log.
  public static var testValue: FindReturnEmitter {
    FindReturnEmitter { _ in }
  }
}

extension DependencyValues {
  public var findReturnEmitter: FindReturnEmitter {
    get { self[FindReturnEmitter.self] }
    set { self[FindReturnEmitter.self] = newValue }
  }
}
