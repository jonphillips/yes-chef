import Foundation
import SQLiteData

public struct IngredientRangeBackfillReport: Equatable, Sendable {
  public var updatedIngredientLineIDs: [IngredientLine.ID]

  public init(updatedIngredientLineIDs: [IngredientLine.ID] = []) {
    self.updatedIngredientLineIDs = updatedIngredientLineIDs
  }

  public var hasFindings: Bool { !updatedIngredientLineIDs.isEmpty }

  public var logSummary: String {
    let ids = updatedIngredientLineIDs.map(\.uuidString).joined(separator: ",")
    return "ingredient-range-backfill updatedCount=\(updatedIngredientLineIDs.count) updatedIDs=[\(ids)]"
  }
}

extension RecipeRepository {
  /// Repairs existing range and hyphenated-size lines after the sync engine is installed, so the
  /// corrected parse fields are recorded and uploaded as ordinary synchronized writes.
  public static func reparseIngredientRanges(in db: Database) throws -> IngredientRangeBackfillReport {
    var report = IngredientRangeBackfillReport()
    let lines = try IngredientLine.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }

    for var line in lines where !line.isHeader {
      let rawLeadingQuantity = QuantityParser.leadingQuantity(in: line.originalText)
      let leadingIngredientAmount = QuantityParser.leadingIngredientAmount(in: line.originalText)
      let needsReparse = QuantityParser.leadingIngredientRange(in: line.originalText) != nil
        || (rawLeadingQuantity != nil && leadingIngredientAmount == nil)
      guard needsReparse else { continue }

      let parsed = IngredientParser.parse(line.originalText)
      let canonicalName = CanonicalIngredient.canonicalName(parsed.item ?? parsed.parsingText)
      let confidence: ParseConfidence = parsed.quantity == nil ? .low : .medium
      guard
        line.quantity != parsed.quantity
          || line.quantityText != parsed.quantityText
          || line.unit != parsed.unit
          || line.item != parsed.item
          || line.canonicalName != canonicalName
          || line.preparation != parsed.preparation
          || line.confidence != confidence
      else { continue }

      line.quantity = parsed.quantity
      line.quantityText = parsed.quantityText
      line.unit = parsed.unit
      line.item = parsed.item
      line.canonicalName = canonicalName
      line.preparation = parsed.preparation
      line.confidence = confidence
      try IngredientLine.upsert { line }.execute(db)
      report.updatedIngredientLineIDs.append(line.id)
    }

    return report
  }
}
