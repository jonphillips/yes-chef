import Foundation

enum CategoryHierarchy {
  struct Path: Equatable, Sendable {
    var components: [String]
  }

  static func paths(from names: [String]) -> [Path] {
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

  static func displayName(
    for category: Category,
    categoriesByID: [Category.ID: Category]
  ) -> String {
    pathComponents(for: category, categoriesByID: categoriesByID).joined(separator: " > ")
  }

  static func filterDisplayNames(
    for category: Category,
    categoriesByID: [Category.ID: Category]
  ) -> [String] {
    let components = pathComponents(for: category, categoriesByID: categoriesByID)
    guard !components.isEmpty else { return [] }
    return components.indices.map { index in
      components.prefix(through: index).joined(separator: " > ")
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

enum CategoryHierarchyError: Error {
  case emptyPath
}
