import SQLiteData
import SwiftUI
import YesChefCore

struct FacetCoverageView: View {
  @Fetch(RecipeFacetCoverageRequest(), animation: .default) private var coverage = RecipeFacetCoverage(
    recipes: [], recipeCategories: [], categories: [], facets: []
  )

  var body: some View {
    List {
      ForEach(coverage.facetSummaries) { summary in
        Section(summary.facet.name) {
          NavigationLink {
            FacetCoverageRecipeList(focusedFacet: summary.facet)
          } label: {
            Label("Recipes missing a \(summary.facet.name)", systemImage: "tag")
          }
          LabeledContent("Classified", value: "\(summary.classifiedRecipeCount)")
          LabeledContent("Unclassified", value: "\(summary.unclassifiedRecipeCount)")
          ForEach(summary.valueCounts.filter { $0.recipeCount > 0 }) { value in
            LabeledContent(value.category.name, value: "\(value.recipeCount)")
          }
        }
      }
    }
    .navigationTitle("Label Recipes")
    .overlay {
      if coverage.facetSummaries.isEmpty {
        ContentUnavailableView(
          "No Recipe Labels to Review",
          systemImage: "tag",
          description: Text("Add a facet before using this label list.")
        )
      }
    }
  }
}

private struct FacetCoverageRecipeList: View {
  @Fetch(RecipeListRequest(), animation: .default) private var recipeRows: [RecipeListRowData] = []
  @Fetch(RecipeFacetCoverageRequest(), animation: .default) private var coverage = RecipeFacetCoverage(
    recipes: [], recipeCategories: [], categories: [], facets: []
  )
  @State private var coverageView: RecipeFacetCoverageView = .missingProtein
  @State private var focusedFacet: Facet?

  init(focusedFacet: Facet? = nil) {
    _focusedFacet = State(initialValue: focusedFacet)
  }

  var body: some View {
    List {
      Section {
        Picker("Recipes to label", selection: $coverageView) {
          ForEach(RecipeFacetCoverageView.allCases) { view in
            Text(view.labelingTitle).tag(view)
          }
        }
        .onChange(of: coverageView) { _, _ in focusedFacet = nil }
      } footer: {
        Text(focusedFacet.map { "Choose labels for recipes missing a \($0.name)." } ?? coverageView.labelingDetail)
      }

      Section {
        ForEach(filteredRows) { row in
          NavigationLink {
            RecipeTagEditorDestination(recipeID: row.recipe.id)
          } label: {
            RecipeListRow(
              row: row,
              options: .init(density: .rich, showsSourceMetadata: true, showsCategoryMetadata: true)
            )
          }
        }
      }
    }
    .navigationTitle(focusedFacet.map { "Recipes missing a \($0.name)" } ?? coverageView.labelingTitle)
    .overlay {
      if filteredRows.isEmpty {
        ContentUnavailableView(
          "No Recipes to Label",
          systemImage: "checkmark.circle",
          description: Text("Everything in this list already has the labels it needs.")
        )
      }
    }
  }

  private var filteredRows: [RecipeListRowData] {
    let matchingIDs = if let focusedFacet {
      coverage.recipeIDs(unclassifiedInFacetID: focusedFacet.id)
    } else {
      coverage.recipeIDs(matching: coverageView)
    }
    return recipeRows.filter { !$0.recipe.archived && matchingIDs.contains($0.recipe.id) }
  }
}

private extension RecipeFacetCoverageView {
  var labelingTitle: String {
    switch self {
    case .missingProtein: "Recipes missing a Protein"
    case .missingPrimaryFacet: "Recipes missing a primary label"
    case .noEditorialLabels: "Recipes without editorial labels"
    }
  }

  var labelingDetail: String {
    switch self {
    case .missingProtein: "These recipes do not yet have a Protein label."
    case .missingPrimaryFacet: "These recipes are missing a Protein, Dish Type, or Technique label."
    case .noEditorialLabels: "These recipes do not yet have Protein, Dietary, Dish Type, or Technique labels."
    }
  }
}
