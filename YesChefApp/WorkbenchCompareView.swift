import LLMClientKit
import SwiftUI
import YesChefCore

/// The Compare surface: an aligned ingredient-diff matrix (Ingredients) plus a whole-recipe
/// flip-through (Full) over a workbench's working recipe + candidates. A pure read over the
/// already-loaded detail — no fetch, no schema. Presented full-screen on iPad, as a sheet on iPhone.
struct WorkbenchCompareView: View {
  enum Segment: String, CaseIterable, Identifiable {
    case ingredients = "Ingredients"
    case full = "Full"

    var id: String { rawValue }
  }

  let detail: WorkbenchDetailData
  let alignmentModel: WorkbenchCompareAlignmentModel
  let tier: ModelTier
  /// Dismisses Compare and opens the workbench chat (already seeded with every candidate's
  /// ingredients) so the cook can talk through the differences. Nil hides the affordance.
  var onDiscuss: (() -> Void)?
  @Environment(\.dismiss) private var dismiss
  @State private var segment: Segment = .ingredients

  private var workingDetail: RecipeDetailData? {
    detail.draftRecipeDetail
  }

  private var candidateDetails: [RecipeDetailData] {
    detail.candidateRows.compactMap(\.recipeDetail)
  }

  private var alignmentKey: CompareAlignmentKey {
    CompareAlignmentKey(working: workingDetail, candidates: candidateDetails)
  }

  private var deterministicComparison: IngredientComparison {
    WorkbenchCompare.ingredientComparison(working: workingDetail, candidates: candidateDetails)
  }

  private var cachedOutcome: WorkbenchAlignedComparison? {
    alignmentModel.cachedOutcome(for: alignmentKey)
  }

  private var currentOutcome: WorkbenchAlignedComparison? {
    alignmentModel.currentKey == alignmentKey ? alignmentModel.currentOutcome : nil
  }

  private var displayedOutcome: WorkbenchAlignedComparison? {
    cachedOutcome ?? currentOutcome
  }

  private var comparison: IngredientComparison {
    displayedOutcome?.comparison ?? deterministicComparison
  }

  private var isAligning: Bool {
    cachedOutcome == nil
      && alignmentModel.currentKey == alignmentKey
      && alignmentModel.isAligning
  }

  private var showsBasicViewAffordance: Bool {
    if let displayedOutcome {
      return displayedOutcome.source.isFallback
    }
    return alignmentModel.currentKey == alignmentKey && alignmentModel.showsBasicViewAffordance
  }

  private var fullRecipes: [WorkbenchCompareRecipe] {
    var recipes: [WorkbenchCompareRecipe] = []
    if let working = detail.draftRecipeDetail {
      recipes.append(WorkbenchCompareRecipe(detail: working, isWorking: true))
    }
    recipes.append(contentsOf: detail.candidateRows.compactMap(\.recipeDetail).map {
      WorkbenchCompareRecipe(detail: $0, isWorking: false)
    })
    return recipes
  }

  var body: some View {
    NavigationStack {
      Group {
        switch segment {
        case .ingredients:
          IngredientMatrixView(comparison: comparison)
            .task(id: alignmentKey) {
              await ingredientsSegmentAppeared()
            }
        case .full:
          WorkbenchCompareFullView(recipes: fullRecipes)
        }
      }
      .navigationTitle(detail.workbench.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Picker("View", selection: $segment) {
            ForEach(Segment.allCases) { segment in
              Text(segment.rawValue).tag(segment)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 260)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            dismiss()
          }
        }
        if let onDiscuss {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              onDiscuss()
            } label: {
              Label("Chat", systemImage: "sparkles")
            }
          }
        }
        if segment == .ingredients {
          ToolbarItemGroup(placement: .topBarTrailing) {
            if isAligning {
              ProgressView()
                .controlSize(.small)
                .accessibilityLabel(Text("Aligning"))
            }
            if showsBasicViewAffordance {
              Text("Showing basic view")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
            Button {
              Task {
                await refreshButtonTapped()
              }
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isAligning)
          }
        }
      }
    }
  }

  private func ingredientsSegmentAppeared() async {
    await alignmentModel.ingredientsSegmentAppeared(
      working: workingDetail,
      candidates: candidateDetails,
      tier: tier
    )
  }

  private func refreshButtonTapped() async {
    await alignmentModel.refreshButtonTapped(
      working: workingDetail,
      candidates: candidateDetails,
      tier: tier
    )
  }
}

private struct WorkbenchCompareRecipe: Identifiable {
  let detail: RecipeDetailData
  let isWorking: Bool

  var id: Recipe.ID { detail.recipe.id }
  var title: String { detail.recipe.title }
}

// MARK: - Ingredient matrix

private enum CompareMetrics {
  static let labelColumnWidth: CGFloat = 150
  static let dataColumnWidth: CGFloat = 172
  static let cellPadding: CGFloat = 10
}

private struct IngredientMatrixView: View {
  let comparison: IngredientComparison
  @State private var rowHeights: [String: CGFloat] = [:]

  // The label + working recipe stay pinned; candidate columns scroll horizontally beside them.
  private var frozenColumn: IngredientMatrixColumn? {
    comparison.columns.first { $0.role == .working }
  }

  private var frozenColumnIndex: Int? {
    comparison.columns.firstIndex { $0.role == .working }
  }

  private var scrollingColumns: [(index: Int, column: IngredientMatrixColumn)] {
    comparison.columns.enumerated()
      .filter { $0.element.role != .working }
      .map { (index: $0.offset, column: $0.element) }
  }

  var body: some View {
    if comparison.rows.isEmpty, !comparison.hasOtherLines {
      ContentUnavailableView(
        "Nothing to Compare",
        systemImage: "square.split.2x2",
        description: Text("These recipes don't share parseable ingredients yet.")
      )
    } else {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 20) {
          matrix
          if comparison.hasOtherLines {
            otherLinesSection
          }
        }
        .padding(.vertical, 12)
      }
      .onPreferenceChange(RowHeightPreference.self) { rowHeights = $0 }
    }
  }

  private var matrix: some View {
    HStack(alignment: .top, spacing: 0) {
      frozenBlock
      Divider()
      ScrollView(.horizontal, showsIndicators: true) {
        HStack(alignment: .top, spacing: 0) {
          ForEach(scrollingColumns, id: \.column.id) { entry in
            dataColumn(entry.column, columnIndex: entry.index)
          }
        }
      }
    }
  }

  private var frozenBlock: some View {
    HStack(alignment: .top, spacing: 0) {
      // Ingredient label column.
      VStack(spacing: 0) {
        headerCell(Text("Ingredient").font(.caption.bold()).foregroundStyle(.secondary), tinted: false)
          .frame(width: CompareMetrics.labelColumnWidth)
        ForEach(comparison.rows) { row in
          measuredCell(rowID: row.id) {
            Text(row.label)
              .font(.subheadline.weight(.medium))
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(width: CompareMetrics.labelColumnWidth)
        }
      }
      // Working recipe column (pinned, accent-tinted).
      if let frozenColumn, let frozenColumnIndex {
        Divider()
        dataColumn(frozenColumn, columnIndex: frozenColumnIndex)
      }
    }
    .background(Color(.systemBackground))
  }

  private func dataColumn(_ column: IngredientMatrixColumn, columnIndex: Int) -> some View {
    let tinted = column.role == .working
    return VStack(spacing: 0) {
      headerCell(
        VStack(alignment: .leading, spacing: 2) {
          Text(column.title)
            .font(.caption.bold())
            .lineLimit(2)
          if tinted {
            Text("Working")
              .font(.caption2)
              .foregroundStyle(.tint)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading),
        tinted: tinted
      )
      .frame(width: CompareMetrics.dataColumnWidth)
      ForEach(comparison.rows) { row in
        let value = row.cells.indices.contains(columnIndex) ? row.cells[columnIndex] : nil
        measuredCell(rowID: row.id, tinted: tinted) {
          if let value {
            Text(value)
              .font(.subheadline)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else {
            Text("—")
              .font(.subheadline)
              .foregroundStyle(.tertiary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .accessibilityLabel(Text("Not in this recipe"))
          }
        }
        .frame(width: CompareMetrics.dataColumnWidth)
      }
    }
  }

  private static let headerRowID = "\u{0}header"

  /// The header row is measured and synced just like data rows so the frozen and scrolling blocks
  /// start their first ingredient at the same Y even when a title wraps to two lines.
  private func headerCell(_ content: some View, tinted: Bool) -> some View {
    content
      .padding(CompareMetrics.cellPadding)
      .frame(
        maxWidth: .infinity,
        minHeight: max(rowHeights[Self.headerRowID] ?? 0, 44),
        alignment: .bottomLeading
      )
      .background(tinted ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
      .background(
        GeometryReader { proxy in
          Color.clear.preference(key: RowHeightPreference.self, value: [Self.headerRowID: proxy.size.height])
        }
      )
  }

  /// A cell that both reports its natural height (so the frozen and scrolling blocks share a row
  /// height) and then adopts the measured max for its row so every column's row aligns.
  private func measuredCell(
    rowID: String,
    tinted: Bool = false,
    @ViewBuilder content: () -> some View
  ) -> some View {
    content()
      .padding(CompareMetrics.cellPadding)
      .frame(maxWidth: .infinity, minHeight: rowHeights[rowID], alignment: .topLeading)
      .background(tinted ? Color.accentColor.opacity(0.06) : Color.clear)
      .overlay(alignment: .bottom) { Divider() }
      .background(
        GeometryReader { proxy in
          Color.clear.preference(key: RowHeightPreference.self, value: [rowID: proxy.size.height])
        }
      )
  }

  private var otherLinesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Other ingredients")
        .font(.headline)
      Text("Lines that didn't line up on a shared row — either they don't map to a known ingredient, or the recipe lists the same ingredient more than once.")
        .font(.caption)
        .foregroundStyle(.secondary)
      ForEach(comparison.columns.filter { !$0.otherLines.isEmpty }) { column in
        VStack(alignment: .leading, spacing: 4) {
          Text(column.title)
            .font(.subheadline.bold())
            .foregroundStyle(column.role == .working ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
          ForEach(Array(column.otherLines.enumerated()), id: \.offset) { _, line in
            Text("• \(line)")
              .font(.subheadline)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
    .padding(.horizontal, 16)
  }
}

private struct RowHeightPreference: PreferenceKey {
  static let defaultValue: [String: CGFloat] = [:]

  static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
    value.merge(nextValue()) { max($0, $1) }
  }
}

// MARK: - Full recipe flip-through

private struct WorkbenchCompareFullView: View {
  let recipes: [WorkbenchCompareRecipe]
  @State private var selectedID: Recipe.ID?

  private var selectedRecipe: WorkbenchCompareRecipe? {
    recipes.first { $0.id == selectedID } ?? recipes.first
  }

  var body: some View {
    if recipes.isEmpty {
      ContentUnavailableView("Nothing to Compare", systemImage: "doc.on.doc")
    } else {
      VStack(spacing: 0) {
        Picker("Recipe", selection: recipeSelection) {
          ForEach(recipes) { recipe in
            Text(recipe.isWorking ? "\(recipe.title) (Working)" : recipe.title).tag(recipe.id)
          }
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        Divider()
        if let selectedRecipe {
          WorkbenchCompareRecipeDetail(recipe: selectedRecipe)
        }
      }
    }
  }

  private var recipeSelection: Binding<Recipe.ID> {
    Binding(
      get: { selectedRecipe?.id ?? recipes[0].id },
      set: { selectedID = $0 }
    )
  }
}

private struct WorkbenchCompareRecipeDetail: View {
  let recipe: WorkbenchCompareRecipe

  private var detail: RecipeDetailData { recipe.detail }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 6) {
          Text(detail.recipe.title)
            .font(.title2.bold())
          HStack(spacing: 12) {
            if let totalTimeMinutes = detail.recipe.totalTimeMinutes {
              Label("\(totalTimeMinutes) min", systemImage: "clock")
            }
            if let servingsText = detail.recipe.servingsText {
              Label(servingsText, systemImage: "person.2")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        ingredients

        if !detail.instructionSteps.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("Directions")
              .font(.title3.bold())
            ForEach(Array(detail.instructionSteps.enumerated()), id: \.element.id) { index, step in
              HStack(alignment: .top, spacing: 12) {
                Text("\(index + 1)")
                  .font(.caption.bold())
                  .foregroundStyle(.white)
                  .frame(width: 26, height: 26)
                  .background(Circle().fill(Color.accentColor))
                Text(step.text)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
        }
      }
      .padding(16)
    }
  }

  private var ingredients: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Ingredients")
        .font(.title3.bold())
      ForEach(orderedSections, id: \.id) { section in
        VStack(alignment: .leading, spacing: 6) {
          if let name = section.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            Text(name)
              .font(.headline)
          }
          ForEach(lines(in: section.id)) { line in
            if line.isHeader {
              Text(line.originalText.trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines)))
                .font(.subheadline.bold())
            } else {
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(line.originalText)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
        }
      }
    }
  }

  private var orderedSections: [IngredientSection] {
    detail.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }
  }

  private func lines(in sectionID: IngredientSection.ID) -> [IngredientLine] {
    detail.ingredientLines
      .filter { $0.sectionID == sectionID }
      .sorted { $0.sortOrder < $1.sortOrder }
  }
}
