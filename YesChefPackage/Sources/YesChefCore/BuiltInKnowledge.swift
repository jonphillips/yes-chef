import Foundation

/// Curated ingredient and grocery defaults shipped with the app.
public struct BuiltInKnowledge: Codable, Equatable, Sendable {
  public let version: Int
  public let aliases: [String: String]
  public let areas: [String: String]
  public let trips: [String: String]
  public let keepers: [String]
  public let pantryStaples: [String]

  public init(
    version: Int = 1,
    aliases: [String: String] = [:],
    areas: [String: String] = [:],
    trips: [String: String] = [:],
    keepers: [String] = [],
    pantryStaples: [String] = []
  ) {
    self.version = version
    self.aliases = aliases
    self.areas = areas
    self.trips = trips
    self.keepers = keepers
    self.pantryStaples = pantryStaples
  }

  public static let empty = BuiltInKnowledge()

  /// The bundled file is loaded once. A broken bundle reports an issue and leaves the app usable
  /// with empty built-in data, as required for a safe fallback.
  public static let current: BuiltInKnowledge = {
    do {
      guard let url = Bundle.module.url(forResource: "BuiltInKnowledge", withExtension: "json") else {
        throw ResourceError.missing
      }
      let data = try Data(contentsOf: url)
      let knowledge = try JSONDecoder().decode(BuiltInKnowledge.self, from: data)
      try knowledge.validate()
      return knowledge
    } catch {
      AppLog.dataIntegrity.error("built-in knowledge could not be loaded: \(String(describing: error), privacy: .public)")
      return .empty
    }
  }()

  public var seedAreas: [String: GroceryStoreArea] {
    areas.compactMapValues(GroceryStoreArea.normalized)
  }

  public func validate() throws {
    guard version > 0 else { throw ValidationError.invalidVersion }
    guard areas.values.allSatisfy({ GroceryStoreArea.normalized($0) != nil }) else {
      throw ValidationError.invalidArea
    }
    guard trips.values.allSatisfy({ GroceryTrip(rawValue: $0) != nil }) else {
      throw ValidationError.invalidTrip
    }
    for start in aliases.keys {
      var current = start
      var visited = Set<String>()
      while let next = aliases[current] {
        if next == current { break }
        guard visited.insert(current).inserted else { throw ValidationError.aliasCycle }
        guard aliases[next] == nil || aliases[next] == next else { throw ValidationError.aliasChain }
        current = next
      }
    }
  }

  private enum ResourceError: Error { case missing }

  enum ValidationError: Error {
    case invalidVersion, invalidArea, invalidTrip, aliasCycle, aliasChain
  }
}
