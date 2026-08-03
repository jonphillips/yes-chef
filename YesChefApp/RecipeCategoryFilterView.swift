import SwiftUI
import SwiftUINavigation
import YesChefCore

struct RecipeCategoryFilterPickerView: View {
  let model: RecipeLibraryModel
  @State private var searchText = ""

  private var categoryGroups: [RecipeCategoryFilterGroup] {
    let categoriesByID = Dictionary(uniqueKeysWithValues: model.categoryFilterCategories.map { ($0.id, $0) })
    return model.categoryFilterFacets.compactMap { facet in
      let categoryPaths = filterPaths(
        for: model.categoryFilterCategories.filter { $0.facetID == facet.id },
        categoriesByID: categoriesByID
      )
      guard !categoryPaths.isEmpty else { return nil }
      return RecipeCategoryFilterGroup(title: facet.name, categoryPaths: categoryPaths)
    }
  }

  private var looseCategoryNodes: [RecipeCategoryFilterNode] {
    let categoriesByID = Dictionary(uniqueKeysWithValues: model.categoryFilterCategories.map { ($0.id, $0) })
    return RecipeCategoryFilterNode.tree(
      from: filterPaths(
        for: model.categoryFilterCategories.filter { $0.facetID == nil },
        categoriesByID: categoriesByID
      )
    )
  }

  private var matchingNodes: [RecipeCategoryFilterSearchNode] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return [] }

    let grouped = categoryGroups.flatMap { group in
      group.nodes.compactMap { node in
        let result = RecipeCategoryFilterSearchNode(title: "\(group.title) > \(node.path)", node: node)
        return result.title.localizedCaseInsensitiveContains(query) ? result : nil
      }
    }
    let loose = looseCategoryNodes.flatMap(\.flattened).compactMap { node in
      let result = RecipeCategoryFilterSearchNode(title: node.path, node: node)
      return result.title.localizedCaseInsensitiveContains(query) ? result : nil
    }
    return grouped + loose
  }

  var body: some View {
    let availabilityByName = model.categoryFilterAvailabilityByName

    Group {
      if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        List {
          Section("Category Groups") {
            ForEach(categoryGroups) { group in
              NavigationLink {
                RecipeCategoryFilterLevelView(
                  model: model,
                  title: group.title,
                  parentNode: nil,
                  nodes: group.nodes,
                  availabilityByName: availabilityByName
                )
              } label: {
                Label(group.title, systemImage: "folder.fill")
              }
            }
          }

          Section("Other Categories") {
            ForEach(looseCategoryNodes) { node in
              RecipeCategoryFilterNodeRow(
                model: model,
                node: node,
                availabilityByName: availabilityByName
              )
            }
          }
        }
        .overlay {
          if categoryGroups.isEmpty && looseCategoryNodes.isEmpty {
            ContentUnavailableView("No Categories", systemImage: "folder")
          }
        }
        .navigationTitle("Categories")
      } else {
        List {
          ForEach(matchingNodes) { result in
            let availability = availabilityByName[result.node.path] ?? .empty(categoryName: result.node.path)
            RecipeFilterSelectionRow(
              title: result.title,
              systemImage: "folder",
              detail: availability.countText,
              isSelected: availability.isSelected,
              isEnabled: availability.isEnabled
            ) {
              model.categoryFilterButtonTapped(result.node.path)
            }
          }
        }
        .overlay {
          if matchingNodes.isEmpty {
            ContentUnavailableView("No Matching Categories", systemImage: "folder")
          }
        }
        .navigationTitle("Categories")
      }
    }
    .searchable(text: $searchText, prompt: "Search categories")
  }

  private func filterPaths(
    for categories: [YesChefCore.Category],
    categoriesByID: [YesChefCore.Category.ID: YesChefCore.Category]
  ) -> [String] {
    let availablePaths = Set(model.categoryFilterOptions)
    return categories
      .flatMap { CategoryHierarchy.filterDisplayNames(for: $0, categoriesByID: categoriesByID) }
      .filter { availablePaths.contains($0) }
  }
}

private struct RecipeCategoryFilterLevelView: View {
  let model: RecipeLibraryModel
  let title: String
  let parentNode: RecipeCategoryFilterNode?
  let nodes: [RecipeCategoryFilterNode]
  let availabilityByName: [String: RecipeCategoryFilterAvailability]

  var body: some View {
    List {
      if let parentNode {
        Section {
          let availability = availabilityByName[parentNode.path] ?? .empty(categoryName: parentNode.path)
          RecipeFilterSelectionRow(
            title: "All \(parentNode.title)",
            systemImage: "folder.fill",
            detail: availability.countText,
            isSelected: availability.isSelected,
            isEnabled: availability.isEnabled
          ) {
            model.categoryFilterButtonTapped(parentNode.path)
          }
        } footer: {
          Text("Parent filters include recipes in descendant categories. Disabled categories would leave no recipes with the current filters.")
        }
      }

      Section(parentNode == nil ? "Categories" : "Subcategories") {
        ForEach(nodes) { node in
          RecipeCategoryFilterNodeRow(
            model: model,
            node: node,
            availabilityByName: availabilityByName
          )
        }
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct RecipeCategoryFilterNodeRow: View {
  let model: RecipeLibraryModel
  let node: RecipeCategoryFilterNode
  let availabilityByName: [String: RecipeCategoryFilterAvailability]

  var body: some View {
    if node.children.isEmpty {
      RecipeFilterSelectionRow(
        title: node.title,
        systemImage: "folder",
        detail: availability.countText,
        isSelected: availability.isSelected,
        isEnabled: availability.isEnabled
      ) {
        model.categoryFilterButtonTapped(node.path)
      }
    } else {
      NavigationLink {
        RecipeCategoryFilterLevelView(
          model: model,
          title: node.title,
          parentNode: node,
          nodes: node.children,
          availabilityByName: availabilityByName
        )
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "folder.fill")
            .foregroundStyle(.secondary)
            .frame(width: 22)
          VStack(alignment: .leading, spacing: 2) {
            Text(node.title)
            if let summary {
              Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .disabled(!isNavigable)
      .opacity(isNavigable ? 1 : 0.55)
    }
  }

  private var availability: RecipeCategoryFilterAvailability {
    availabilityByName[node.path] ?? .empty(categoryName: node.path)
  }

  private var descendantAvailabilities: [RecipeCategoryFilterAvailability] {
    node.flattened.map { availabilityByName[$0.path] ?? .empty(categoryName: $0.path) }
  }

  private var selectedPathCount: Int {
    descendantAvailabilities.filter(\.isSelected).count
  }

  private var possiblePathCount: Int {
    descendantAvailabilities.filter { !$0.isSelected && $0.matchingRecipeCount > 0 }.count
  }

  private var isNavigable: Bool {
    selectedPathCount > 0 || possiblePathCount > 0
  }

  private var summary: String? {
    switch (selectedPathCount, possiblePathCount) {
    case (0, 0):
      "No matches"
    case (0, let possible):
      "\(possible) possible"
    case (let selected, 0):
      "\(selected) selected"
    case let (selected, possible):
      "\(selected) selected · \(possible) possible"
    }
  }
}

private struct RecipeCategoryFilterGroup: Identifiable, Equatable {
  let title: String
  let nodes: [RecipeCategoryFilterNode]

  init(title: String, categoryPaths: [String]) {
    self.title = title
    nodes = RecipeCategoryFilterNode.tree(from: categoryPaths)
  }

  var id: String { title }
}

private struct RecipeCategoryFilterSearchNode: Identifiable, Equatable {
  let title: String
  let node: RecipeCategoryFilterNode

  var id: String { title }
}

private struct RecipeCategoryFilterNode: Identifiable, Equatable {
  let title: String
  let path: String
  let children: [RecipeCategoryFilterNode]

  var id: String { path }

  var flattened: [RecipeCategoryFilterNode] {
    [self] + children.flatMap(\.flattened)
  }

  static func tree(from categoryPaths: [String]) -> [RecipeCategoryFilterNode] {
    let parsedPaths = categoryPaths
      .map(pathComponents)
      .filter { !$0.isEmpty }
    return nodes(parentComponents: [], parsedPaths: parsedPaths)
  }

  private static func nodes(
    parentComponents: [String],
    parsedPaths: [[String]]
  ) -> [RecipeCategoryFilterNode] {
    let depth = parentComponents.count
    let childTitles: Set<String> = Set(
      parsedPaths.compactMap { components in
        guard components.count > depth,
              hasPrefix(parentComponents, in: components) else { return nil }
        return components[depth]
      }
    )

    return childTitles
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
      .map { title in
        let components = parentComponents + [title]
        let childPaths = parsedPaths.filter { hasPrefix(components, in: $0) }
        return RecipeCategoryFilterNode(
          title: title,
          path: components.joined(separator: " > "),
          children: nodes(parentComponents: components, parsedPaths: childPaths)
        )
      }
  }

  private static func pathComponents(_ path: String) -> [String] {
    path
      .split(separator: ">")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func hasPrefix(_ prefix: [String], in components: [String]) -> Bool {
    guard prefix.count <= components.count else { return false }
    return zip(prefix, components).allSatisfy { pair in
      pair.0 == pair.1
    }
  }
}

#Preview {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    try! $0.seedSampleDataIfNeeded()
  }
  AppContainer()
}
