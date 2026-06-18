import Foundation

public enum CategoryHierarchy {
  public struct Path: Equatable, Sendable {
    public var components: [String]

    public init(components: [String]) {
      self.components = components
    }
  }

  public struct DisplayRow: Identifiable, Equatable, Sendable {
    public var category: Category
    public var displayName: String
    public var depth: Int
    public var hasChildren: Bool

    public var id: Category.ID { category.id }

    public init(category: Category, displayName: String, depth: Int, hasChildren: Bool) {
      self.category = category
      self.displayName = displayName
      self.depth = depth
      self.hasChildren = hasChildren
    }
  }

  public static func paths(from names: [String]) -> [Path] {
    var seen: Set<String> = []
    var paths: [Path] = []

    for name in names {
      let components = name
        .split(separator: ">")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      guard !components.isEmpty else { continue }

      let key = components.map { $0.lowercased() }.joined(separator: ">")
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      paths.append(Path(components: components))
    }

    return paths
  }

  public static func displayRows(from categories: [Category]) -> [DisplayRow] {
    let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    let childrenByParentID = Dictionary(grouping: categories, by: \.parentCategoryID)
    var rows: [DisplayRow] = []
    appendRows(
      parentCategoryID: nil,
      depth: 0,
      categoriesByID: categoriesByID,
      childrenByParentID: childrenByParentID,
      rows: &rows
    )
    return rows
  }

  public static func children(
    of parentCategoryID: Category.ID?,
    in categories: [Category]
  ) -> [Category] {
    sortedCategories(categories.filter { $0.parentCategoryID == parentCategoryID })
  }

  public static func descendantIDs(
    of categoryID: Category.ID,
    in categories: [Category]
  ) -> Set<Category.ID> {
    let childrenByParentID = Dictionary(grouping: categories, by: \.parentCategoryID)
    var ids: Set<Category.ID> = []
    appendDescendantIDs(of: categoryID, childrenByParentID: childrenByParentID, ids: &ids)
    return ids
  }

  public static func displayName(
    for category: Category,
    categoriesByID: [Category.ID: Category]
  ) -> String {
    pathComponents(for: category, categoriesByID: categoriesByID).joined(separator: " > ")
  }

  public static func filterDisplayNames(
    for category: Category,
    categoriesByID: [Category.ID: Category]
  ) -> [String] {
    let components = pathComponents(for: category, categoriesByID: categoriesByID)
    guard !components.isEmpty else { return [] }
    return components.indices.map { index in
      components.prefix(through: index).joined(separator: " > ")
    }
  }

  private static func appendRows(
    parentCategoryID: Category.ID?,
    depth: Int,
    categoriesByID: [Category.ID: Category],
    childrenByParentID: [Category.ID?: [Category]],
    rows: inout [DisplayRow]
  ) {
    for category in sortedCategories(childrenByParentID[parentCategoryID] ?? []) {
      rows.append(
        DisplayRow(
          category: category,
          displayName: displayName(for: category, categoriesByID: categoriesByID),
          depth: depth,
          hasChildren: !(childrenByParentID[category.id] ?? []).isEmpty
        )
      )
      appendRows(
        parentCategoryID: category.id,
        depth: depth + 1,
        categoriesByID: categoriesByID,
        childrenByParentID: childrenByParentID,
        rows: &rows
      )
    }
  }

  private static func appendDescendantIDs(
    of categoryID: Category.ID,
    childrenByParentID: [Category.ID?: [Category]],
    ids: inout Set<Category.ID>
  ) {
    for child in childrenByParentID[categoryID] ?? [] {
      guard !ids.contains(child.id) else { continue }
      ids.insert(child.id)
      appendDescendantIDs(of: child.id, childrenByParentID: childrenByParentID, ids: &ids)
    }
  }

  private static func sortedCategories(_ categories: [Category]) -> [Category] {
    categories.sorted { lhs, rhs in
      let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
      if nameComparison != .orderedSame {
        return nameComparison == .orderedAscending
      }
      if lhs.sortOrder != rhs.sortOrder {
        return lhs.sortOrder < rhs.sortOrder
      }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  private static func pathComponents(
    for category: Category,
    categoriesByID: [Category.ID: Category]
  ) -> [String] {
    var categories: [Category] = [category]
    var current = category
    var seenIDs: Set<Category.ID> = [category.id]

    while let parentID = current.parentCategoryID,
          let parent = categoriesByID[parentID],
          !seenIDs.contains(parent.id) {
      categories.insert(parent, at: 0)
      seenIDs.insert(parent.id)
      current = parent
    }

    return categories.map(\.name)
  }
}

public enum CategoryHierarchyError: Error {
  case emptyPath
}
