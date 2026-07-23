import Dependencies
import Foundation
import LLMClientKit

public struct WorkbenchAlignedComparison: Sendable, Equatable, Codable {
  public enum Source: Sendable, Equatable, Codable {
    case aligned
    case fallback(FallbackReason)
  }

  public enum FallbackReason: Sendable, Equatable, Codable {
    case emptyResponse
    case malformed
    case truncated
  }

  public var comparison: IngredientComparison
  public var source: Source

  public init(comparison: IngredientComparison, source: Source) {
    self.comparison = comparison
    self.source = source
  }
}

public struct WorkbenchCompareAlignerClient: Sendable {
  /// Semantically aligns ingredient lines into the existing compare matrix shape.
  ///
  /// Transport failures from the model call are rethrown so the view layer can decide how to
  /// present a quiet deterministic fallback. Content failures in the model response are not thrown:
  /// malformed JSON, empty rows, or output with no valid assignments falls back to
  /// `WorkbenchCompare.ingredientComparison(working:candidates:)`.
  public var align: @Sendable (
    _ working: RecipeDetailData?,
    _ candidates: [RecipeDetailData],
    _ tier: ModelTier
  ) async throws -> WorkbenchAlignedComparison

  public init(
    align: @escaping @Sendable (
      _ working: RecipeDetailData?,
      _ candidates: [RecipeDetailData],
      _ tier: ModelTier
    ) async throws -> WorkbenchAlignedComparison
  ) {
    self.align = align
  }

  public func callAsFunction(
    working: RecipeDetailData?,
    candidates: [RecipeDetailData],
    tier: ModelTier
  ) async throws -> WorkbenchAlignedComparison {
    try await align(working, candidates, tier)
  }
}

extension WorkbenchCompareAlignerClient: DependencyKey {
  public static let liveValue = WorkbenchCompareAlignerClient { working, candidates, tier in
    @Dependency(\.modelClient) var modelClient
    let deterministic = WorkbenchCompare.ingredientComparison(working: working, candidates: candidates)
    let request = ModelCall(
      surface: .workbench,
      task: .workbenchComparison,
      tierResolution: .callerProvided,
      contextLayers: [.systemInstructions, .tasteProfile, .workbench, .candidates],
      tier: tier,
      system: instructions,
      prompt: prompt(working: working, candidates: candidates),
      maxTokens: responseTokenBudget(working: working, candidates: candidates),
      reasoningEffort: .medium,
      promptPreferenceKey: nil
    )
    let response = try await request.complete(using: modelClient)
    if response.wasTruncated {
      return WorkbenchAlignedComparison(comparison: deterministic, source: .fallback(.truncated))
    }
    if let comparison = parse(response.text, working: working, candidates: candidates) {
      return WorkbenchAlignedComparison(comparison: comparison, source: .aligned)
    }
    return WorkbenchAlignedComparison(
      comparison: deterministic,
      source: .fallback(classifyFallbackReason(response.text))
    )
  }

  public static let testValue = WorkbenchCompareAlignerClient { working, candidates, _ in
    WorkbenchAlignedComparison(
      comparison: WorkbenchCompare.ingredientComparison(working: working, candidates: candidates),
      source: .aligned
    )
  }

  static let instructions = """
    You align ingredient lines from several recipes for the same dish into a comparison matrix,
    grouping lines that play the same CULINARY ROLE across recipes.

    Rules:
    - Group by role, not by exact wording. "chicken breast" and "chicken thigh" are the same row
      (the chicken); "chile"/"chiles"/"chilies" are one row; "morita" and "chipotle" are the same
      role. Different actual ingredients stay separate rows.
    - Order rows for a cook: main protein first (regardless of cut), then aromatics (onion, garlic,
      ginger), then chiles/spices, then liquids/stock, then everything else.
    - Label each row with the shared ingredient in plain form (e.g. "Beef (chuck)", "Guajillo chile").
    - Assign each recipe's line to a row by its lineID. A recipe with no line for a row is simply
      absent from that row's assignments — do not force a match.
    - NEVER invent a lineID or a recipeID. Only reference IDs given in the input.
    - It is fine to leave a line unassigned to any row; unassigned lines are handled separately.
    - Return ONLY strict JSON: {"rows":[{"label":"...","role":"...","assignments":{"<recipeID>":"<lineID>"}}]}.
    """

  static func prompt(working: RecipeDetailData?, candidates: [RecipeDetailData]) -> String {
    """
    Align these ingredient lines into a comparison matrix.

    Input JSON:
    \(promptJSON(working: working, candidates: candidates))

    Return the ordered alignment JSON only.
    """
  }

  static func classifyFallbackReason(_ text: String) -> WorkbenchAlignedComparison.FallbackReason {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return .emptyResponse
    }
    guard
      let json = jsonObjectSlice(text),
      let data = json.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data),
      let object = raw as? [String: Any],
      let rawRows = object["rows"] as? [[String: Any]]
    else {
      return .malformed
    }
    return rawRows.isEmpty ? .emptyResponse : .malformed
  }

  public static func parse(
    _ text: String,
    working: RecipeDetailData?,
    candidates: [RecipeDetailData]
  ) -> IngredientComparison? {
    guard
      let json = jsonObjectSlice(text),
      let data = json.data(using: .utf8),
      let raw = try? JSONSerialization.jsonObject(with: data),
      let object = raw as? [String: Any],
      let rawRows = object["rows"] as? [[String: Any]],
      !rawRows.isEmpty
    else { return nil }

    let sources = orderedSources(working: working, candidates: candidates)
    guard !sources.isEmpty else { return IngredientComparison() }

    var lineLookup: [UUID: LineReference] = [:]
    var lineIDsByRecipe: [UUID: Set<UUID>] = [:]
    var orderedLineIDsByRecipe: [UUID: [UUID]] = [:]
    for (columnIndex, source) in sources.enumerated() {
      let lines = nonHeaderLines(in: source.detail)
      orderedLineIDsByRecipe[source.detail.recipe.id] = lines.map(\.id)
      lineIDsByRecipe[source.detail.recipe.id] = Set(lines.map(\.id))
      for line in lines {
        lineLookup[line.id] = LineReference(
          recipeID: source.detail.recipe.id,
          columnIndex: columnIndex,
          text: line.originalText
        )
      }
    }

    let columns = sources.map {
      IngredientMatrixColumn(
        id: $0.detail.recipe.id,
        title: $0.detail.recipe.title,
        role: $0.role
      )
    }

    var placedLineIDs: Set<UUID> = []
    var rows: [IngredientMatrixRow] = []
    for rawRow in rawRows {
      guard
        let label = (rawRow["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !label.isEmpty,
        let assignments = rawRow["assignments"] as? [String: Any]
      else { continue }

      var cells = Array<String?>(repeating: nil, count: columns.count)
      var rowPlaced = false
      for (recipeIDText, rawLineID) in assignments {
        guard
          let recipeID = UUID(uuidString: recipeIDText),
          let lineIDText = rawLineID as? String,
          let lineID = UUID(uuidString: lineIDText),
          lineIDsByRecipe[recipeID]?.contains(lineID) == true,
          !placedLineIDs.contains(lineID),
          let line = lineLookup[lineID],
          line.recipeID == recipeID
        else { continue }

        cells[line.columnIndex] = line.text
        placedLineIDs.insert(lineID)
        rowPlaced = true
      }

      guard rowPlaced else { continue }
      rows.append(
        IngredientMatrixRow(
          id: "\(rows.count)-\(label.labelSlug)",
          label: label,
          cells: cells
        )
      )
    }

    guard !placedLineIDs.isEmpty, !rows.isEmpty else { return nil }

    var completedColumns = columns
    for columnIndex in completedColumns.indices {
      let recipeID = completedColumns[columnIndex].id
      completedColumns[columnIndex].otherLines = orderedLineIDsByRecipe[recipeID, default: []]
        .filter { !placedLineIDs.contains($0) }
        .compactMap { lineLookup[$0]?.text }
    }

    return IngredientComparison(columns: completedColumns, rows: rows)
  }

  private static func promptJSON(working: RecipeDetailData?, candidates: [RecipeDetailData]) -> String {
    let recipes = orderedSources(working: working, candidates: candidates).map { source in
      PromptRecipe(
        recipeID: source.detail.recipe.id.uuidString,
        title: source.detail.recipe.title,
        isWorking: source.role == .working,
        lines: nonHeaderLines(in: source.detail).map {
          PromptLine(lineID: $0.id.uuidString, text: $0.originalText)
        }
      )
    }
    let data = (try? JSONEncoder.promptEncoder.encode(["recipes": recipes])) ?? Data()
    return String(data: data, encoding: .utf8) ?? #"{"recipes":[]}"#
  }

  private static func orderedSources(
    working: RecipeDetailData?,
    candidates: [RecipeDetailData]
  ) -> [(role: IngredientMatrixColumn.Role, detail: RecipeDetailData)] {
    var sources: [(role: IngredientMatrixColumn.Role, detail: RecipeDetailData)] = []
    if let working {
      sources.append((.working, working))
    }
    sources.append(contentsOf: candidates.map { (.candidate, $0) })
    return sources
  }

  private static func nonHeaderLines(in detail: RecipeDetailData) -> [IngredientLine] {
    detail.ingredientLines.enumerated()
      .filter { !$0.element.isHeader }
      .sorted {
        if $0.element.sortOrder == $1.element.sortOrder {
          $0.offset < $1.offset
        } else {
          $0.element.sortOrder < $1.element.sortOrder
        }
      }
      .map(\.element)
  }

  private static func jsonObjectSlice(_ text: String) -> String? {
    guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close
    else { return nil }
    return String(text[open...close])
  }

  private static func responseTokenBudget(
    working: RecipeDetailData?,
    candidates: [RecipeDetailData]
  ) -> Int {
    let lineCount = orderedSources(working: working, candidates: candidates)
      .map { nonHeaderLines(in: $0.detail).count }
      .reduce(0, +)
    return min(16_384, max(8_192, lineCount * 192))
  }
}

public extension WorkbenchAlignedComparison.Source {
  var isFallback: Bool {
    if case .fallback = self {
      return true
    }
    return false
  }
}

extension DependencyValues {
  public var workbenchCompareAligner: WorkbenchCompareAlignerClient {
    get { self[WorkbenchCompareAlignerClient.self] }
    set { self[WorkbenchCompareAlignerClient.self] = newValue }
  }
}

private struct PromptRecipe: Codable {
  var recipeID: String
  var title: String
  var isWorking: Bool
  var lines: [PromptLine]
}

private struct PromptLine: Codable {
  var lineID: String
  var text: String
}

private struct LineReference {
  var recipeID: UUID
  var columnIndex: Int
  var text: String
}

private extension JSONEncoder {
  static var promptEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}

private extension String {
  var labelSlug: String {
    var result = ""
    var previousWasSeparator = true
    for scalar in lowercased().unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        result.unicodeScalars.append(scalar)
        previousWasSeparator = false
      } else if !previousWasSeparator {
        result.append("-")
        previousWasSeparator = true
      }
    }
    if result.last == "-" {
      result.removeLast()
    }
    return result.isEmpty ? "row" : result
  }
}
