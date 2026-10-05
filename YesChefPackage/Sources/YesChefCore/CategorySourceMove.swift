import Foundation
import SQLiteData

/// One-shot library cleanup: the "Cookbook" and "Chef" category groups were standing in for the recipe
/// source's Book title / Publication and Author. Values move into the source only when the field is empty (or
/// already holds the same value); everything else is reported and left untouched, tag included.
public struct CategorySourceMoveReport: Equatable, Sendable {
  public enum Group: String, CaseIterable, Equatable, Sendable {
    case cookbook
    case chef

    public var name: String {
      switch self {
      case .cookbook: "Cookbook"
      case .chef: "Chef"
      }
    }
  }

  public enum Field: String, CaseIterable, Equatable, Sendable {
    case bookTitle
    case publicationName
    case author

    /// The category group that stands in for this field.
    public var group: Group {
      switch self {
      case .bookTitle, .publicationName: .cookbook
      case .author: .chef
      }
    }

    public var fieldName: String {
      switch self {
      case .bookTitle: "Book title"
      case .publicationName: "Publication"
      case .author: "Author"
      }
    }
  }

  public enum Outcome: Equatable, Sendable {
    /// The field was empty; the category value fills it.
    case move
    /// The field already holds the same value; only the tag comes off.
    case alreadySet
    /// The field holds something else, so nothing changes.
    case fieldHasDifferentValue(existing: String)
    /// The recipe carries more than one category bound for the same field, so there is no single value to move.
    case multipleValues
    /// The recipe has more than one source record, so there is no single field to write.
    case multipleSourceRecords

    public var isProblem: Bool {
      switch self {
      case .move, .alreadySet: false
      case .fieldHasDifferentValue, .multipleValues, .multipleSourceRecords: true
      }
    }
  }

  public struct Entry: Equatable, Identifiable, Sendable {
    public var recipeID: Recipe.ID
    public var recipeTitle: String
    public var field: Field
    public var categoryNames: [String]
    public var outcome: Outcome

    public var id: String { "\(recipeID.uuidString)-\(field.rawValue)" }

    public init(recipeID: Recipe.ID, recipeTitle: String, field: Field, categoryNames: [String], outcome: Outcome) {
      self.recipeID = recipeID
      self.recipeTitle = recipeTitle
      self.field = field
      self.categoryNames = categoryNames
      self.outcome = outcome
    }
  }

  /// Cookbook values that start out routed to Publication; anything else goes to Book title until the caller
  /// says otherwise. Exact names only — "Milk Street Tuesday Nights" is a book, "Milk Street" is not.
  public static let knownPublications: [String] = [
    "America's Test Kitchen", "Bon Appétit", "Christopher Kimball's Milk Street", "Cook's Country",
    "Cook's Illustrated", "Epicurious", "Fine Cooking", "Food & Wine", "Food52", "Gourmet", "Milk Street",
    "New York Times", "NYT Cooking", "Saveur", "Serious Eats", "The New York Times", "Washington Post",
  ]

  public var missingGroups: [Group]
  /// Every distinct Cookbook value still tagged on a recipe, for choosing which ones are publications.
  public var cookbookValues: [String]
  public var entries: [Entry]

  public init(missingGroups: [Group] = [], cookbookValues: [String] = [], entries: [Entry] = []) {
    self.missingGroups = missingGroups
    self.cookbookValues = cookbookValues
    self.entries = entries
  }

  public var moveCount: Int { entries.filter { $0.outcome == .move }.count }
  public var alreadySetCount: Int { entries.filter { $0.outcome == .alreadySet }.count }
  public var problems: [Entry] { entries.filter(\.outcome.isProblem) }
  public var changeCount: Int { moveCount + alreadySetCount }

  public static func isKnownPublication(_ value: String) -> Bool {
    knownPublications.map(RecipeRepository.moveNormalized).contains(RecipeRepository.moveNormalized(value))
  }

  /// Plain text for sharing the problem list off the device.
  public var problemSummary: String {
    var lines = ["Cookbook/Chef → Book title/Publication/Author: \(problems.count) not moved"]
    for entry in problems {
      let value = entry.categoryNames.joined(separator: ", ")
      lines.append(
        "- \(entry.recipeTitle) — \(entry.field.group.name) \"\(value)\": \(entry.outcome.problemDescription(entry.field))"
      )
    }
    return lines.joined(separator: "\n")
  }
}

extension CategorySourceMoveReport.Outcome {
  public func problemDescription(_ field: CategorySourceMoveReport.Field) -> String {
    switch self {
    case .move: "Moves to \(field.fieldName)"
    case .alreadySet: "\(field.fieldName) already matches"
    case let .fieldHasDifferentValue(existing): "\(field.fieldName) is already \"\(existing)\""
    case .multipleValues: "More than one \(field.group.name) value for \(field.fieldName)"
    case .multipleSourceRecords: "More than one source record"
    }
  }
}

extension RecipeRepository {
  /// Reports what the move would do without writing. `publicationNames` are the Cookbook values routed to
  /// Publication instead of Book title (matched ignoring case, accents, and punctuation).
  public static func planCategorySourceMove(
    publicationNames: Set<String>,
    in db: Database
  ) throws -> CategorySourceMoveReport {
    try categorySourceMovePlan(publicationNames: publicationNames, in: db).report
  }

  /// Plans and applies in one transaction, so the report describes exactly what was written. Re-running is
  /// harmless: moved tags are gone, and problems stay put until fixed by hand.
  public static func applyCategorySourceMove(
    publicationNames: Set<String>,
    in db: Database,
    uuid: () -> UUID
  ) throws -> CategorySourceMoveReport {
    let plan = try categorySourceMovePlan(publicationNames: publicationNames, in: db)
    let changes = plan.report.entries.filter { !$0.outcome.isProblem }

    for (recipeID, entries) in Dictionary(grouping: changes, by: \.recipeID) {
      let moves = entries.filter { $0.outcome == .move }
      if !moves.isEmpty {
        var source = plan.sourceByRecipeID[recipeID] ?? RecipeSource(id: uuid(), recipeID: recipeID)
        for entry in moves {
          let value = entry.categoryNames[0]
          switch entry.field {
          case .bookTitle: source.bookTitle = value
          case .publicationName: source.publicationName = value
          case .author: source.author = value
          }
        }
        try RecipeSource.upsert { source }.execute(db)
      }
      for entry in entries {
        for assignmentID in plan.assignmentIDsByEntryID[entry.id] ?? [] {
          try RecipeCategory.find(assignmentID).delete().execute(db)
        }
      }
    }
    return plan.report
  }

  private struct CategorySourceMovePlan {
    var report: CategorySourceMoveReport
    var sourceByRecipeID: [Recipe.ID: RecipeSource]
    var assignmentIDsByEntryID: [String: [RecipeCategory.ID]]
  }

  private static func categorySourceMovePlan(
    publicationNames: Set<String>,
    in db: Database
  ) throws -> CategorySourceMovePlan {
    let facets = try Facet.fetchAll(db)
    let categoriesByID = Dictionary(uniqueKeysWithValues: try Category.fetchAll(db).map { ($0.id, $0) })
    let assignmentsByRecipeID = Dictionary(grouping: try RecipeCategory.fetchAll(db), by: \.recipeID)
    let sourcesByRecipeID = Dictionary(grouping: try RecipeSource.fetchAll(db), by: \.recipeID)
    let titlesByRecipeID = Dictionary(uniqueKeysWithValues: try Recipe.fetchAll(db).map { ($0.id, $0.title) })
    let publicationKeys = Set(publicationNames.map(moveNormalized))

    var groupByFacetID: [Facet.ID: CategorySourceMoveReport.Group] = [:]
    var missingGroups: [CategorySourceMoveReport.Group] = []
    for group in CategorySourceMoveReport.Group.allCases {
      let names = [group.name, group.name + "s"].map(moveNormalized)
      let matches = facets.filter { names.contains(moveNormalized($0.name)) }
      if matches.isEmpty { missingGroups.append(group) }
      for facet in matches { groupByFacetID[facet.id] = group }
    }

    var entries: [CategorySourceMoveReport.Entry] = []
    var cookbookValues: [String] = []
    var assignmentIDsByEntryID: [String: [RecipeCategory.ID]] = [:]
    var sourceByRecipeID: [Recipe.ID: RecipeSource] = [:]

    for recipeID in assignmentsByRecipeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
      guard let title = titlesByRecipeID[recipeID] else { continue }
      let sources = sourcesByRecipeID[recipeID] ?? []
      if sources.count == 1 { sourceByRecipeID[recipeID] = sources[0] }

      var assignmentsByField: [CategorySourceMoveReport.Field: [(RecipeCategory, String)]] = [:]
      for assignment in assignmentsByRecipeID[recipeID] ?? [] {
        guard
          let category = categoriesByID[assignment.categoryID],
          let group = category.facetID.flatMap({ groupByFacetID[$0] })
        else { continue }
        let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let field: CategorySourceMoveReport.Field
        switch group {
        case .cookbook:
          if !name.isEmpty { appendDistinct(name, to: &cookbookValues) }
          field = publicationKeys.contains(moveNormalized(name)) ? .publicationName : .bookTitle
        case .chef:
          field = .author
        }
        assignmentsByField[field, default: []].append((assignment, name))
      }

      for field in CategorySourceMoveReport.Field.allCases {
        guard let assignments = assignmentsByField[field] else { continue }
        var distinctNames: [String] = []
        for (_, name) in assignments where !name.isEmpty {
          appendDistinct(name, to: &distinctNames)
        }

        let outcome: CategorySourceMoveReport.Outcome
        if distinctNames.count != 1 {
          outcome = .multipleValues
        } else if sources.count > 1 {
          outcome = .multipleSourceRecords
        } else {
          let existing = sources.first.flatMap { source in
            switch field {
            case .bookTitle: source.bookTitle
            case .publicationName: source.publicationName
            case .author: source.author
            }
          }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          if existing.isEmpty {
            outcome = .move
          } else if moveNormalized(existing) == moveNormalized(distinctNames[0]) {
            outcome = .alreadySet
          } else {
            outcome = .fieldHasDifferentValue(existing: existing)
          }
        }

        let entry = CategorySourceMoveReport.Entry(
          recipeID: recipeID,
          recipeTitle: title,
          field: field,
          categoryNames: distinctNames,
          outcome: outcome
        )
        entries.append(entry)
        assignmentIDsByEntryID[entry.id] = assignments.map(\.0.id)
      }
    }

    entries.sort {
      ($0.recipeTitle.localizedLowercase, $0.field.rawValue) < ($1.recipeTitle.localizedLowercase, $1.field.rawValue)
    }
    cookbookValues.sort { $0.localizedStandardCompare($1) == .orderedAscending }
    return CategorySourceMovePlan(
      report: CategorySourceMoveReport(missingGroups: missingGroups, cookbookValues: cookbookValues, entries: entries),
      sourceByRecipeID: sourceByRecipeID,
      assignmentIDsByEntryID: assignmentIDsByEntryID
    )
  }

  private static func appendDistinct(_ name: String, to names: inout [String]) {
    if !names.map(moveNormalized).contains(moveNormalized(name)) {
      names.append(name)
    }
  }

  /// Case-, accent-, and punctuation-insensitive, so "Cooks Illustrated" matches "Cook's Illustrated".
  static func moveNormalized(_ value: String) -> String {
    value
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .unicodeScalars
      .filter { CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0) }
      .map(String.init)
      .joined()
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }
}

/// What the follow-up cleanup deleted, and what still holds a tag and so had to stay.
public struct CategorySourceGroupCleanupReport: Equatable, Sendable {
  public struct Remaining: Equatable, Identifiable, Sendable {
    public var group: CategorySourceMoveReport.Group
    public var categoryName: String
    public var recipeCount: Int

    public var id: String { "\(group.rawValue)-\(categoryName)" }

    public init(group: CategorySourceMoveReport.Group, categoryName: String, recipeCount: Int) {
      self.group = group
      self.categoryName = categoryName
      self.recipeCount = recipeCount
    }
  }

  public var deletedCategoryCount: Int
  public var deletedGroups: [CategorySourceMoveReport.Group]
  public var remaining: [Remaining]

  public init(
    deletedCategoryCount: Int = 0,
    deletedGroups: [CategorySourceMoveReport.Group] = [],
    remaining: [Remaining] = []
  ) {
    self.deletedCategoryCount = deletedCategoryCount
    self.deletedGroups = deletedGroups
    self.remaining = remaining
  }
}

extension RecipeRepository {
  /// Deletes every Cookbook/Chef category no recipe still uses (deepest first, so emptied parents go too), then
  /// each group left empty. Categories still tagged on a recipe are kept and reported — never untagged here.
  public static func deleteUnusedCategorySourceGroups(in db: Database) throws -> CategorySourceGroupCleanupReport {
    let facets = try Facet.fetchAll(db)
    let assignments = try RecipeCategory.fetchAll(db)
    let usedCategoryIDs = Set(assignments.map(\.categoryID))
    var report = CategorySourceGroupCleanupReport()

    for group in CategorySourceMoveReport.Group.allCases {
      let names = [group.name, group.name + "s"].map(moveNormalized)
      for facet in facets where names.contains(moveNormalized(facet.name)) {
        guard !CategoryRepository.isStarterFacet(facet.id) else { continue }
        var categories = try Category.where { $0.facetID.eq(facet.id) }.fetchAll(db)

        var deletedSomething = true
        while deletedSomething {
          deletedSomething = false
          let parentIDs = Set(categories.compactMap(\.parentCategoryID))
          for category in categories
          where !usedCategoryIDs.contains(category.id)
            && !parentIDs.contains(category.id)
            && !CategoryRepository.isStarterCategory(category.id) {
            try Category.find(category.id).delete().execute(db)
            categories.removeAll { $0.id == category.id }
            report.deletedCategoryCount += 1
            deletedSomething = true
          }
        }

        if categories.isEmpty {
          try Facet.find(facet.id).delete().execute(db)
          report.deletedGroups.append(group)
        } else {
          for category in categories.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            report.remaining.append(.init(
              group: group,
              categoryName: category.name,
              recipeCount: assignments.count { $0.categoryID == category.id }
            ))
          }
        }
      }
    }
    return report
  }
}
