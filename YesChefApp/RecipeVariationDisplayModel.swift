import Foundation
import YesChefCore

/// A run of ingredient lines under an optional section heading, for grouped detail display.
struct IngredientLineGroup: Identifiable {
  let id: IngredientSection.ID
  var name: String?
  var lines: [IngredientLineDisplay]
}

struct IngredientLineDisplay: Identifiable {
  var line: IngredientLine
  var highlight: RecipeVariationIngredientHighlight?

  var id: IngredientLine.ID { line.id }
}

extension RecipeDetailModel {
  var recipe: Recipe? {
    detail?.recipe
  }

  var displayDetail: RecipeDetailData? {
    guard let detail else { return nil }
    guard let variation = detail.activeVariation else { return detail }
    return (try? detail.resolved(applying: variation)) ?? detail
  }

  var activeVariation: RecipeVariation? {
    detail?.activeVariation
  }

  var activeVariationNote: String? {
    guard let note = activeVariation?.note?.trimmingCharacters(in: .whitespacesAndNewlines),
          !note.isEmpty
    else { return nil }
    return note
  }

  var ingredientLines: [IngredientLine] {
    displayDetail?.ingredientLines.sorted { $0.sortOrder < $1.sortOrder } ?? []
  }

  var ingredientLineDisplays: [IngredientLineDisplay] {
    displayIngredientLines(for: nil)
  }

  var ingredientGroups: [IngredientLineGroup] {
    guard let detail = displayDetail else { return [] }
    let linesBySection = Dictionary(grouping: detail.ingredientLines) { $0.sectionID }
    return detail.ingredientSections
      .sorted { $0.sortOrder < $1.sortOrder }
      .compactMap { section in
        let lines = displayIngredientLines(
          for: section.id,
          foldedLines: (linesBySection[section.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }
        )
        guard !lines.isEmpty else { return nil }
        return IngredientLineGroup(id: section.id, name: section.name, lines: lines)
      }
  }

  var instructionSteps: [InstructionStep] {
    displayDetail?.instructionSteps.sorted { $0.sortOrder < $1.sortOrder } ?? []
  }

  var visibleNotes: [RecipeNote] {
    displayDetail?.notes.filter { $0.noteType != .retrospective } ?? []
  }

  private func displayIngredientLines(
    for sectionID: IngredientSection.ID?,
    foldedLines: [IngredientLine]? = nil
  ) -> [IngredientLineDisplay] {
    let foldedLines = foldedLines ?? ingredientLines
    guard
      let baseDetail = detail,
      let variation = baseDetail.activeVariation,
      let highlights = try? baseDetail.variationIngredientHighlights(for: variation)
    else {
      return foldedLines.map { IngredientLineDisplay(line: $0, highlight: nil) }
    }

    var displays = foldedLines.map { line in
      IngredientLineDisplay(line: line, highlight: highlights[line.id])
    }
    let foldedLineIDs = Set(foldedLines.map(\.id))
    let removedLines = baseDetail.ingredientLines
      .filter { line in
        highlights[line.id] == .removed
          && !foldedLineIDs.contains(line.id)
          && (sectionID == nil || line.sectionID == sectionID)
      }
      .map { IngredientLineDisplay(line: $0, highlight: .removed) }
    displays.append(contentsOf: removedLines)
    return displays.sorted { lhs, rhs in
      if lhs.line.sortOrder != rhs.line.sortOrder {
        return lhs.line.sortOrder < rhs.line.sortOrder
      }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }
}
