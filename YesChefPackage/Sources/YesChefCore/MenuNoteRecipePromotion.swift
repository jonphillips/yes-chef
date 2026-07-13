import Foundation

/// A reviewed recipe proposal made from a menu note-item. The original note stays intact until the
/// caller explicitly chooses to replace its menu row with the committed recipe.
public struct MenuNoteRecipePromotion: Equatable, Sendable {
  public var sourceItemID: MenuItem.ID
  public var menuID: Menu.ID
  public var originalTitle: String
  public var originalProse: String
  public var draftRecipe: WorkbenchDraftRecipe

  public init?(menuItem: MenuItem) {
    guard menuItem.kind == .note else { return nil }

    let prose = menuItem.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !prose.isEmpty else { return nil }

    sourceItemID = menuItem.id
    menuID = menuItem.menuID
    originalTitle = menuItem.title
    originalProse = prose
    draftRecipe = RecipeParseBuilder.draftRecipe(title: menuItem.title, prose: prose)
  }

  public func editorDraft(for approvedRecipe: WorkbenchDraftRecipe) -> RecipeEditorDraft {
    approvedRecipe.editorDraft(libraryPlacement: .main).withMenuNoteProvenance(
      originalTitle: originalTitle,
      originalProse: originalProse
    )
  }
}

private extension RecipeParseBuilder {
  /// The note adapter deliberately recognizes only explicit recipe headings. Anything it cannot
  /// identify remains in the immutable provenance copy and is visible in the review sheet, where the
  /// cook can reject the proposal rather than losing prose to an over-eager extraction.
  static func draftRecipe(title: String, prose: String) -> WorkbenchDraftRecipe {
    var ingredients: [String] = []
    var instructions: [String] = []
    var notes: [String] = []
    var section = Section.introduction

    for line in prose.components(separatedBy: .newlines) {
      let cleaned = cleanedLine(line)
      guard !cleaned.isEmpty else { continue }

      if let heading = Section(heading: cleaned) {
        section = heading
        continue
      }

      switch section {
      case .introduction:
        notes.append(cleaned)
      case .ingredients:
        ingredients.append(cleaned)
      case .instructions:
        instructions.append(cleaned.removingStepNumber)
      }
    }

    return WorkbenchDraftRecipe(
      title: title,
      ingredientLines: ingredients,
      instructionLines: instructions,
      notes: notes,
      rationale: "Promoted from a menu note."
    )
  }

  private enum Section {
    case introduction
    case ingredients
    case instructions

    init?(heading: String) {
      let normalized = heading
        .trimmingCharacters(in: CharacterSet(charactersIn: "#: ").union(.whitespacesAndNewlines))
        .lowercased()
      switch normalized {
      case "ingredients": self = .ingredients
      case "instructions", "method", "directions", "preparation": self = .instructions
      default: return nil
      }
    }
  }

  private static func cleanedLine(_ line: String) -> String {
    var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
    while cleaned.hasPrefix("#") { cleaned.removeFirst() }
    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.hasPrefix("- ") || cleaned.hasPrefix("* ") || cleaned.hasPrefix("• ") {
      cleaned.removeFirst(2)
    }
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private extension String {
  var removingStepNumber: String {
    let prefix = prefix { $0.isNumber }
    guard !prefix.isEmpty else { return self }
    let remainder = dropFirst(prefix.count)
    guard remainder.first == "." || remainder.first == ")" else { return self }
    return String(remainder.dropFirst())
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private extension RecipeEditorDraft {
  func withMenuNoteProvenance(
    originalTitle: String,
    originalProse: String
  ) -> RecipeEditorDraft {
    var draft = self
    let condensedProse = originalProse
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    let provenanceNote = "From menu note \"\(originalTitle)\":\n\(condensedProse)"
    draft.noteText = draft.noteText.isEmpty
      ? provenanceNote
      : draft.noteText + "\n\n" + provenanceNote
    return draft
  }
}
