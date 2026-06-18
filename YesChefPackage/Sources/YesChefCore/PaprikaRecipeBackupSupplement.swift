import Foundation
import SQLiteData

public struct PaprikaRecipeBackupRecord: Equatable, Sendable {
  public var name: String
  public var sourceName: String?
  public var sourceURL: String?
  public var created: Date

  public init(
    name: String,
    sourceName: String? = nil,
    sourceURL: String? = nil,
    created: Date
  ) {
    self.name = name
    self.sourceName = sourceName
    self.sourceURL = sourceURL
    self.created = created
  }
}

public struct PaprikaRecipeBackupParseResult: Equatable, Sendable {
  public var records: [PaprikaRecipeBackupRecord]
  public var skippedEntryCount: Int

  public init(records: [PaprikaRecipeBackupRecord], skippedEntryCount: Int = 0) {
    self.records = records
    self.skippedEntryCount = skippedEntryCount
  }
}

public struct PaprikaRecipeBackupSupplementSummary: Equatable, Sendable {
  public var backupRecipeCount: Int
  public var matchedRecipeCount: Int
  public var updatedRecipeCount: Int
  public var unchangedRecipeCount: Int
  public var ambiguousRecipeCount: Int
  public var unmatchedRecipeCount: Int
  public var skippedRecordCount: Int

  public init(
    backupRecipeCount: Int = 0,
    matchedRecipeCount: Int = 0,
    updatedRecipeCount: Int = 0,
    unchangedRecipeCount: Int = 0,
    ambiguousRecipeCount: Int = 0,
    unmatchedRecipeCount: Int = 0,
    skippedRecordCount: Int = 0
  ) {
    self.backupRecipeCount = backupRecipeCount
    self.matchedRecipeCount = matchedRecipeCount
    self.updatedRecipeCount = updatedRecipeCount
    self.unchangedRecipeCount = unchangedRecipeCount
    self.ambiguousRecipeCount = ambiguousRecipeCount
    self.unmatchedRecipeCount = unmatchedRecipeCount
    self.skippedRecordCount = skippedRecordCount
  }
}

extension RecipeRepository {
  public static func supplementCreatedDates(
    from backupRecords: [PaprikaRecipeBackupRecord],
    in db: Database
  ) throws -> PaprikaRecipeBackupSupplementSummary {
    let recipes = try Recipe.fetchAll(db)
      .filter { !$0.archived }
    let sourcesByRecipeID = try Dictionary(
      grouping: RecipeSource.fetchAll(db),
      by: \.recipeID
    )
    let recipesByNormalizedName = Dictionary(
      grouping: recipes,
      by: { normalizedRecipeName($0.title) }
    )

    var summary = PaprikaRecipeBackupSupplementSummary(backupRecipeCount: backupRecords.count)
    var handledRecipeIDs: Set<Recipe.ID> = []

    for record in backupRecords {
      let normalizedName = normalizedRecipeName(record.name)
      guard !normalizedName.isEmpty else {
        summary.skippedRecordCount += 1
        continue
      }

      let candidates = recipesByNormalizedName[normalizedName] ?? []
      guard !candidates.isEmpty else {
        summary.unmatchedRecipeCount += 1
        continue
      }

      guard let recipe = match(record, candidates: candidates, sourcesByRecipeID: sourcesByRecipeID) else {
        summary.ambiguousRecipeCount += 1
        continue
      }

      guard !handledRecipeIDs.contains(recipe.id) else {
        summary.skippedRecordCount += 1
        continue
      }

      summary.matchedRecipeCount += 1
      if recipe.dateCreated == record.created {
        summary.unchangedRecipeCount += 1
      } else {
        try Recipe.find(recipe.id).update {
          $0.dateCreated = record.created
        }
        .execute(db)
        summary.updatedRecipeCount += 1
      }
      handledRecipeIDs.insert(recipe.id)
    }

    return summary
  }

  private static func match(
    _ record: PaprikaRecipeBackupRecord,
    candidates: [Recipe],
    sourcesByRecipeID: [Recipe.ID: [RecipeSource]]
  ) -> Recipe? {
    if candidates.count == 1 {
      return candidates[0]
    }

    guard let recordSourceURL = normalizedSourceURL(record.sourceURL) else { return nil }
    let sourceMatches = candidates.filter { recipe in
      (sourcesByRecipeID[recipe.id] ?? []).contains { source in
        normalizedSourceURL(source.url) == recordSourceURL
      }
    }
    return sourceMatches.count == 1 ? sourceMatches[0] : nil
  }

  private static func normalizedRecipeName(_ value: String) -> String {
    let folded = value
      .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    let words = folded.unicodeScalars.reduce(into: [String]()) { words, scalar in
      if CharacterSet.alphanumerics.contains(scalar) {
        if words.isEmpty || words[words.count - 1] == " " {
          words.append(String(scalar))
        } else {
          words[words.count - 1].append(String(scalar))
        }
      } else if words.last != " " {
        words.append(" ")
      }
    }
    return words
      .joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func normalizedSourceURL(_ value: String?) -> String? {
    guard var value = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased(),
      !value.isEmpty
    else { return nil }

    while value.hasSuffix("/") {
      value.removeLast()
    }
    return value
  }
}
