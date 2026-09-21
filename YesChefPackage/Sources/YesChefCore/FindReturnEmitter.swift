import Dependencies
import Foundation

/// The transport seam for returning a ``FindVerdict`` to Cockpit at the moment of admit/decline
/// (M6 Gate 5, return half). Modeled as a closure-struct dependency client to match the house idiom
/// (see `RecipeExtractionClient`), not a `protocol`.
///
/// **Why a seam and not a direct call.** No public API lets Yes Chef invoke Cockpit's registered App
/// Intent silently — App Intents surface to the *system* (Shortcuts/Siri/Spotlight/widgets), not to peer
/// apps (2026-09-21 architect re-review; see the effort doc's re-review section). So the verdict is
/// decoupled from *how it travels*. The real conformance is one of two swappable transports, decided
/// later and injected by the app layer:
///
/// - **App-Group verdict dead-drop** — write the verdict to a shared-container mailbox keyed by
///   `referralID`; Cockpit reads it on next foreground. Preserves the silent / zero-housekeeping promise.
/// - **`cockpit://` foreground hop** — open Cockpit once carrying the whole N/M verdict; costs one
///   foreground blink per referral.
///
/// Until that fork resolves, ``liveValue`` is a **no-op logging stub**: S-y1 and the coordinator threading
/// build and test against this seam now, and the transport becomes a one-line `$0.findReturnEmitter = …`
/// override in the app's dependency preparation.
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
  /// No-op stub until the return-transport fork is decided. It records the verdict to `AppLog.handoff`
  /// so the round-trip is observable during a device pass, but it does **not** reach Cockpit. The app
  /// overrides `$0.findReturnEmitter` with the real transport once the fork resolves.
  public static var liveValue: FindReturnEmitter {
    FindReturnEmitter { verdict in
      AppLog.handoff.log(
        """
        FindReturnEmitter stub: no transport wired — verdict for referral \
        \(verdict.referralID, privacy: .public) NOT delivered to Cockpit \
        (\(verdict.admitted.count, privacy: .public) admitted, \(verdict.declines.count, privacy: .public) declined)
        """
      )
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
