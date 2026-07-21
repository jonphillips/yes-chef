import Foundation
import LLMClientKit

public struct WorkbenchChatContext: Equatable, Sendable {
  public static let softCandidateCap = 5
  // Apple reports an on-device context near 4k tokens. At the shared 4 chars/token estimate,
  // 9k context chars leaves room for base instructions, chat history, prompt preferences, and reply.
  public static let onDeviceSerializedCharacterBudget = 9_000
  // 2.4k chars is roughly 600 estimated tokens: enough for several recent log entries while
  // preventing the append-only log from crowding every candidate out of the on-device window.
  public static let onDeviceLogCharacterBudget = 2_400
  public static let frontierSerializedCharacterBudget = 160_000
  public static let serializedCharacterBudget = onDeviceSerializedCharacterBudget

  public var workbenchID: Workbench.ID?
  public var title: String
  public var notes: String?
  public var draftRecipe: RecipeChatRecipeContext?
  public var logEntries: [WorkbenchLogEntryChatContext]
  public var candidates: [WorkbenchCandidateChatContext]

  public init(
    workbenchID: Workbench.ID? = nil,
    title: String,
    notes: String? = nil,
    draftRecipe: RecipeChatRecipeContext? = nil,
    logEntries: [WorkbenchLogEntryChatContext] = [],
    candidates: [WorkbenchCandidateChatContext] = []
  ) {
    self.workbenchID = workbenchID
    self.title = title
    self.notes = notes
    self.draftRecipe = draftRecipe
    self.logEntries = logEntries
    self.candidates = candidates
  }

  public init(detail: WorkbenchDetailData) {
    self.init(
      workbenchID: detail.workbench.id,
      title: detail.workbench.title,
      notes: detail.workbench.notes,
      draftRecipe: detail.draftRecipeDetail.map(RecipeChatRecipeContext.init(detail:)),
      logEntries: detail.logEntries.map(WorkbenchLogEntryChatContext.init(entry:)),
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

  /// External compare is deliberately prose-only: the deterministic matrix remains in-app, while the
  /// hand-off contributes named differences and claims that a cook can read in the workbench log.
  public func compareHandoffPrompt() -> String {
    """
    Compare the candidate recipes in this workbench. Return a handful of named differences with a concrete claim attached, one per line. Do not walk through every recipe or restate an ingredient matrix; Yes Chef already presents that deterministically.

    \(serialized(characterBudget: Self.frontierSerializedCharacterBudget))
    """
  }

  public func experimentsHandoffPrompt() -> String {
    """
    Propose a small set of distinct experiments for this workbench. Each experiment should test one concrete change against a specific expected result. Experiments are untested conjectures, so do not return learnings.

    \(serialized(characterBudget: Self.frontierSerializedCharacterBudget))
    """
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
        omittedCandidateCount: sortedCandidates.count - includedCount,
        characterBudget: characterBudget
      )
      if candidate.text.count <= characterBudget || includedCount == 0 {
        return candidate
      }
    }
    return renderedContext(
      candidates: [],
      omittedCandidateCount: sortedCandidates.count,
      characterBudget: characterBudget
    )
  }

  private func renderedContext(
    candidates: [WorkbenchCandidateChatContext],
    omittedCandidateCount: Int,
    characterBudget: Int
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
    appendLogEntries(to: &lines, characterBudget: Self.logCharacterBudget(for: characterBudget), notes: &budgetNotes)
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
      if let sourceName = candidate.sourceName {
        lines.append("  - Source: \(sourceName)")
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

  private static func logCharacterBudget(for characterBudget: Int) -> Int {
    guard characterBudget > onDeviceSerializedCharacterBudget else {
      return min(onDeviceLogCharacterBudget, characterBudget)
    }
    return characterBudget * onDeviceLogCharacterBudget / onDeviceSerializedCharacterBudget
  }

  private func appendLogEntries(to lines: inout [String], characterBudget: Int, notes: inout [String]) {
    guard !logEntries.isEmpty else { return }
    let rendered = renderedLogEntries().joined(separator: "\n")
    if rendered.count <= characterBudget {
      lines.append(rendered)
      return
    }

    notes.append("Workbench log was trimmed to recent text so it stays within its context slice.")
    lines.append("Workbench log (trimmed to fit context budget):")
    let clipped = rendered.suffix(characterBudget)
    if let firstNewline = clipped.firstIndex(of: "\n") {
      lines.append(String(clipped[clipped.index(after: firstNewline)...]))
    } else {
      lines.append(String(clipped))
    }
  }

  private func renderedLogEntries() -> [String] {
    var lines = ["Workbench log:"]
    for entry in logEntries.sorted(by: areWorkbenchLogEntriesInIncreasingOrder) {
      lines.append(contentsOf: renderedLogEntry(entry))
    }
    return lines
  }

  private func renderedLogEntry(_ entry: WorkbenchLogEntryChatContext) -> [String] {
    var lines = ["- \(entry.kind.title) (\(entry.dateCreated.formatted(date: .abbreviated, time: .shortened))):"]
    if let hypothesis = entry.hypothesis,
       let change = entry.change,
       let rationale = entry.rationale
    {
      lines.append("  - Hypothesis: \(hypothesis.replacingOccurrences(of: "\n", with: " "))")
      lines.append("  - Change: \(change.replacingOccurrences(of: "\n", with: " "))")
      lines.append("  - Rationale: \(rationale.replacingOccurrences(of: "\n", with: " "))")
    } else {
      lines.append("  - \(entry.body.replacingOccurrences(of: "\n", with: " "))")
    }
    if let outcome = entry.outcome {
      lines.append("  - Outcome: \(outcome.replacingOccurrences(of: "\n", with: " "))")
    }
    if let relatedRecipeID = entry.relatedRecipeID {
      lines.append("  - Related recipe ID: \(relatedRecipeID.uuidString)")
    }
    return lines
  }
}

public struct WorkbenchLogEntryChatContext: Equatable, Sendable {
  public var id: WorkbenchLogEntry.ID
  public var kind: WorkbenchLogEntryKind
  public var body: String
  public var hypothesis: String?
  public var change: String?
  public var rationale: String?
  public var outcome: String?
  public var relatedRecipeID: Recipe.ID?
  public var sortOrder: Int
  public var dateCreated: Date

  public init(
    id: WorkbenchLogEntry.ID,
    kind: WorkbenchLogEntryKind,
    body: String,
    hypothesis: String? = nil,
    change: String? = nil,
    rationale: String? = nil,
    outcome: String? = nil,
    relatedRecipeID: Recipe.ID? = nil,
    sortOrder: Int,
    dateCreated: Date
  ) {
    self.id = id
    self.kind = kind
    self.body = body
    self.hypothesis = hypothesis
    self.change = change
    self.rationale = rationale
    self.outcome = outcome
    self.relatedRecipeID = relatedRecipeID
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
  }

  public init(entry: WorkbenchLogEntry) {
    self.init(
      id: entry.id,
      kind: entry.kind,
      body: entry.body,
      hypothesis: entry.hypothesis,
      change: entry.change,
      rationale: entry.rationale,
      outcome: entry.outcome,
      relatedRecipeID: entry.relatedRecipeID,
      sortOrder: entry.sortOrder,
      dateCreated: entry.dateCreated
    )
  }
}

public struct WorkbenchCandidateChatContext: Equatable, Sendable {
  public var id: WorkbenchCandidate.ID
  public var recipeID: Recipe.ID?
  public var title: String
  public var sourceName: String?
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
    sourceName: String? = nil,
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
    self.sourceName = sourceName
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
      sourceName: row.recipeDetail?.source?.workbenchDisplayName,
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

private func areWorkbenchLogEntriesInIncreasingOrder(
  _ lhs: WorkbenchLogEntryChatContext,
  _ rhs: WorkbenchLogEntryChatContext
) -> Bool {
  if lhs.sortOrder != rhs.sortOrder {
    return lhs.sortOrder < rhs.sortOrder
  }
  if lhs.dateCreated != rhs.dateCreated {
    return lhs.dateCreated < rhs.dateCreated
  }
  return lhs.id.uuidString < rhs.id.uuidString
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
