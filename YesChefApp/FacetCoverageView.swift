#if DEBUG
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
          LabeledContent("Classified", value: "\(summary.classifiedRecipeCount)")
          NavigationLink {
            FacetCoverageRecipeList(focusedFacet: summary.facet)
          } label: {
            LabeledContent("Unclassified", value: "\(summary.unclassifiedRecipeCount)")
          }
          ForEach(summary.valueCounts.filter { $0.recipeCount > 0 }) { value in
            LabeledContent(value.category.name, value: "\(value.recipeCount)")
          }
        }
      }
    }
    .navigationTitle("Facet Coverage")
    .overlay {
      if coverage.facetSummaries.isEmpty {
        ContentUnavailableView("No Visible Facets", systemImage: "chart.bar")
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
        Picker("Coverage", selection: $coverageView) {
          ForEach(RecipeFacetCoverageView.allCases) { view in
            Text(view.title).tag(view)
          }
        }
        .onChange(of: coverageView) { _, _ in focusedFacet = nil }
      } footer: {
        Text(focusedFacet.map { "Recipes missing \($0.name). Choose a coverage view to browse the D8 work list." } ?? coverageView.detail)
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
    .navigationTitle(focusedFacet.map { "Missing \($0.name)" } ?? "Coverage Recipes")
    .overlay {
      if filteredRows.isEmpty {
        ContentUnavailableView("No Recipes", systemImage: "checkmark.circle")
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
#endif
