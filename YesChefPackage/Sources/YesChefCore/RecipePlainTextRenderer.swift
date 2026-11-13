import Foundation

public enum RecipePlainTextRenderer {
  public static func render(_ detail: RecipeDetailData) -> String {
    var lines = [detail.recipe.title]

    if let source = detail.source {
      append(source.name, to: &lines)
      append(source.url, to: &lines)
    }

    let recipe = detail.recipe
    let yield = recipe.yieldText?.nonEmptyRecipeText
      ?? recipe.servingsText?.nonEmptyRecipeText
      ?? recipe.servings.map(IngredientScaler.formattedQuantity)
    append(yield, to: &lines)
    append(recipe.prepTimeMinutes.map { "Prep time: \($0) minutes" }, to: &lines)
    append(recipe.cookTimeMinutes.map { "Cook time: \($0) minutes" }, to: &lines)
    append(recipe.totalTimeMinutes.map { "Total time: \($0) minutes" }, to: &lines)

    let ingredientLines = sortedIngredientLines(detail)
    if !ingredientLines.isEmpty {
      lines.append("")
      lines.append("Ingredients")
      for (section, sectionLines) in ingredientLines {
        if let name = section?.name?.nonEmptyRecipeText {
          lines.append("")
          lines.append(name)
        }
        lines.append(contentsOf: sectionLines.map { "- \(IngredientScaler.scaledText(for: $0, factor: 1))" })
      }
    }

    let instructionGroups = detail.instructionGroups
    if !instructionGroups.isEmpty {
      lines.append("")
      lines.append("Directions")
      for group in instructionGroups {
        if let name = group.name {
          lines.append("")
          lines.append(name)
        }
        lines.append(contentsOf: group.steps.enumerated().map { index, step in "\(index + 1). \(step.text)" })
      }
    }

    let notes = detail.notes
      .sorted {
        if $0.dateCreated != $1.dateCreated { return $0.dateCreated < $1.dateCreated }
        return $0.id.uuidString < $1.id.uuidString
      }
      .compactMap { $0.text.nonEmptyRecipeText }
    if !notes.isEmpty {
      lines.append("")
      lines.append("Notes")
      lines.append(contentsOf: notes)
    }

    return lines.joined(separator: "\n")
  }

  private static func append(_ text: String?, to lines: inout [String]) {
    guard let text = text?.nonEmptyRecipeText else { return }
    lines.append(text)
  }

  private static func sortedIngredientLines(
    _ detail: RecipeDetailData
  ) -> [(section: IngredientSection?, lines: [IngredientLine])] {
    let linesBySection = Dictionary(grouping: detail.ingredientLines, by: \.sectionID)
    let sections = detail.ingredientSections.sorted {
      if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
      return $0.id.uuidString < $1.id.uuidString
    }
    var result = sections.compactMap { section -> (IngredientSection?, [IngredientLine])? in
      guard let lines = linesBySection[section.id], !lines.isEmpty else { return nil }
      return (section, lines.sorted(by: ingredientLineOrder))
    }
    let knownIDs = Set(sections.map(\.id))
    let orphanLines = detail.ingredientLines
      .filter { !knownIDs.contains($0.sectionID) }
      .sorted(by: ingredientLineOrder)
    if !orphanLines.isEmpty { result.append((nil, orphanLines)) }
    return result
  }

  private static func ingredientLineOrder(_ lhs: IngredientLine, _ rhs: IngredientLine) -> Bool {
    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
    return lhs.id.uuidString < rhs.id.uuidString
  }
}

private extension String {
  var nonEmptyRecipeText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
