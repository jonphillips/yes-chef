import SwiftUI
import SwiftUINavigation
import YesChefCore

struct RecipeCategoryFilterPickerView: View {
  let model: RecipeLibraryModel
  @State private var searchText = ""

  private var rootNodes: [RecipeCategoryFilterNode] {
    RecipeCategoryFilterNode.tree(from: model.categoryFilterOptions)
  }

  private var matchingNodes: [RecipeCategoryFilterNode] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return [] }
    return rootNodes
      .flatMap(\.flattened)
      .filter { $0.path.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    let availabilityByName = model.categoryFilterAvailabilityByName

    Group {
      if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        RecipeCategoryFilterLevelView(
          model: model,
          title: "Categories",
          parentNode: nil,
          nodes: rootNodes,
          availabilityByName: availabilityByName
        )
      } else {
        List {
          if matchingNodes.isEmpty {
            ContentUnavailableView("No Matching Categories", systemImage: "folder")
          } else {
            ForEach(matchingNodes) { node in
              let availability = availabilityByName[node.path] ?? .empty(categoryName: node.path)
              RecipeFilterSelectionRow(
                title: node.path,
                systemImage: "folder",
                detail: availability.countText,
                isSelected: availability.isSelected,
                isEnabled: availability.isEnabled
              ) {
                model.categoryFilterButtonTapped(node.path)
              }
            }
          }
        }
        .navigationTitle("Categories")
      }
    }
    .searchable(text: $searchText, prompt: "Search categories")
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

      Section(parentNode == nil ? "Top Level" : "Subcategories") {
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
