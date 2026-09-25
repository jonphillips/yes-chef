import Foundation

/// File operations for the pair-scoped Cockpit mailbox. The root URL is supplied by the app-group
/// boundary; this type keeps filename validation, wire encoding, and atomic writes deterministic.
public struct FindReferralMailbox: Sendable {
  public let rootURL: URL

  public init(rootURL: URL) {
    self.rootURL = rootURL
  }

  public func readReferral(id: String) throws -> FindReferral? {
    let url = try messageURL(folder: "find-referrals", id: id)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(FindReferral.self, from: Data(contentsOf: url))
  }

  public func deleteReferral(id: String) throws {
    let url = try messageURL(folder: "find-referrals", id: id)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }

  public func write(verdict: FindVerdict) throws {
    let url = try messageURL(folder: "find-verdicts", id: verdict.referralID)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(verdict).write(to: url, options: .atomic)
  }

  fileprivate func validateReferralID(_ id: String) throws {
    guard !id.isEmpty, id != ".", id != "..",
          id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.").contains($0) })
    else { throw FindMailboxError.invalidReferralID }
  }

  private func messageURL(folder: String, id: String) throws -> URL {
    try validateReferralID(id)
    return rootURL.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("\(id).json")
  }
}

public enum FindMailboxError: Error, Equatable {
  case invalidReferralID
  case sharedContainerUnavailable
  case outstandingReferralPending
}

/// The only URL form accepted from Cockpit. This is a door into the existing Create Recipe coordinator,
/// not a general navigation router.
public enum FindReferralDoor {
  public static func referralID(from url: URL) -> String? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.scheme == "yeschef",
          components.host == "find-referral",
          components.path.isEmpty,
          let items = components.queryItems,
          items.count == 1,
          items[0].name == "id",
          let id = items[0].value,
          !id.isEmpty,
          (try? FindReferralMailbox(rootURL: URL(fileURLWithPath: "/")).validateReferralID(id)) != nil
    else { return nil }
    return id
  }
}
