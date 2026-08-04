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
          LabeledContent("Unclassified", value: "\(summary.unclassifiedRecipeCount)")
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
#endif
