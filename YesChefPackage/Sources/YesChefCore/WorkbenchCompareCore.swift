import Foundation

/// One recipe column in the Compare ingredient matrix. The working recipe is pinned first
/// (`role == .working`); candidates follow in their workbench order.
public struct IngredientMatrixColumn: Identifiable, Equatable, Sendable {
  public enum Role: Equatable, Sendable {
    case working
    case candidate
  }

  public let id: UUID
  public var title: String
  public var role: Role
  /// Authored lines from this recipe that could not be aligned onto a shared row — either they
  /// don't canonicalize, or two lines in this same recipe collide on one canonical key (ambiguous
  /// which represents the row). Kept per-column so a wrong alignment never masquerades as a match.
  public var otherLines: [String]

  public init(id: UUID, title: String, role: Role, otherLines: [String] = []) {
    self.id = id
    self.title = title
    self.role = role
    self.otherLines = otherLines
  }
}

/// One canonical-ingredient row spanning every column. `cells` is parallel to the matrix `columns`;
/// a `nil` cell means the ingredient is absent from that recipe — an honest blank, not a guess.
public struct IngredientMatrixRow: Identifiable, Equatable, Sendable {
  /// The canonical alignment key (`CanonicalIngredient.canonicalName`).
  public let id: String
  public var label: String
  public var cells: [String?]

  public init(id: String, label: String, cells: [String?]) {
    self.id = id
    self.label = label
    self.cells = cells
  }
}

/// An aligned ingredient-diff matrix over a workbench's working recipe + candidates. A pure read
/// over already-loaded `RecipeDetailData` — no fetch, no schema.
public struct IngredientComparison: Equatable, Sendable {
  public var columns: [IngredientMatrixColumn]
  public var rows: [IngredientMatrixRow]

  public init(columns: [IngredientMatrixColumn] = [], rows: [IngredientMatrixRow] = []) {
    self.columns = columns
    self.rows = rows
  }

  public var isEmpty: Bool { columns.isEmpty }
  public var hasOtherLines: Bool { columns.contains { !$0.otherLines.isEmpty } }
}

public enum WorkbenchCompare {
  /// Build the aligned ingredient matrix. Rows are canonical ingredients (working-recipe order first,
  /// then candidates left-to-right); each cell is that recipe's ingredient line as authored, or blank.
  /// Alignment is *only* on exact `CanonicalIngredient.canonicalName` match; anything that doesn't
  /// canonicalize — or collides ambiguously within a single recipe — drops to that column's "other"
  /// tail instead of being force-merged.
  public static func ingredientComparison(
    working: RecipeDetailData?,
    candidates: [RecipeDetailData]
  ) -> IngredientComparison {
    var sources: [(role: IngredientMatrixColumn.Role, detail: RecipeDetailData)] = []
    if let working {
      sources.append((.working, working))
    }
    sources.append(contentsOf: candidates.map { (.candidate, $0) })

    guard !sources.isEmpty else { return IngredientComparison() }

    var builds = sources.map { source in buildColumn(role: source.role, detail: source.detail) }

    // Ordered union of aligned keys: working recipe's order first, then each candidate's, appending
    // keys not seen yet. Preserves the reading order the cook expects while covering every recipe.
    var orderedKeys: [String] = []
    var seenKeys: Set<String> = []
    for build in builds {
      for key in build.orderedKeys where !seenKeys.contains(key) {
        seenKeys.insert(key)
        orderedKeys.append(key)
      }
    }

    // The row header is the coarse base (the comparison key made presentable), not any one recipe's
    // authored line — so the same row reads "Spinach" whether a column said "fresh" or "frozen"; the
    // form lives in the cells.
    let rows = orderedKeys.map { key -> IngredientMatrixRow in
      let cells = builds.map { $0.cellsByKey[key] }
      return IngredientMatrixRow(id: key, label: key.capitalizingFirstLetter, cells: cells)
    }

    // Free the per-build lookup tables now that rows are materialized.
    let columns = builds.map(\.column)
    builds.removeAll()

    return IngredientComparison(columns: columns, rows: rows)
  }

  private struct ColumnBuild {
    var column: IngredientMatrixColumn
    var orderedKeys: [String]
    var cellsByKey: [String: String]
  }

  private static func buildColumn(
    role: IngredientMatrixColumn.Role,
    detail: RecipeDetailData
  ) -> ColumnBuild {
    let lines = detail.ingredientLines.filter { !$0.isHeader }

    // A key is only alignable in this recipe if exactly one line carries it; two lines sharing a
    // canonical key (e.g. "2 tomatoes" + "1 can crushed tomatoes") are ambiguous and both go to other.
    var keyCounts: [String: Int] = [:]
    for line in lines {
      if let key = line.comparisonAlignmentKey {
        keyCounts[key, default: 0] += 1
      }
    }

    var orderedKeys: [String] = []
    var cellsByKey: [String: String] = [:]
    var otherLines: [String] = []

    for line in lines {
      guard let text = line.comparisonCellText else { continue }
      if let key = line.comparisonAlignmentKey, keyCounts[key] == 1 {
        cellsByKey[key] = text
        orderedKeys.append(key)
      } else {
        otherLines.append(text)
      }
    }

    return ColumnBuild(
      column: IngredientMatrixColumn(
        id: detail.recipe.id,
        title: detail.recipe.title,
        role: role,
        otherLines: otherLines
      ),
      orderedKeys: orderedKeys,
      cellsByKey: cellsByKey
    )
  }
}

private extension IngredientLine {
  /// The ingredient line as authored, for a matrix cell. `nil` when there's nothing to show.
  var comparisonCellText: String? {
    originalText.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyCompareText
  }

  /// The row-alignment key for the matrix — the **coarse** compare key (drops form/state words), not
  /// the cached grocery `canonicalName`. Computed on read; no schema, no cache.
  var comparisonAlignmentKey: String? {
    CanonicalIngredient.comparisonKey(item ?? originalText)
  }
}

private extension String {
  var nonEmptyCompareText: String? { isEmpty ? nil : self }

  var capitalizingFirstLetter: String {
    guard let first else { return self }
    return first.uppercased() + dropFirst()
  }
}
