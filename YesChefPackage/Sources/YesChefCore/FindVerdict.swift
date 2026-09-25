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
/// The frozen return shape travels as a versioned JSON message through the Cockpit pair mailbox.
public struct FindVerdict: Codable, Equatable, Sendable {
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

  private enum CodingKeys: String, CodingKey { case version, referralID, outcomes }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try FindReferral.validateVersion(in: values)
    referralID = try values.decode(String.self, forKey: .referralID)
    outcomes = try values.decode([FindOutcome].self, forKey: .outcomes)
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(1, forKey: .version)
    try values.encode(referralID, forKey: .referralID)
    try values.encode(outcomes, forKey: .outcomes)
  }
}

extension FindOutcome: Codable {
  private enum CodingKeys: String, CodingKey { case kind, recipeRef, reason, detail }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    switch try values.decode(String.self, forKey: .kind) {
    case "admitted":
      self = .admitted(FindRecipeRef(rawValue: try values.decode(String.self, forKey: .recipeRef)))
    case "declined":
      let reason = try values.decode(String.self, forKey: .reason)
      switch reason {
      case "noRecipeFound": self = .declined(.noRecipeFound)
      case "duplicate": self = .declined(.duplicate)
      case "dismissed": self = .declined(.dismissed)
      case "extractionFailed": self = .declined(.extractionFailed(try values.decode(String.self, forKey: .detail)))
      default: throw Self.invalidValue(reason, codingPath: values.codingPath + [CodingKeys.reason])
      }
    default:
      throw Self.invalidValue(try values.decode(String.self, forKey: .kind), codingPath: values.codingPath + [CodingKeys.kind])
    }
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .admitted(recipeRef):
      try values.encode("admitted", forKey: .kind)
      try values.encode(recipeRef.rawValue, forKey: .recipeRef)
    case let .declined(reason):
      try values.encode("declined", forKey: .kind)
      switch reason {
      case .noRecipeFound: try values.encode("noRecipeFound", forKey: .reason)
      case .duplicate: try values.encode("duplicate", forKey: .reason)
      case .dismissed: try values.encode("dismissed", forKey: .reason)
      case let .extractionFailed(detail):
        try values.encode("extractionFailed", forKey: .reason)
        try values.encode(detail, forKey: .detail)
      }
    }
  }

  private static func invalidValue(_ value: String, codingPath: [any CodingKey]) -> DecodingError {
    .dataCorrupted(.init(codingPath: codingPath, debugDescription: "Unknown Find outcome value: \(value)"))
  }
}

extension FindRecipeRef: Codable {
  public init(from decoder: Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    try value.encode(rawValue)
  }
}
