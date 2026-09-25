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

  fileprivate enum CodingKeys: String, CodingKey { case version, referralID, rawText, provenance }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try Self.validateVersion(in: values)
    referralID = try values.decode(String.self, forKey: .referralID)
    rawText = try values.decode(String.self, forKey: .rawText)
    provenance = try values.decode(FindProvenance.self, forKey: .provenance)
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(1, forKey: .version)
    try values.encode(referralID, forKey: .referralID)
    try values.encode(rawText, forKey: .rawText)
    try values.encode(provenance, forKey: .provenance)
  }

  static func validateVersion<Key: CodingKey>(in values: KeyedDecodingContainer<Key>) throws {
    guard let versionKey = Key(stringValue: "version") else { return }
    let version = try values.decode(Int.self, forKey: versionKey)
    guard version == 1 else {
      throw DecodingError.dataCorruptedError(forKey: versionKey, in: values, debugDescription: "Unsupported Find referral version: \(version)")
    }
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

  private enum CodingKeys: String, CodingKey {
    case sender, publisher, arrivalDate, seriesID, contentPieceToken, note, hints
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    sender = try values.decodeIfPresent(String.self, forKey: .sender)
    publisher = try values.decodeIfPresent(String.self, forKey: .publisher)
    if let date = try values.decodeIfPresent(String.self, forKey: .arrivalDate) {
      arrivalDate = try FindWireDate.decode(date, codingPath: values.codingPath + [CodingKeys.arrivalDate])
    } else {
      arrivalDate = nil
    }
    seriesID = try values.decodeIfPresent(String.self, forKey: .seriesID)
    contentPieceToken = try values.decodeIfPresent(String.self, forKey: .contentPieceToken)
    note = try values.decodeIfPresent(String.self, forKey: .note)
    hints = try values.decodeIfPresent([String: String].self, forKey: .hints) ?? [:]
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encodeIfPresent(sender, forKey: .sender)
    try values.encodeIfPresent(publisher, forKey: .publisher)
    try values.encodeIfPresent(arrivalDate.map(FindWireDate.encode), forKey: .arrivalDate)
    try values.encodeIfPresent(seriesID, forKey: .seriesID)
    try values.encodeIfPresent(contentPieceToken, forKey: .contentPieceToken)
    try values.encodeIfPresent(note, forKey: .note)
    try values.encode(hints, forKey: .hints)
  }
}

private enum FindWireDate {
  static func encode(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  static func decode(_ value: String, codingPath: [any CodingKey]) throws -> Date {
    for options: ISO8601DateFormatter.Options in [
      [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime],
    ] {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = options
      if let date = formatter.date(from: value) { return date }
    }
    throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Invalid ISO-8601 date"))
  }
}
