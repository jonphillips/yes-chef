import Foundation

/// An opaque reference to an admitted Yes Chef recipe, returned to Cockpit so it can resolve its Find.
/// Machine-only; never shown to the cook. Backed by the recipe's UUID string but treated as opaque on
/// the Cockpit side — custody stays per-app (the Yes Chef recipe is a wholly separate record).
public struct FindRecipeRef: Equatable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(_ recipeID: UUID) {
    self.rawValue = recipeID.uuidString
  }
}

/// Why a portion of a referral was not admitted. A decline — **including a duplicate** — is a
/// first-class, valuable outcome (the quality signal extraction has never had), not an error.
public enum FindDeclineReason: Equatable, Sendable {
  /// Extraction found no recipe in the body (S-y1's 0-recipe path). A clean decline, not a failure.
  case noRecipeFound
  /// A recipe in the body already exists in the library.
  case duplicate
  /// The cook dismissed the referral (or a candidate within it) without saving.
  case dismissed
  /// Extraction failed for a stated reason; the string is a diagnostic, not shown to the cook.
  case extractionFailed(String)
}

/// One outcome within a referral's verdict. A single referral may yield **N admitted + M declined**.
public enum FindOutcome: Equatable, Sendable {
  case admitted(FindRecipeRef)
  case declined(FindDeclineReason)
}

/// The **set-valued** verdict for one referral, keyed by its opaque `referralID`. Built deterministically
/// and emitted at the moment of admit/decline via ``FindReturnEmitter``; Cockpit resolves its Find from
/// it with zero cook housekeeping on either side.
///
/// This is the frozen return *shape*. It is deliberately independent of the return *transport* (App-Group
/// dead-drop vs. `cockpit://` foreground hop), which is decided later behind ``FindReturnEmitter``.
public struct FindVerdict: Equatable, Sendable {
  public let referralID: String
  public let outcomes: [FindOutcome]

  public init(referralID: String, outcomes: [FindOutcome]) {
    self.referralID = referralID
    self.outcomes = outcomes
  }

  public var admitted: [FindRecipeRef] {
    outcomes.compactMap { outcome in
      guard case let .admitted(ref) = outcome else { return nil }
      return ref
    }
  }

  public var declines: [FindDeclineReason] {
    outcomes.compactMap { outcome in
      guard case let .declined(reason) = outcome else { return nil }
      return reason
    }
  }

  /// A whole-referral decline (0 recipes found, or the cook dismissed) — the common non-admit shape.
  public static func declined(referralID: String, _ reason: FindDeclineReason) -> FindVerdict {
    FindVerdict(referralID: referralID, outcomes: [.declined(reason)])
  }
}
