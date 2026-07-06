import Foundation
import LLMClientKit

public struct WorkbenchChatContext: Equatable, Sendable {
  public static let softCandidateCap = 5
  public static let onDeviceSerializedCharacterBudget = 24_000
  public static let frontierSerializedCharacterBudget = 160_000
  public static let serializedCharacterBudget = onDeviceSerializedCharacterBudget

  public var workbenchID: Workbench.ID?
  public var title: String
  public var notes: String?
  public var draftRecipe: RecipeChatRecipeContext?
  public var candidates: [WorkbenchCandidateChatContext]

  public init(
    workbenchID: Workbench.ID? = nil,
    title: String,
    notes: String? = nil,
    draftRecipe: RecipeChatRecipeContext? = nil,
    candidates: [WorkbenchCandidateChatContext] = []
  ) {
    self.workbenchID = workbenchID
    self.title = title
    self.notes = notes
    self.draftRecipe = draftRecipe
    self.candidates = candidates
  }

  public init(detail: WorkbenchDetailData) {
    self.init(
      workbenchID: detail.workbench.id,
      title: detail.workbench.title,
      notes: detail.workbench.notes,
      draftRecipe: detail.draftRecipeDetail.map(RecipeChatRecipeContext.init(detail:)),
      candidates: detail.candidateRows.map(WorkbenchCandidateChatContext.init(row:))
    )
  }

  public var seededContextDescription: String {
    let budgeted = budgetedSerialization(characterBudget: Self.onDeviceSerializedCharacterBudget)
    guard !budgeted.notes.isEmpty else {
      return "Seeded with full candidate ingredients and instructions."
    }
    return "Seeded with full candidate ingredients and instructions. \(budgeted.notes.joined(separator: " "))"
  }

  public func serialized(for tier: ModelTier) -> String {
    serialized(characterBudget: Self.serializedCharacterBudget(for: tier))
  }

  public func serialized(characterBudget: Int = Self.serializedCharacterBudget) -> String {
    budgetedSerialization(characterBudget: characterBudget).text
  }

  public static func serializedCharacterBudget(for tier: ModelTier) -> Int {
    switch tier {
    case .onDevice:
      onDeviceSerializedCharacterBudget
    case .frontier, .frontierPreferred:
      frontierSerializedCharacterBudget
    }
  }

  private func budgetedSerialization(characterBudget: Int) -> WorkbenchChatSerializedContext {
    let sortedCandidates = candidates.sorted(by: areWorkbenchChatCandidatesInIncreasingOrder)
    let cappedCandidates = Array(sortedCandidates.prefix(Self.softCandidateCap))
    for includedCount in stride(from: cappedCandidates.count, through: 0, by: -1) {
      let candidate = renderedContext(
        candidates: Array(cappedCandidates.prefix(includedCount)),
        omittedCandidateCount: sortedCandidates.count - includedCount
      )
      if candidate.text.count <= characterBudget || includedCount == 0 {
        return candidate
      }
    }
    return renderedContext(candidates: [], omittedCandidateCount: sortedCandidates.count)
  }

  private func renderedContext(
    candidates: [WorkbenchCandidateChatContext],
    omittedCandidateCount: Int
  ) -> WorkbenchChatSerializedContext {
    var budgetNotes: [String] = []
    if omittedCandidateCount > 0 {
      budgetNotes.append(
        "\(omittedCandidateCount) lower-priority candidate(s) were omitted so included candidates keep full ingredients and instructions."
      )
    }

    var lines = ["The user is looking at this recipe workbench:"]
    lines.append("- Title: \(title.isEmpty ? "(untitled)" : title)")
    if let notes {
      lines.append("- Workbench notes: \(notes.replacingOccurrences(of: "\n", with: " "))")
    }
    if let draftRecipe {
      lines.append("Current working recipe:")
      lines.append(draftRecipe.serialized())
    }
    if !budgetNotes.isEmpty {
      lines.append("Context budget notes:")
      for note in budgetNotes {
        lines.append("- \(note)")
      }
    }
    guard !candidates.isEmpty else {
      lines.append("Candidates: none included.")
      return WorkbenchChatSerializedContext(text: lines.joined(separator: "\n"), notes: budgetNotes)
    }

    lines.append("Candidates:")
    for candidate in candidates {
      lines.append("- \(candidate.title.isEmpty ? "(untitled)" : candidate.title)")
      lines.append("  - Candidate ID: \(candidate.id.uuidString)")
      if let recipeID = candidate.recipeID {
        lines.append("  - Recipe ID: \(recipeID.uuidString)")
      }
      if let annotation = candidate.annotation {
        lines.append("  - Cook annotation: \(annotation.replacingOccurrences(of: "\n", with: " "))")
      }
      if let subtitle = candidate.subtitle { lines.append("  - Subtitle: \(subtitle)") }
      if let summary = candidate.summary { lines.append("  - Summary: \(summary)") }
      if let servingsText = candidate.servingsText { lines.append("  - Servings: \(servingsText)") }
      if let yieldText = candidate.yieldText { lines.append("  - Yield: \(yieldText)") }
      if let prepTimeMinutes = candidate.prepTimeMinutes {
        lines.append("  - Prep time: \(prepTimeMinutes) minutes")
      }
      if let cookTimeMinutes = candidate.cookTimeMinutes {
        lines.append("  - Cook time: \(cookTimeMinutes) minutes")
      }
      if let totalTimeMinutes = candidate.totalTimeMinutes {
        lines.append("  - Total time: \(totalTimeMinutes) minutes")
      }
      append(sections: candidate.ingredientSections, title: "Ingredients", to: &lines)
      append(sections: candidate.instructionSections, title: "Instructions", to: &lines)
      if !candidate.notes.isEmpty {
        lines.append("  - Notes:")
        for note in candidate.notes {
          lines.append("    - \(note.replacingOccurrences(of: "\n", with: " "))")
        }
      }
    }
    return WorkbenchChatSerializedContext(text: lines.joined(separator: "\n"), notes: budgetNotes)
  }

  private func append(sections: [RecipeChatSection], title: String, to lines: inout [String]) {
    guard !sections.isEmpty else { return }
    lines.append("  - \(title):")
    for section in sections {
      if let name = section.name, !name.isEmpty {
        lines.append("    - \(name):")
        for line in section.lines {
          lines.append("      - \(line.replacingOccurrences(of: "\n", with: " "))")
        }
      } else {
        for line in section.lines {
          lines.append("    - \(line.replacingOccurrences(of: "\n", with: " "))")
        }
      }
    }
  }
}

public struct WorkbenchCandidateChatContext: Equatable, Sendable {
  public var id: WorkbenchCandidate.ID
  public var recipeID: Recipe.ID?
  public var title: String
  public var annotation: String?
  public var sortOrder: Int
  public var subtitle: String?
  public var summary: String?
  public var servingsText: String?
  public var yieldText: String?
  public var prepTimeMinutes: Int?
  public var cookTimeMinutes: Int?
  public var totalTimeMinutes: Int?
  public var ingredientSections: [RecipeChatSection]
  public var instructionSections: [RecipeChatSection]
  public var notes: [String]

  public init(
    id: WorkbenchCandidate.ID,
    recipeID: Recipe.ID? = nil,
    title: String,
    annotation: String? = nil,
    sortOrder: Int,
    subtitle: String? = nil,
    summary: String? = nil,
    servingsText: String? = nil,
    yieldText: String? = nil,
    prepTimeMinutes: Int? = nil,
    cookTimeMinutes: Int? = nil,
    totalTimeMinutes: Int? = nil,
    ingredientSections: [RecipeChatSection] = [],
    instructionSections: [RecipeChatSection] = [],
    notes: [String] = []
  ) {
    self.id = id
    self.recipeID = recipeID
    self.title = title
    self.annotation = annotation
    self.sortOrder = sortOrder
    self.subtitle = subtitle
    self.summary = summary
    self.servingsText = servingsText
    self.yieldText = yieldText
    self.prepTimeMinutes = prepTimeMinutes
    self.cookTimeMinutes = cookTimeMinutes
    self.totalTimeMinutes = totalTimeMinutes
    self.ingredientSections = ingredientSections
    self.instructionSections = instructionSections
    self.notes = notes
  }

  public init(row: WorkbenchCandidateRowData) {
    let recipeContext = row.recipeDetail.map(RecipeChatRecipeContext.init(detail:))
    self.init(
      id: row.candidate.id,
      recipeID: row.candidate.recipeID,
      title: row.displayTitle,
      annotation: row.candidate.annotation,
      sortOrder: row.candidate.sortOrder,
      subtitle: recipeContext?.subtitle,
      summary: recipeContext?.summary,
      servingsText: recipeContext?.servingsText,
      yieldText: recipeContext?.yieldText,
      prepTimeMinutes: recipeContext?.prepTimeMinutes,
      cookTimeMinutes: recipeContext?.cookTimeMinutes,
      totalTimeMinutes: recipeContext?.totalTimeMinutes,
      ingredientSections: recipeContext?.ingredientSections ?? [],
      instructionSections: recipeContext?.instructionSections ?? [],
      notes: recipeContext?.notes ?? []
    )
  }
}

private struct WorkbenchChatSerializedContext: Equatable {
  var text: String
  var notes: [String]
}

private func areWorkbenchChatCandidatesInIncreasingOrder(
  _ lhs: WorkbenchCandidateChatContext,
  _ rhs: WorkbenchCandidateChatContext
) -> Bool {
  if lhs.sortOrder != rhs.sortOrder {
    return lhs.sortOrder < rhs.sortOrder
  }
  let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
  if titleComparison != .orderedSame {
    return titleComparison == .orderedAscending
  }
  return lhs.id.uuidString < rhs.id.uuidString
}
