import Foundation
import SQLiteData

public struct KitchenKnowledgeExport: Codable, Equatable, Sendable {
  public enum Variant: String, Codable, Sendable { case production, dev }
  public struct NameFix: Codable, Equatable, Sendable {
    public let from: String
    public let to: String
  }
  public struct Area: Codable, Equatable, Sendable {
    public let name: String
    public let area: String
    public let source: GroceryAreaAssignment.Source
  }
  public struct Trip: Codable, Equatable, Sendable {
    public let name: String
    public let trip: GroceryTrip
  }

  public let exportedAt: Date
  public let variant: Variant
  public let nameFixes: [NameFix]
  public let areas: [Area]
  public let trips: [Trip]

  public static func build(
    in db: Database,
    exportedAt: Date,
    variant: Variant
  ) throws -> Self {
    let nameFixes = try IngredientNameFix.fetchAll(db)
      .sorted { $0.fromName < $1.fromName }
      .map { NameFix(from: $0.fromName, to: $0.toName) }
    let areas = try GroceryAreaAssignment.fetchAll(db)
      .filter { $0.source == .user || ($0.source == .model && $0.reviewedAt != nil) }
      .sorted { $0.canonicalName < $1.canonicalName }
      .map { Area(name: $0.canonicalName, area: $0.area, source: $0.source) }
    let trips = try GroceryTripAssignment.fetchAll(db)
      .sorted { $0.canonicalName < $1.canonicalName }
      .map { Trip(name: $0.canonicalName, trip: $0.trip) }
    return Self(exportedAt: exportedAt, variant: variant, nameFixes: nameFixes, areas: areas, trips: trips)
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }
}
