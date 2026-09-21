import Foundation

/// A cross-app recipe referral from Cockpit's Find (M6 Gate 5). Cockpit sends the whole readable body
/// plus provenance plus a fallible "this looks like a recipe" hint, and nothing more. **All** recipe
/// intelligence is Yes Chef's: parsing, LLM extraction, 0/1/N cardinality, dedup, merge, admission, and
/// the decline. See `docs/efforts/cockpit-find-handoff-receiver.md`.
///
/// - Important: `referralID` is an **opaque, machine-only** correlation token — never surface it to the
///   cook. `provenance.contentPieceToken` is opaque Cockpit custody state — round-trip it untouched.
public struct FindReferral: Codable, Equatable, Sendable {
  /// Opaque correlation token. Echoed back in the ``FindVerdict``; never shown to the cook.
  public let referralID: String

  /// The whole readable body, newsletter chrome and all. **Never assume it is one clean recipe** — it
  /// may contain 0, 1, or N recipes. Isolation and cardinality are Yes Chef's job (S-y1).
  public let rawText: String

  public let provenance: FindProvenance

  public init(referralID: String, rawText: String, provenance: FindProvenance) {
    self.referralID = referralID
    self.rawText = rawText
    self.provenance = provenance
  }
}

/// Source context Cockpit attaches to a referral. Every field is an advisory hint for the cook's review
/// **except** ``contentPieceToken``, which is opaque Cockpit custody state to be echoed back untouched.
/// Yes Chef never learns Cockpit's schema and never interprets these beyond display.
public struct FindProvenance: Codable, Equatable, Sendable {
  public var sender: String?
  public var publisher: String?
  public var arrivalDate: Date?
  /// `List-ID` / newsletter series identifier, when present.
  public var seriesID: String?
  /// Opaque Cockpit `ContentPiece` token. Round-trip it untouched; Yes Chef never parses it.
  public var contentPieceToken: String?
  /// Cockpit's why-it-mattered note, shown to the cook for context during review.
  public var note: String?
  /// Small advisory values from Cockpit. Yes Chef does not use them for recipe decisions.
  public var hints: [String: String]

  public init(
    sender: String? = nil,
    publisher: String? = nil,
    arrivalDate: Date? = nil,
    seriesID: String? = nil,
    contentPieceToken: String? = nil,
    note: String? = nil,
    hints: [String: String] = [:]
  ) {
    self.sender = sender
    self.publisher = publisher
    self.arrivalDate = arrivalDate
    self.seriesID = seriesID
    self.contentPieceToken = contentPieceToken
    self.note = note
    self.hints = hints
  }
}
